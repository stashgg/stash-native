#import "RegressionSupport.h"
#import "../../Sources/StashNative/StashNativePrivate.h"

@interface StashPresentationProbeView : UIView
@property (nonatomic) UIUserInterfaceSizeClass verticalClass;
@end
@implementation StashPresentationProbeView
- (UITraitCollection *)traitCollection {
    return [UITraitCollection traitCollectionWithVerticalSizeClass:self.verticalClass];
}
@end

@interface StashTransitionProbeView : UIView
@property (nonatomic) UIUserInterfaceSizeClass horizontalClass;
@property (nonatomic) UIUserInterfaceSizeClass verticalClass;
@end
@implementation StashTransitionProbeView
- (UITraitCollection *)traitCollection {
    return [UITraitCollection traitCollectionWithTraitsFromCollections:@[
        [UITraitCollection traitCollectionWithHorizontalSizeClass:self.horizontalClass],
        [UITraitCollection traitCollectionWithVerticalSizeClass:self.verticalClass]]];
}
@end

NSDictionary *StashCardTransitionProbe(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSDictionary *input in @[
        @{@"name":@"tablet", @"h":@(UIUserInterfaceSizeClassRegular), @"v":@(UIUserInterfaceSizeClassRegular)},
        @{@"name":@"phone", @"h":@(UIUserInterfaceSizeClassCompact), @"v":@(UIUserInterfaceSizeClassRegular)},
        @{@"name":@"phoneLandscape", @"h":@(UIUserInterfaceSizeClassRegular), @"v":@(UIUserInterfaceSizeClassCompact)}]) {
        StashCardSession *session = [StashCardSession new];
        session.config = [StashNativeCardConfig new];
        UIViewController *presenter = [UIViewController new];
        StashTransitionProbeView *view = [[StashTransitionProbeView alloc] initWithFrame:CGRectMake(0, 0, 1000, 1200)];
        view.horizontalClass = [input[@"h"] integerValue];
        view.verticalClass = [input[@"v"] integerValue];
        presenter.view = view; session.presenter = presenter;
        StashCardViewController *controller = [StashCardViewController new];
        session.controller = controller; controller.session = session; [controller configurePresentation];
        result[input[@"name"]] = @(controller.modalTransitionStyle);
    }
    return result;
}

NSDictionary *StashNativePresentationProbe(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSDictionary *input in @[
        @{@"name":@"compactPhone", @"width":@390, @"height":@700},
        @{@"name":@"wideTablet", @"width":@1000, @"height":@1200},
        @{@"name":@"narrowPane", @"width":@320, @"height":@900},
        @{@"name":@"compactHeight", @"width":@700, @"height":@320, @"compact":@YES}]) {
        StashCardSession *session = [StashCardSession new];
        session.config = [StashNativeCardConfig new];
        UIViewController *presenter = [UIViewController new];
        StashPresentationProbeView *view = [[StashPresentationProbeView alloc] initWithFrame:
            CGRectMake(0, 0, [input[@"width"] doubleValue], [input[@"height"] doubleValue])];
        view.verticalClass = [input[@"compact"] boolValue] ? UIUserInterfaceSizeClassCompact : UIUserInterfaceSizeClassRegular;
        presenter.view = view; session.presenter = presenter;
        StashCardViewController *controller = [StashCardViewController new];
        session.controller = controller; controller.session = session; [controller configurePresentation];
        UISheetPresentationController *sheet = controller.sheetPresentationController;
        BOOL native = sheet && sheet.delegate == session &&
            controller.modalPresentationStyle == UIModalPresentationFormSheet && !controller.transitioningDelegate;
        BOOL selected = [sheet.selectedDetentIdentifier isEqualToString:[controller nativeDetentIdentifierForExpanded:NO]];
        BOOL stops = sheet.detents.count >= 1;
        if (@available(iOS 16.0, *)) {
            stops &= [[controller nativeDetentIdentifierForExpanded:NO] isEqualToString:@"stash-resting"] &&
                [[controller nativeDetentIdentifierForExpanded:YES] isEqualToString:@"stash-expanded"];
        } else {
            BOOL compact = [input[@"compact"] boolValue];
            stops &= sheet.detents.count == (compact ? 1 : 2) &&
                [[controller nativeDetentIdentifierForExpanded:YES] isEqualToString:UISheetPresentationControllerDetentIdentifierLarge] &&
                [[controller nativeDetentIdentifierForExpanded:NO] isEqualToString:compact
                    ? UISheetPresentationControllerDetentIdentifierLarge : UISheetPresentationControllerDetentIdentifierMedium];
        }
        session.processing = YES; [controller updateDismissalPolicy];
        BOOL locked = controller.modalInPresentation && !sheet.prefersGrabberVisible;
        session.processing = NO; [controller updateDismissalPolicy];
        BOOL restored = !controller.modalInPresentation && sheet.prefersGrabberVisible;
        // UIKit ignores the width of a zero-height preferred size, which locked phone-landscape cards to 540 points.
        BOOL wide = [input[@"width"] doubleValue] >= 600;
        BOOL widthHonored = !wide || (controller.preferredContentSize.height > 0 &&
            controller.preferredContentSize.width == session.config.preferredContentWidth);
        result[input[@"name"]] = @(native && selected && stops && locked && restored && widthHonored);
        [session cleanup];
    }
    return result;
}

@interface StashOccupiedPresentationHost : UIViewController
@property (nonatomic, strong) UIViewController *otherPresentation;
@property (nonatomic) BOOL dismissing;
@end
@implementation StashOccupiedPresentationHost
- (UIViewController *)presentedViewController { return self.otherPresentation; }
- (BOOL)isBeingDismissed { return self.dismissing; }
@end

NSDictionary *StashPresentationLifetimeProbe(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *name in @[@"closed", @"replacement", @"detached", @"occupied", @"dismissing"]) {
        StashNative *owner = [StashNative new];
        StashCardSession *session = [StashCardSession new];
        owner.session = session; session.owner = owner; session.config = [StashNativeCardConfig new];
        session.url = @"about:blank";
        StashOccupiedPresentationHost *presenter = [StashOccupiedPresentationHost new];
        UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 700)];
        window.rootViewController = presenter; [window addSubview:presenter.view]; session.presenter = presenter;
        StashCardSession *replacement = nil;
        if ([name isEqualToString:@"closed"]) session.closing = YES;
        if ([name isEqualToString:@"replacement"]) {
            replacement = [StashCardSession new]; replacement.owner = owner; owner.session = replacement;
        }
        if ([name isEqualToString:@"detached"]) [presenter.view removeFromSuperview];
        if ([name isEqualToString:@"occupied"]) presenter.otherPresentation = [UIViewController new];
        if ([name isEqualToString:@"dismissing"]) presenter.dismissing = YES;
        UIViewController *other = presenter.otherPresentation;
        [session presentCheckout];
        BOOL untouched = !session.webView && !session.controller && presenter.otherPresentation == other;
        if (replacement) untouched &= owner.session == replacement;
        if ([name isEqualToString:@"detached"] || [name isEqualToString:@"occupied"] || [name isEqualToString:@"dismissing"])
            untouched &= owner.session == nil;
        result[name] = @(untouched);
        [session cleanup]; [owner resetPresentationState]; window.hidden = YES;
    }
    return result;
}

@interface StashHostDismissalReceiver : NSObject <StashNativeDelegate>
@property (nonatomic, strong) NSMutableArray<NSString *> *events;
@end
@implementation StashHostDismissalReceiver
- (instancetype)init {
    if ((self = [super init])) _events = [NSMutableArray new];
    return self;
}
- (void)stashNativeDidDismissCard { [self.events addObject:@"card-dismissed"]; }
- (void)stashNativeDidDismissBrowser { [self.events addObject:@"browser-dismissed"]; }
- (void)stashNativeDidEncounterNetworkError { [self.events addObject:@"network-error"]; }
@end

static void StashAwaitHostCondition(BOOL (^condition)(void), CFAbsoluteTime deadline, void (^completion)(BOOL)) {
    if (condition() || CFAbsoluteTimeGetCurrent() >= deadline) { completion(condition()); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        StashAwaitHostCondition(condition, deadline, completion);
    });
}

void StashHostDismissalProbe(NSString *mode, void (^completion)(NSDictionary *)) {
    UIWindow *previous = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) previous = window;
    UIWindow *window = previous.windowScene ? [[UIWindow alloc] initWithWindowScene:previous.windowScene] :
        [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    UIViewController *root = [UIViewController new];
    window.rootViewController = root; [window makeKeyAndVisible];
    UIViewController *modal = [UIViewController new];
    modal.modalPresentationStyle = UIModalPresentationFullScreen;
    StashNative *owner = [StashNative new];
    StashHostDismissalReceiver *receiver = [StashHostDismissalReceiver new];
    owner.delegate = receiver;
    BOOL browser = [mode isEqualToString:@"browser"];
    void (^finish)(NSDictionary *) = ^(NSDictionary *result) {
        [owner resetPresentationState];
        window.hidden = YES; [previous makeKeyWindow];
        completion(result);
    };
    [root presentViewController:modal animated:NO completion:^{
        if (browser) [owner openBrowserWithURL:@"https://example.invalid" fromViewController:modal];
        else [owner openCardWithURL:@"https://example.invalid" fromViewController:modal config:nil];
        StashCardSession *session = owner.session;
        // A failed load would end the session before the host acts.
        [session.webView stopLoading];
        UIViewController *surface = browser ? session.browser : session.controller;
        StashAwaitHostCondition(^BOOL { return surface.presentingViewController == modal && !surface.isBeingPresented; },
            CFAbsoluteTimeGetCurrent() + 5, ^(BOOL presented) {
            if (!presented) { finish(@{@"presented":@NO}); return; }
            if ([mode isEqualToString:@"covered"]) {
                // A full-screen cover hides the card without dismissing it.
                UIViewController *cover = [UIViewController new];
                cover.modalPresentationStyle = UIModalPresentationFullScreen;
                [surface presentViewController:cover animated:NO completion:^{
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                        [surface dismissViewControllerAnimated:NO completion:^{
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                                finish(@{@"presented":@YES, @"silent":@(receiver.events.count == 0),
                                    @"survived":@(owner.session == session && session.controller == surface && [session isActive])});
                            });
                        }];
                    });
                }];
                return;
            }
            UIViewController *dismisser = [mode isEqualToString:@"card"] ? modal : root;
            [dismisser dismissViewControllerAnimated:YES completion:nil];
            StashAwaitHostCondition(^BOOL { return receiver.events.count > 0; }, CFAbsoluteTimeGetCurrent() + 5, ^(BOOL ended) {
                NSArray *expected = @[browser ? @"browser-dismissed" : @"card-dismissed"];
                BOOL closed = !owner.isCurrentlyPresented && !session.controller && !session.browser;
                // Open from the visible controller; a full-screen modal takes the root's view out of the window.
                [owner openCardWithURL:@"https://example.invalid" fromViewController:root.presentedViewController ?: root
                    config:nil];
                [owner.session.webView stopLoading];
                finish(@{@"presented":@YES, @"ended":@([receiver.events isEqualToArray:expected]), @"closed":@(closed),
                    @"reopened":@(owner.isCurrentlyPresented && owner.session != session)});
            });
        });
    }];
}

static void StashRequestSceneOrientation(UIWindowScene *scene, UIInterfaceOrientationMask mask) API_AVAILABLE(ios(16.0)) {
    for (UIWindow *window in scene.windows) [window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
    UIWindowSceneGeometryPreferencesIOS *preferences = [[UIWindowSceneGeometryPreferencesIOS alloc]
        initWithInterfaceOrientations:mask];
    [scene requestGeometryUpdateWithPreferences:preferences errorHandler:nil];
}

// Repeats the request until the active scene reports the orientation. A request made while the scene is still
// activating or settling from an earlier rotation can be dropped, so a single request is not enough on a loaded runner.
static void StashRotateScene(UIWindowScene *scene, UIWindow *window, BOOL landscape, CFAbsoluteTime deadline,
    void (^completion)(BOOL)) API_AVAILABLE(ios(16.0)) {
    BOOL (^settled)(void) = ^BOOL {
        CGSize size = window.bounds.size;
        if (scene.activationState != UISceneActivationStateForegroundActive) return NO;
        return landscape ? size.width > size.height && window.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact :
            size.width < size.height;
    };
    if (settled() || CFAbsoluteTimeGetCurrent() >= deadline) { completion(settled()); return; }
    if (scene.activationState == UISceneActivationStateForegroundActive)
        StashRequestSceneOrientation(scene, landscape ? UIInterfaceOrientationMaskLandscapeRight : UIInterfaceOrientationMaskPortrait);
    StashAwaitHostCondition(settled, MIN(deadline, CFAbsoluteTimeGetCurrent() + 1), ^(BOOL done) {
        if (done) completion(YES);
        else StashRotateScene(scene, window, landscape, deadline, completion);
    });
}

static void StashLandscapeCardWidth(CGFloat preferredWidth, void (^completion)(NSDictionary *)) API_AVAILABLE(ios(16.0)) {
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes)
        if ([candidate isKindOfClass:UIWindowScene.class]) scene = (UIWindowScene *)candidate;
    // The host's own window, not a fixture an earlier test left key.
    id<UIWindowSceneDelegate> sceneDelegate = (id<UIWindowSceneDelegate>)scene.delegate;
    UIWindow *previous = [sceneDelegate respondsToSelector:@selector(window)] ? sceneDelegate.window : scene.keyWindow;
    if (!scene || !previous) { completion(@{@"rotated":@NO}); return; }
    [previous makeKeyWindow];
    // Rotate the host scene itself: the card must follow a real compact-height phone window.
    StashRotateScene(scene, previous, YES, CFAbsoluteTimeGetCurrent() + 20, ^(BOOL rotated) {
        UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
        UIViewController *root = [UIViewController new];
        window.rootViewController = root; [window makeKeyAndVisible];
        StashNative *owner = [StashNative new];
        void (^finish)(NSDictionary *) = ^(NSDictionary *result) {
            [owner resetPresentationState];
            window.hidden = YES; [previous makeKeyWindow];
            StashRotateScene(scene, previous, NO, CFAbsoluteTimeGetCurrent() + 20, ^(BOOL restored) {
                NSMutableDictionary *final = [result mutableCopy];
                final[@"restoredPortrait"] = @(restored);
                completion(final);
            });
        };
        if (!rotated) { finish(@{@"rotated":@NO}); return; }
        StashNativeCardConfig *config = [StashNativeCardConfig new];
        config.preferredContentWidth = preferredWidth;
        [owner openCardWithURL:@"https://example.invalid" fromViewController:root config:config];
        StashCardSession *session = owner.session;
        // A failed load would end the session before the measurement.
        [session.webView stopLoading];
        UIViewController *card = session.controller;
        StashAwaitHostCondition(^BOOL { return card.presentingViewController == root && !card.isBeingPresented; },
            CFAbsoluteTimeGetCurrent() + 10, ^(BOOL presented) {
            if (!presented) { finish(@{@"rotated":@YES, @"presented":@NO}); return; }
            // Let any post-presentation size update settle before measuring.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                CGRect frame = [card.view convertRect:card.view.bounds toView:window];
                finish(@{@"rotated":@YES, @"presented":@YES, @"windowWidth":@(window.bounds.size.width),
                    @"windowHeight":@(window.bounds.size.height), @"cardWidth":@(frame.size.width),
                    @"cardHeight":@(frame.size.height), @"active":@([session isActive])});
            });
        });
    });
}

@interface StashKeepOpenDelegate : NSObject <StashNativeDelegate>
@property (nonatomic, strong) NSMutableArray<NSString *> *events;
@end
@implementation StashKeepOpenDelegate
- (instancetype)init { if ((self = [super init])) _events = [NSMutableArray new]; return self; }
- (void)stashNativeDidRequestExternalPaymentWithURL:(NSString *)url { [self.events addObject:@"externalPayment"]; }
- (void)stashNativeDidDismissBrowser { [self.events addObject:@"browserDismissed"]; }
- (void)stashNativeDidDismissCard { [self.events addObject:@"cardDismissed"]; }
- (void)stashNativeDidCompletePaymentWithOrder:(NSString *)order { [self.events addObject:@"paymentSuccess"]; }
- (void)stashNativeDidFailPayment { [self.events addObject:@"paymentFailure"]; }
- (void)stashNativeDidEncounterNetworkError { [self.events addObject:@"networkError"]; }
@end

void StashKeepOpenBrowserProbe(void (^completion)(NSDictionary *)) {
    UIWindow *previous = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) previous = window;
    if (!previous.windowScene) { completion(@{@"presented":@NO}); return; }
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:previous.windowScene];
    UIViewController *root = [UIViewController new];
    window.rootViewController = root; [window makeKeyAndVisible];
    StashNative *owner = [StashNative new];
    StashKeepOpenDelegate *delegate = [StashKeepOpenDelegate new];
    owner.delegate = delegate;
    [owner openCardWithURL:@"https://example.invalid" fromViewController:root config:nil];
    StashCardSession *session = owner.session;
    [session.webView stopLoading];
    UIViewController *card = session.controller;
    void (^finish)(NSDictionary *) = ^(NSDictionary *result) {
        [owner resetPresentationState];
        owner.delegate = nil;
        window.hidden = YES; [previous makeKeyWindow];
        completion(result);
    };
    StashAwaitHostCondition(^BOOL { return card.presentingViewController == root && !card.isBeingPresented; },
        CFAbsoluteTimeGetCurrent() + 5, ^(BOOL presented) {
        if (!presented) { finish(@{@"presented":@NO}); return; }
        [session handleMessage:@"stashExternalPayment" body:@{@"url":@"https://example.invalid/pay", @"keepOpen":@YES}];
        StashAwaitHostCondition(^BOOL {
            return [card.presentedViewController isKindOfClass:SFSafariViewController.class] &&
                !card.presentedViewController.isBeingPresented;
        }, CFAbsoluteTimeGetCurrent() + 5, ^(BOOL browserShown) {
            SFSafariViewController *browser = (SFSafariViewController *)card.presentedViewController;
            BOOL tracked = browser != nil && browser == session.overlayBrowser;
            NSArray *eventsWhileOpen = [delegate.events copy];
            // Safari's Done button: the delegate hears about it, then Safari dismisses itself.
            [session safariViewControllerDidFinish:browser];
            [browser dismissViewControllerAnimated:YES completion:nil];
            StashAwaitHostCondition(^BOOL { return card.presentedViewController == nil; },
                CFAbsoluteTimeGetCurrent() + 5, ^(BOOL returned) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                    finish(@{@"presented":@YES, @"browserShown":@(browserShown), @"tracked":@(tracked),
                        @"eventsWhileOpen":eventsWhileOpen, @"returned":@(returned),
                        @"cardStillPresented":@(card.presentingViewController == root),
                        @"sessionActive":@([session isActive] && owner.session == session),
                        @"overlayCleared":@(session.overlayBrowser == nil), @"events":[delegate.events copy]});
                });
            });
        });
    });
}

void StashCardStackProbe(NSString *cover, NSString *trigger, BOOL autoClose, void (^completion)(NSDictionary *)) {
    UIWindow *previous = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) previous = window;
    if (!previous.windowScene) { completion(@{@"presented":@NO}); return; }
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:previous.windowScene];
    UIViewController *root = [UIViewController new];
    window.rootViewController = root; [window makeKeyAndVisible];
    __block StashNative *owner = [StashNative new];
    __weak StashNative *weakOwner = owner;
    StashKeepOpenDelegate *delegate = [StashKeepOpenDelegate new];
    owner.delegate = delegate;
    StashNativeCardConfig *config = [StashNativeCardConfig new];
    config.autoClose = autoClose;
    [owner openCardWithURL:@"https://example.invalid" fromViewController:root config:config];
    StashCardSession *session = owner.session;
    [session.webView stopLoading];
    // Slow cases must not reach the 15-second load deadline.
    [session.loadTimer invalidate]; session.loadTimer = nil;
    UIViewController *card = session.controller;
    BOOL alert = [cover isEqualToString:@"alert"];
    NSDictionary *keepOpen = @{@"url":@"https://example.invalid/pay", @"keepOpen":@YES};
    __block NSInteger scriptReturns = 0;
    void (^finish)(NSDictionary *) = ^(NSDictionary *result) {
        [owner resetPresentationState];
        owner.delegate = nil;
        // Remove anything left behind so later tests start from an empty host.
        if (root.presentedViewController) [root dismissViewControllerAnimated:NO completion:nil];
        window.hidden = YES; [previous makeKeyWindow];
        completion(result);
    };
    void (^report)(NSDictionary *) = ^(NSDictionary *extra) {
        NSMutableDictionary *result = [@{@"presented":@YES, @"overlayShown":@YES,
            @"rootCleared":@(root.presentedViewController == nil),
            @"cardGone":@(card.presentingViewController == nil),
            @"cardOpen":@(card.presentingViewController == root && [session isActive] && weakOwner.session == session),
            @"sessionEnded":@(weakOwner.session == nil),
            @"overlayCleared":@(session.overlayBrowser == nil),
            @"scriptReturns":@(scriptReturns), @"events":[delegate.events copy]} mutableCopy];
        [result addEntriesFromDictionary:extra];
        finish(result);
    };
    // Waits for the condition, then lets late callbacks arrive before continuing.
    void (^settle)(BOOL (^)(void), void (^)(BOOL)) = ^(BOOL (^condition)(void), void (^then)(BOOL)) {
        StashAwaitHostCondition(condition, CFAbsoluteTimeGetCurrent() + 10, ^(BOOL met) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ then(met); });
        });
    };
    BOOL (^closed)(void) = ^BOOL { return root.presentedViewController == nil && weakOwner.session == nil; };
    BOOL (^coverGone)(void) = ^BOOL { return card.presentedViewController == nil; };
    BOOL (^coverShown)(void) = ^BOOL {
        UIViewController *top = card.presentedViewController;
        return [top isKindOfClass:alert ? UIAlertController.class : SFSafariViewController.class] && !top.isBeingPresented;
    };
    // Back on the card, a second keepOpen request must present Safari again.
    void (^reopen)(BOOL) = ^(BOOL returned) {
        BOOL cleared = session.overlayBrowser == nil;
        [session handleMessage:@"stashExternalPayment" body:keepOpen];
        settle(coverShown, ^(BOOL shown) {
            report(@{@"returned":@(returned), @"clearedOnReturn":@(cleared),
                @"reopened":@(shown && card.presentedViewController == session.overlayBrowser)});
        });
    };
    void (^apply)(void) = ^{
        if ([trigger isEqualToString:@"dismiss"]) [owner dismiss];
        else if ([trigger isEqualToString:@"reset"]) [owner resetPresentationState];
        else if ([trigger isEqualToString:@"ownerRelease"]) owner = nil;
        else if ([trigger isEqualToString:@"success"]) [session handleMessage:@"stashNativementSuccess" body:@"order"];
        else if ([trigger isEqualToString:@"failure"]) [session handleMessage:@"stashNativementFailure" body:@{}];
        else if ([trigger isEqualToString:@"windowClose"]) [session handleMessage:@"stashWindowClose" body:@{}];
        else if ([trigger isEqualToString:@"networkError"]) [session networkFailed];
        else if ([trigger isEqualToString:@"handoff"]) {
            [session handleMessage:@"stashExternalPayment" body:@{@"url":@"https://example.invalid/pay", @"keepOpen":@NO}];
            settle(^BOOL {
                return session.browser && root.presentedViewController == session.browser && !session.browser.isBeingPresented;
            }, ^(BOOL handedOff) { report(@{@"browserPresented":@(handedOff)}); });
            return;
        } else if ([trigger isEqualToString:@"closeBrowser"] || [trigger isEqualToString:@"hostDismissOverlay"]) {
            if ([trigger isEqualToString:@"closeBrowser"]) [owner closeBrowser];
            // The host removes Safari itself; Safari's Done callback never runs.
            else [card dismissViewControllerAnimated:YES completion:nil];
            settle(coverGone, reopen);
            return;
        } else if ([trigger isEqualToString:@"result"] || [trigger isEqualToString:@"pageThenResult"]) {
            BOOL pageFirst = [trigger isEqualToString:@"pageThenResult"];
            // Checkout keeps running under keepOpen Safari, so the page can report the same payment.
            void (^page)(void) = ^{ [session handleMessage:@"stashNativementSuccess" body:@"order"]; };
            if (pageFirst) page(); else [owner dismissSafariViewControllerWithResult:YES];
            settle(autoClose ? closed : (pageFirst ? ^BOOL { return YES; } : coverGone), ^(BOOL first) {
                if (pageFirst) [owner dismissSafariViewControllerWithResult:YES]; else page();
                settle(autoClose ? closed : coverGone, ^(BOOL second) {
                    report(@{@"returned":@(first && second && coverGone())});
                });
            });
            return;
        }
        settle([trigger isEqualToString:@"ownerRelease"] ? ^BOOL { return root.presentedViewController == nil && !weakOwner; } :
            [trigger hasPrefix:@"reset"] ? ^BOOL { return root.presentedViewController == nil; } : closed, ^(BOOL ended) {
            report(@{@"ended":@(ended)});
        });
    };
    StashAwaitHostCondition(^BOOL { return card.presentingViewController == root && !card.isBeingPresented; },
        CFAbsoluteTimeGetCurrent() + 10, ^(BOOL presented) {
        if (!presented) { finish(@{@"presented":@NO}); return; }
        void (^covered)(BOOL) = ^(BOOL shown) {
            if (!shown) {
                finish(@{@"presented":@YES, @"overlayShown":@NO, @"loaded":@(session.loaded),
                    @"top":NSStringFromClass(card.presentedViewController.class) ?: @"none"});
                return;
            }
            apply();
        };
        if (!alert) {
            [session handleMessage:@"stashExternalPayment" body:keepOpen];
            StashAwaitHostCondition(coverShown, CFAbsoluteTimeGetCurrent() + 10, covered);
            return;
        }
        // A real page alert: WebKit waits for the SDK to complete its panel before the script returns.
        // In the simulator, the process's first alert over a page blocked in alert() takes about 15 seconds to
        // finish presenting; a plain alert first avoids that wait.
        UIAlertController *plain = [UIAlertController alertControllerWithTitle:nil message:@"stash"
            preferredStyle:UIAlertControllerStyleAlert];
        [card presentViewController:plain animated:NO completion:^{
            [card dismissViewControllerAnimated:NO completion:^{
                [session.webView loadHTMLString:@"<!doctype html><title>stash</title>"
                    baseURL:[NSURL URLWithString:@"https://example.invalid/"]];
                StashAwaitHostCondition(^BOOL { return session.loaded; }, CFAbsoluteTimeGetCurrent() + 10, ^(BOOL loaded) {
                    [session.webView evaluateJavaScript:@"alert('stash'); 1" completionHandler:^(id value, NSError *error) {
                        scriptReturns += 1;
                    }];
                    StashAwaitHostCondition(coverShown, CFAbsoluteTimeGetCurrent() + 10, covered);
                });
            }];
        }];
    });
}

// Observes a deferred session's WebView so the probe can stop its load before a DNS failure ends it.
@interface StashDeferredLoadStopper : NSObject
@property (nonatomic, weak) StashCardSession *session;
@end
@implementation StashDeferredLoadStopper
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    StashCardSession *session = self.session;
    dispatch_async(dispatch_get_main_queue(), ^{ [session.webView stopLoading]; });
}
@end

void StashResetReopenProbe(NSString *mode, void (^completion)(NSDictionary *)) {
    UIWindow *previous = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) previous = window;
    if (!previous.windowScene) { completion(@{@"presented":@NO}); return; }
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:previous.windowScene];
    UIViewController *root = [UIViewController new];
    window.rootViewController = root; [window makeKeyAndVisible];
    StashNative *owner = [StashNative new];
    StashKeepOpenDelegate *delegate = [StashKeepOpenDelegate new];
    owner.delegate = delegate;
    [owner openCardWithURL:@"https://example.invalid" fromViewController:root config:nil];
    StashCardSession *first = owner.session;
    [first.webView stopLoading];
    UIViewController *firstCard = first.controller;
    BOOL firstAnimating = firstCard.isBeingPresented;
    // Reset and reopen while the first card is still in its presentation animation.
    [owner resetPresentationState];
    if ([mode isEqualToString:@"browserDetached"])
        [owner openBrowserWithURL:@"https://example.invalid" fromViewController:root];
    else [owner openCardWithURL:@"https://example.invalid" fromViewController:root config:nil];
    StashCardSession *second = owner.session;
    [second.webView stopLoading];
    BOOL deferred = first.surfaceDismissalWaiters.count == 1 && second.openDeferred;
    // The host changes before the deferred open runs: the first card's own dismissal waiter goes first.
    void (^interfere)(void) = nil;
    if ([mode hasSuffix:@"etached"]) interfere = ^{ [root.view removeFromSuperview]; };
    else if ([mode isEqualToString:@"occupied"]) interfere = ^{
        [root presentViewController:[UIViewController new] animated:NO completion:nil];
    };
    else if ([mode isEqualToString:@"reset"]) [owner resetPresentationState];
    if (interfere) [first.surfaceDismissalWaiters insertObject:[interfere copy] atIndex:0];
    StashDeferredLoadStopper *stopper = [StashDeferredLoadStopper new];
    stopper.session = second;
    [second addObserver:stopper forKeyPath:@"webView" options:0 context:NULL];
    void (^finish)(NSDictionary *) = ^(NSDictionary *result) {
        [second removeObserver:stopper forKeyPath:@"webView"];
        [owner resetPresentationState];
        owner.delegate = nil;
        if (root.presentedViewController) [root dismissViewControllerAnimated:NO completion:nil];
        window.hidden = YES; [previous makeKeyWindow];
        completion(result);
    };
    BOOL presents = [mode isEqualToString:@"present"];
    StashAwaitHostCondition(^BOOL {
        if (firstCard.presentingViewController) return NO;
        if (!presents) return owner.session == nil;
        UIViewController *card = second.controller;
        return card && card.presentingViewController == root && !card.isBeingPresented;
    }, CFAbsoluteTimeGetCurrent() + 10, ^(BOOL settled) {
        // Let a duplicate or late final event arrive.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            UIViewController *card = second.controller;
            finish(@{@"firstAnimating":@(firstAnimating), @"admitted":@(second != nil && second != first),
                @"deferred":@(deferred), @"settled":@(settled), @"firstGone":@(firstCard.presentingViewController == nil),
                @"secondOnRoot":@(card && card.presentingViewController == root && root.presentedViewController == card),
                @"active":@(owner.isCurrentlyPresented && owner.session == second && [second isActive]),
                @"ended":@(!owner.isCurrentlyPresented && !second.controller && !second.browser),
                @"events":[delegate.events copy]});
        });
    });
}

void StashDismissalContentProbe(void (^completion)(NSDictionary *)) {
    UIWindow *previous = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) previous = window;
    if (!previous.windowScene) { completion(@{@"presented":@NO}); return; }
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:previous.windowScene];
    UIViewController *root = [UIViewController new];
    window.rootViewController = root; [window makeKeyAndVisible];
    StashNative *owner = [StashNative new];
    [owner openCardWithURL:@"https://example.invalid" fromViewController:root config:nil];
    StashCardSession *session = owner.session;
    [session.webView stopLoading];
    UIViewController *card = session.controller;
    WKWebView *web = session.webView;
    void (^finish)(NSDictionary *) = ^(NSDictionary *result) {
        [owner resetPresentationState];
        window.hidden = YES; [previous makeKeyWindow];
        completion(result);
    };
    StashAwaitHostCondition(^BOOL { return card.presentingViewController == root && !card.isBeingPresented; },
        CFAbsoluteTimeGetCurrent() + 5, ^(BOOL presented) {
        if (!presented) { finish(@{@"presented":@NO}); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            CGRect before = web.frame;
            __block CGFloat minimumHeight = before.size.height;
            __block NSInteger samples = 0;
            [owner dismiss];
            // Sample every frame while UIKit animates the card out; force layout as the update link would.
            StashAwaitHostCondition(^BOOL {
                if (card.isBeingDismissed) {
                    [card.view setNeedsLayout]; [card.view layoutIfNeeded];
                    minimumHeight = MIN(minimumHeight, web.frame.size.height);
                    samples += 1;
                }
                return card.presentingViewController == nil;
            }, CFAbsoluteTimeGetCurrent() + 5, ^(BOOL dismissed) {
                finish(@{@"presented":@YES, @"dismissed":@(dismissed), @"beforeHeight":@(before.size.height),
                    @"minimumHeight":@(minimumHeight), @"samples":@(samples)});
            });
        });
    });
}

void StashLandscapeCardWidthProbe(CGFloat preferredWidth, void (^completion)(NSDictionary *)) {
    if (@available(iOS 16.0, *)) StashLandscapeCardWidth(preferredWidth, completion);
    else completion(@{@"rotated":@NO});
}
