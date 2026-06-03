//
//  StashNativeCardSafari.m
//  StashNative
//
//  External-browser / SFSafariViewController handling: openBrowser/closeBrowser, the in-card
//  external-payment Safari handoff that keeps/creates a dedicated portrait window and uses the
//  orientation swizzle from StashNativeCardOrientation, Safari dismissal, and the close/dismiss
//  delegate callbacks. StashNativeCard category holds the public and private entry points;
//  StashNativeCardInternal category holds the SFSafariViewControllerDelegate teardown.
//

#import "StashNativeCard.h"
#import "StashNativeCardInternal.h"
#import "StashNativeCardPrivate.h"
#import "StashNativeCardOrientation.h"

// Private Safari entry points on StashNativeCard.
@interface StashNativeCard (SafariPrivate)
- (void)openInSafariViewController:(NSString *)url;
- (UIViewController *)createSafariPortraitPresenter;
- (void)didFinishSafariDismiss;
- (void)dismissSafariViewController;
@end

#if !__has_feature(objc_arc)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshadow"
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

/** YES when the current SFSafariViewController was opened via openBrowser. */
static BOOL _safariOpenedViaOpenBrowser = NO;
/** YES when stashNativeCardDidCloseBrowser is still pending delivery. */
static BOOL _safariBrowserCloseDelegatePending = NO;

static void resetSafariOpenBrowserTrackingFlags(void) {
    _safariOpenedViaOpenBrowser = NO;
    _safariBrowserCloseDelegatePending = NO;
}

static const NSTimeInterval kRotationDelayAfterLandscape = 0.35;

@implementation StashNativeCard (Safari)

- (void)openBrowserWithURL:(NSString *)url {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self openBrowserWithURL:url]; });
        return;
    }
    if (url == nil || url.length == 0) {
        return;
    }
    _safariOpenedViaOpenBrowser = YES;
    _safariBrowserCloseDelegatePending = YES;
    // External browser URLs are opened as-is; theme is applied only to in-card content.
    [self openInSafariViewController:url];
}

- (void)closeBrowser {
    [self dismissSafariViewController];
}

- (void)openInSafariViewController:(NSString *)url {
    NSURL *nsurl = [NSURL URLWithString:url];
    if (!nsurl) {
        resetSafariOpenBrowserTrackingFlags();
        return;
    }
    // SFSafariViewController only supports web URLs; reject any non-http(s) scheme (also avoids a crash).
    NSString *scheme = nsurl.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        resetSafariOpenBrowserTrackingFlags();
        return;
    }

    SFSafariViewController *safariVC = [[SFSafariViewController alloc] initWithURL:nsurl];
    safariVC.delegate = [StashNativeCardInternal sharedInstance];
    [StashNativeCardInternal sharedInstance].currentSafariViewController = safariVC;

    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    UIViewController *presenter;
    // Seconds to wait after a rotation request before presenting Safari.
    NSTimeInterval rotationDelay = 0.0;

    if (internal.portraitWindow) {
        // Portrait window alive: card handoff or inline card Safari.
        // Set the portrait window root to a new SafariPortraitContainerViewController.
        SafariPortraitContainerViewController *safariContainer =
            [[SafariPortraitContainerViewController alloc] init];
        safariContainer.view.backgroundColor = stash_sheetBackgroundUIColor();
        internal.portraitWindow.rootViewController = safariContainer;
        presenter = safariContainer;

        // Clear the handoff-in-progress flag.
        internal.isHandingOffPortraitWindowToSafari = NO;

        // Request portrait when the scene is in landscape.
        CGRect sceneBounds = [UIScreen mainScreen].bounds;
        BOOL sceneIsLandscape = (sceneBounds.size.width > sceneBounds.size.height);
        if (sceneIsLandscape) {
            // Set the post-landscape rotation delay and request portrait.
            rotationDelay = kRotationDelayAfterLandscape;
            if (@available(iOS 16.0, *)) {
                UIWindowScene *scene = internal.portraitWindow.windowScene;
                if (scene) {
                    UIWindowSceneGeometryPreferencesIOS *prefs =
                        [[UIWindowSceneGeometryPreferencesIOS alloc]
                            initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait];
                    [scene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *error) {
                        STASH_DEBUG_LOG(@"StashNative: geometry update error: %@", error);
                    }];
                }
            } else {
                [[UIDevice currentDevice] setValue:@(UIInterfaceOrientationPortrait)
                                            forKey:@"orientation"];
                [UIViewController attemptRotationToDeviceOrientation];
            }
        }
        // else: scene already portrait, rotationDelay stays 0.

    } else if (stash_forcePortraitOnCheckout && !_safariOpenedViaOpenBrowser) {
        // External payment handoff from a forcePortrait card: present Safari in a portrait window.
        CGRect screen = [UIScreen mainScreen].bounds;
        BOOL wasLandscape = (screen.size.width > screen.size.height);
        rotationDelay = wasLandscape ? kRotationDelayAfterLandscape : 0.0;
        presenter = [self createSafariPortraitPresenter];
    } else {
        presenter = stash_getTopPresentedViewController();
    }

    // Present Safari after rotationDelay seconds. rotationDelay 0 fires on the next runloop turn.
    BOOL lockPortrait = (internal.portraitWindow != nil || internal.safariPresentationWindow != nil);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(rotationDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        // Abort when the current SafariViewController changed during the delay.
        if (rotationDelay > 0 && internal.currentSafariViewController != safariVC) {
            resetSafariOpenBrowserTrackingFlags();
            internal.currentSafariViewController = nil;
            return;
        }
        if (presenter == nil) {
            resetSafariOpenBrowserTrackingFlags();
            internal.currentSafariViewController = nil;
            return;
        }
        // Lock the SDK window to portrait. Cleared in safariViewControllerDidFinish:.
        if (lockPortrait) {
            internal.isSafariPortraitLocked = YES;
        }
        [presenter presentViewController:safariVC animated:YES completion:^{
            stash_isCardCurrentlyPresented = YES;
        }];
    });
}

- (UIViewController *)createSafariPortraitPresenter {
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];

    if (!self.disableAutoOrientationUnlock) {
        stashInstallOrientationSwizzleIfNeeded();
    }

    UIWindow *gameWindow = stash_getKeyWindow();
    internal.previousKeyWindow = gameWindow;

    CGRect screen = [UIScreen mainScreen].bounds;
    BOOL isLS = screen.size.width > screen.size.height;
    CGRect portraitFrame = CGRectMake(0, 0,
        isLS ? screen.size.height : screen.size.width,
        isLS ? screen.size.width  : screen.size.height);

    UIWindow *safariWindow = [[UIWindow alloc] initWithFrame:portraitFrame];
    stash_attachWindowToKeyWindowScene(safariWindow, gameWindow);
    safariWindow.windowLevel = UIWindowLevelAlert;

    SafariPortraitContainerViewController *vc = [[SafariPortraitContainerViewController alloc] init];
    safariWindow.rootViewController = vc;
    internal.safariPresentationWindow = safariWindow;
    [safariWindow makeKeyAndVisible];

    // Capture current orientation and request portrait.
    if (@available(iOS 16.0, *)) {
        UIWindowScene *scene = safariWindow.windowScene;
        if (scene) {
            UIInterfaceOrientation cur = scene.interfaceOrientation;
            if (UIInterfaceOrientationIsLandscape(cur)) {
                internal.previousSceneOrientationMask = stashOrientationMaskForOrientation(cur);
            } else {
                internal.previousSceneOrientationMask = UIInterfaceOrientationMaskAll;
            }
            UIWindowSceneGeometryPreferencesIOS *prefs = [[UIWindowSceneGeometryPreferencesIOS alloc]
                initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait];
            [scene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *error) {
                STASH_DEBUG_LOG(@"StashNative Safari portrait request failed: %@", error);
            }];
        }
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        UIInterfaceOrientation cur = [[UIApplication sharedApplication] statusBarOrientation];
#pragma clang diagnostic pop
        if (UIInterfaceOrientationIsLandscape(cur)) {
            internal.previousSceneOrientationMask = stashOrientationMaskForOrientation(cur);
        } else {
            internal.previousSceneOrientationMask = UIInterfaceOrientationMaskAll;
        }
        [[UIDevice currentDevice] setValue:@(UIInterfaceOrientationPortrait) forKey:@"orientation"];
        [UIViewController attemptRotationToDeviceOrientation];
    }
    return vc;
}

- (void)didFinishSafariDismiss {
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    internal.currentSafariViewController = nil;
    if (self.delegate && [self.delegate respondsToSelector:@selector(stashNativeCardDidDismiss)]) {
        [self.delegate stashNativeCardDidDismiss];
    }
    if (_safariBrowserCloseDelegatePending) {
        _safariBrowserCloseDelegatePending = NO;
        if (self.delegate && [self.delegate respondsToSelector:@selector(stashNativeCardDidCloseBrowser)]) {
            [self.delegate stashNativeCardDidCloseBrowser];
        }
    }
}

- (void)dismissSafariViewController {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self dismissSafariViewController]; });
        return;
    }
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    if (internal.currentSafariViewController) {
        [internal.currentSafariViewController dismissViewControllerAnimated:YES completion:^{
            [self didFinishSafariDismiss];
        }];
    }
}

- (void)dismissSafariViewControllerWithResult:(BOOL)success {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self dismissSafariViewControllerWithResult:success]; });
        return;
    }
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    if (internal.currentSafariViewController) {
        if (success) {
            if ([self.delegate respondsToSelector:@selector(stashNativeCardDidCompletePaymentWithOrder:)]) {
                [self.delegate stashNativeCardDidCompletePaymentWithOrder:nil];
            } else if ([self.delegate respondsToSelector:@selector(stashNativeCardDidCompletePayment)]) {
                [self.delegate stashNativeCardDidCompletePayment];
            }
        } else {
            if (self.delegate && [self.delegate respondsToSelector:@selector(stashNativeCardDidFailPayment)]) {
                [self.delegate stashNativeCardDidFailPayment];
            }
        }
        [internal.currentSafariViewController dismissViewControllerAnimated:YES completion:^{
            [self didFinishSafariDismiss];
        }];
    }
}

@end

@implementation StashNativeCardInternal (Safari)

- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller {
    // Unlock portrait before window teardown.
    self.isSafariPortraitLocked = NO;

    // If we created a dedicated Safari portrait window (standalone browser path), tear it down.
    if (self.safariPresentationWindow) {
        [self teardownPresentationWindow:self.safariPresentationWindow];
        self.safariPresentationWindow = nil;
    }

    if (_safariOpenedViaOpenBrowser) {
        _safariOpenedViaOpenBrowser = NO;
        stash_isCardCurrentlyPresented = NO;
        self.currentSafariViewController = nil;

        // Tear down the portrait window when present.
        if (self.portraitWindow) {
            [self teardownPresentationWindow:self.portraitWindow];
            self.portraitWindow = nil;
        }
        if (_safariBrowserCloseDelegatePending) {
            _safariBrowserCloseDelegatePending = NO;
            id<StashNativeCardDelegate> delegate = [StashNativeCard sharedInstance].delegate;
            if (delegate != nil
                && [delegate respondsToSelector:@selector(stashNativeCardDidCloseBrowser)]) {
                [delegate stashNativeCardDidCloseBrowser];
            }
        }
    } else {
        [self cleanupCardInstance];
        [self callDelegateCallbackOnce];
    }
}

@end

#if !__has_feature(objc_arc)
#pragma clang diagnostic pop
#endif
