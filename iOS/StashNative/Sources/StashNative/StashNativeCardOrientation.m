//
//  StashNativeCardOrientation.m
//  StashNative
//
//  Forced-portrait orientation control for the card and the dedicated Safari portrait window.
//  Holds the one-time AppDelegate swizzle on application:supportedInterfaceOrientationsForWindow:,
//  the shared window->orientation-mask resolver, the public +supportedInterfaceOrientationsForWindow:
//  forwarder, the pre-portrait orientation restore and window teardown, and the iPhone-card keyboard
//  orientation lock.
//

#import "StashNativeCard.h"
#import "StashNativeCardInternal.h"
#import "StashNativeCardPrivate.h"
#import "StashNativeCardOrientation.h"
#import <objc/runtime.h>

#if !__has_feature(objc_arc)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshadow"
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

UIInterfaceOrientationMask stashOrientationMaskForOrientation(UIInterfaceOrientation orientation) {
    switch (orientation) {
        case UIInterfaceOrientationPortrait:            return UIInterfaceOrientationMaskPortrait;
        case UIInterfaceOrientationPortraitUpsideDown:  return UIInterfaceOrientationMaskPortraitUpsideDown;
        case UIInterfaceOrientationLandscapeLeft:       return UIInterfaceOrientationMaskLandscapeLeft;
        case UIInterfaceOrientationLandscapeRight:      return UIInterfaceOrientationMaskLandscapeRight;
        default:                                        return UIInterfaceOrientationMaskAll;
    }
}

void stash_attachWindowToKeyWindowScene(UIWindow *cardWindow, UIWindow *keyWindow) {
    if (@available(iOS 13.0, *)) {
        if (keyWindow.windowScene) {
            cardWindow.windowScene = keyWindow.windowScene;
            return;
        }
        // Fallback when the key window has no scene: first connected window scene that owns a window.
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                if (ws.windows.count > 0) {
                    cardWindow.windowScene = ws;
                    return;
                }
            }
        }
    }
}

// Orientation unlock swizzle
//
// Installs a one-time swizzle on application:supportedInterfaceOrientationsForWindow: on the
// AppDelegate class. SDK windows (the portrait window and the dedicated Safari portrait window)
// resolve to the card orientation; non-SDK windows call through to the original implementation.
// dispatch_once installs the swizzle exactly once, on first use.
// ============================================================================

// Returns the orientation mask from the host app's Info.plist (UISupportedInterfaceOrientations).
// Fallback when the app has no application:supportedInterfaceOrientationsForWindow:.
static UIInterfaceOrientationMask stashInfoPlistSupportedOrientationMask(void) {
    static UIInterfaceOrientationMask cached = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *orientations = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UISupportedInterfaceOrientations"];
        if (!orientations || orientations.count == 0) {
            cached = UIInterfaceOrientationMaskAll;
            return;
        }
        UIInterfaceOrientationMask mask = 0;
        for (NSString *o in orientations) {
            if ([o isEqualToString:@"UIInterfaceOrientationPortrait"])           mask |= UIInterfaceOrientationMaskPortrait;
            if ([o isEqualToString:@"UIInterfaceOrientationPortraitUpsideDown"]) mask |= UIInterfaceOrientationMaskPortraitUpsideDown;
            if ([o isEqualToString:@"UIInterfaceOrientationLandscapeLeft"])      mask |= UIInterfaceOrientationMaskLandscapeLeft;
            if ([o isEqualToString:@"UIInterfaceOrientationLandscapeRight"])     mask |= UIInterfaceOrientationMaskLandscapeRight;
        }
        cached = mask ? mask : UIInterfaceOrientationMaskAll;
    });
    return cached;
}

// Resolves the interface-orientation mask for a window the SDK governs during a forced-portrait
// card/Safari presentation. Returns YES and writes *outMask when the window is the card window,
// the Safari portrait window, or a system window (keyboard/alert) shown over the card; returns NO
// for a host window or when no card is presented. Shared by the swizzle and the public
// +supportedInterfaceOrientationsForWindow: forwarder.
static BOOL stashResolveCardWindowOrientationMask(StashNativeCardInternal *internal,
                                                  UIWindow *window,
                                                  UIInterfaceOrientationMask *outMask) {
    if (window && (window == internal.portraitWindow || window == internal.safariPresentationWindow)) {
        if (internal.isSafariPortraitLocked) {
            *outMask = UIInterfaceOrientationMaskPortrait;
            return YES;
        }
        if (window == internal.portraitWindow && internal.isIPhoneCardKeyboardVisible) {
            *outMask = [internal stashKeyboardOrientationLockMaskForCardWindow];
            return YES;
        }
        UIViewController *rootVC = window.rootViewController;
        *outMask = rootVC ? [rootVC supportedInterfaceOrientations] : UIInterfaceOrientationMaskAll;
        return YES;
    }
    if (internal.portraitWindow && window != internal.previousKeyWindow) {
        UIViewController *cardRootVC = internal.portraitWindow.rootViewController;
        if (cardRootVC) {
            *outMask = [cardRootVC supportedInterfaceOrientations];
            return YES;
        }
    }
    return NO;
}

void stashInstallOrientationSwizzleIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        id appDelegate = [UIApplication sharedApplication].delegate;
        if (!appDelegate) return;

        Class delegateClass = [appDelegate class];
        SEL sel = @selector(application:supportedInterfaceOrientationsForWindow:);

        // C-function-pointer typedef for the original implementation; __block so the block can
        // capture and call it.
        typedef UIInterfaceOrientationMask (*OriginalIMP)(id, SEL, UIApplication *, UIWindow *);
        __block OriginalIMP originalIMP = NULL;

        IMP newIMP = imp_implementationWithBlock(
            ^UIInterfaceOrientationMask(id blockSelf, UIApplication *app, UIWindow *window) {
                StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
                // Card window, Safari portrait window, or a system window (keyboard/alert) over the
                // card: return the card's orientation mask.
                UIInterfaceOrientationMask mask;
                if (stashResolveCardWindowOrientationMask(internal, window, &mask)) {
                    return mask;
                }
                // Host app's window, or no card presented: forward to the original.
                if (originalIMP) {
                    return originalIMP(blockSelf, sel, app, window);
                }
                // No original implementation: return the Info.plist orientations.
                return stashInfoPlistSupportedOrientationMask();
            });

        Method method = class_getInstanceMethod(delegateClass, sel);
        if (method) {
            // Method exists on this class or a superclass: replace it and save the original.
            originalIMP = (OriginalIMP)method_setImplementation(method, newIMP);
        } else {
            // Method does not exist: add it; originalIMP stays NULL.
            // Type encoding "Q40@0:8@16@24": Q = returned NSUInteger (UIInterfaceOrientationMask); 40 =
            // legacy frame size (ignored by the modern runtime); arg offsets self@0, _cmd@8, UIApplication*@16, UIWindow*@24.
            class_addMethod(delegateClass, sel, newIMP, "Q40@0:8@16@24");
        }
    });
}

@implementation StashNativeCard (Orientation)

+ (UIInterfaceOrientationMask)supportedInterfaceOrientationsForWindow:(nullable UIWindow *)window {
    if (!window) {
        return 0;
    }
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    UIInterfaceOrientationMask mask;
    if (stashResolveCardWindowOrientationMask(internal, window, &mask)) {
        return mask;
    }
    // Host window, or no card presented: 0 leaves the caller's own mask in effect.
    return 0;
}

@end

@implementation StashNativeCardInternal (Orientation)

- (BOOL)isIPhoneLandscapeCurrentOrientation {
    if (!self.currentPresentedVC) return NO;
    if (![self.currentPresentedVC isKindOfClass:[IPhoneCardCurrentOrientationViewController class]]) return NO;
    CGRect b = [self referenceScreenBoundsForIPhoneCardLayout];
    return b.size.width > b.size.height;
}

- (void)restorePrePortraitOrientation {
    if (self.previousSceneOrientationMask == 0) return;
    UIInterfaceOrientationMask mask = self.previousSceneOrientationMask;
    self.previousSceneOrientationMask = 0;

    // MaskAll marks an open from portrait/neutral: no forced rotation on restore.
    if (mask == UIInterfaceOrientationMaskAll) {
        return;
    }

    if (@available(iOS 16.0, *)) {
        UIWindowScene *scene = nil;
        if (self.previousKeyWindow) {
            scene = self.previousKeyWindow.windowScene;
        }
        if (!scene) {
            for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]] &&
                    s.activationState == UISceneActivationStateForegroundActive) {
                    scene = (UIWindowScene *)s;
                    break;
                }
            }
        }
        if (scene) {
            UIWindowSceneGeometryPreferencesIOS *prefs =
                [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
            [scene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *e) {
                STASH_DEBUG_LOG(@"StashNative orientation restore failed: %@", e);
            }];
        }
    } else {
        // Pre-iOS 16: UIDevice orientation set for landscape restore only.
        if (mask == UIInterfaceOrientationMaskLandscapeLeft ||
            mask == UIInterfaceOrientationMaskLandscapeRight) {
            UIInterfaceOrientation target =
                (mask == UIInterfaceOrientationMaskLandscapeLeft)
                    ? UIInterfaceOrientationLandscapeLeft
                    : UIInterfaceOrientationLandscapeRight;
            [[UIDevice currentDevice] setValue:@(target) forKey:@"orientation"];
            [UIViewController attemptRotationToDeviceOrientation];
        }
    }
}

// Hides and detaches a dedicated SDK window (card portrait window or Safari portrait window),
// restoring the host's previous key window and the pre-portrait scene orientation. The caller
// clears its own strong reference to the window afterward.
- (void)teardownPresentationWindow:(UIWindow *)window {
    window.hidden = YES;
    window.rootViewController = nil;
    if (self.previousKeyWindow) {
        // Restore scene orientation; no-op when previousSceneOrientationMask == 0.
        [self restorePrePortraitOrientation];
        [self.previousKeyWindow makeKeyAndVisible];
        self.previousKeyWindow = nil;
    }
}

- (UIInterfaceOrientationMask)stashKeyboardOrientationLockMaskForCardWindow {
    if (stash_forcePortraitOnCheckout) {
        return UIInterfaceOrientationMaskPortrait;
    }
    UIViewController *vc = self.currentPresentedVC;
    if ([vc isKindOfClass:[IPhoneCardCurrentOrientationViewController class]]) {
        IPhoneCardCurrentOrientationViewController *cvc = (IPhoneCardCurrentOrientationViewController *)vc;
        if (cvc.lockedOrientationMask != 0) {
            return cvc.lockedOrientationMask;
        }
    }
    return UIInterfaceOrientationMaskPortrait;
}

- (void)stashApplyKeyboardOrientationLockIfNeeded {
    if (stash_isRunningOniPad() || stash_usePopupPresentation || stash_useModalPresentation) {
        return;
    }
    if (!self.portraitWindow) {
        return;
    }
    self.isIPhoneCardKeyboardVisible = YES;
    {
        UIDeviceOrientation d = [UIDevice currentDevice].orientation;
        self.stashLastValidDeviceOrientationForKeyboard =
            UIDeviceOrientationIsValidInterfaceOrientation(d) ? (NSInteger)d : 0;
    }
    if (stash_forcePortraitOnCheckout && self.portraitWindow.windowScene) {
        self.stashLastSceneSizeForKeyboardDismiss = self.portraitWindow.windowScene.coordinateSpace.bounds.size;
    } else {
        self.stashLastSceneSizeForKeyboardDismiss = CGSizeZero;
    }
    if (@available(iOS 16.0, *)) {
        UIWindowScene *scene = self.portraitWindow.windowScene;
        if (scene) {
            UIInterfaceOrientationMask mask = [self stashKeyboardOrientationLockMaskForCardWindow];
            UIWindowSceneGeometryPreferencesIOS *prefs =
                [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
            [scene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *error) {
                STASH_DEBUG_LOG(@"StashNative keyboard orientation lock: %@", error);
            }];
            if (stash_forcePortraitOnCheckout) {
                CGRect cb = scene.coordinateSpace.bounds;
                BOOL boundsLandscape = cb.size.width > cb.size.height;
                BOOL ioLandscape = UIInterfaceOrientationIsLandscape(scene.interfaceOrientation);
                if (boundsLandscape || ioLandscape) {
                    [scene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *error) {
                        STASH_DEBUG_LOG(@"StashNative keyboard portrait reinforce: %@", error);
                    }];
                }
            }
        }
    } else {
        // Pre-iOS 16: re-query supportedInterfaceOrientationsForWindow with
        // isIPhoneCardKeyboardVisible == YES.
        [UIViewController attemptRotationToDeviceOrientation];
    }
}

- (void)stashClearKeyboardOrientationLockIfNeeded {
    if (!self.isIPhoneCardKeyboardVisible) {
        return;
    }
    self.isIPhoneCardKeyboardVisible = NO;
    self.stashLastValidDeviceOrientationForKeyboard = 0;
    self.stashLastSceneSizeForKeyboardDismiss = CGSizeZero;
    if (@available(iOS 16.0, *)) {
        UIWindowScene *scene = self.portraitWindow.windowScene;
        if (!scene || !self.portraitWindow) {
            return;
        }
        UIInterfaceOrientationMask mask = [self stashKeyboardOrientationLockMaskForCardWindow];
        UIWindowSceneGeometryPreferencesIOS *prefs =
            [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
        [scene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *error) {
            STASH_DEBUG_LOG(@"StashNative keyboard orientation restore: %@", error);
        }];
    } else {
        // Pre-iOS 16: reinforce the card's orientation for the next keyboard presentation.
        if (self.portraitWindow) {
            if (stash_forcePortraitOnCheckout) {
                [[UIDevice currentDevice] setValue:@(UIInterfaceOrientationPortrait)
                                            forKey:@"orientation"];
            }
            [UIViewController attemptRotationToDeviceOrientation];
        }
    }
}

@end

#if !__has_feature(objc_arc)
#pragma clang diagnostic pop
#endif
