//
//  StashNativeCardOrientation.m
//  StashNative
//
//  Forced-portrait orientation control for the card and the dedicated Safari portrait window.
//  Holds the one-time AppDelegate swizzle on application:supportedInterfaceOrientationsForWindow:
//  (so the SDK window can be portrait even when a Unity/Unreal host is landscape-locked), the
//  shared window->orientation-mask resolver, the public +supportedInterfaceOrientationsForWindow:
//  forwarder for hosts that manage orientation manually, the pre-portrait orientation restore +
//  window teardown, and the iPhone-card keyboard orientation lock. Moved verbatim from
//  StashNativeCard.m.
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
        // Cold start / early presentation: key window may be nil before the scene is foreground-active.
        // Any window scene with a window is enough to attach; otherwise the card window has no scene.
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
// When forcePortrait is used the SDK installs a one-time swizzle on
// application:supportedInterfaceOrientationsForWindow: on the AppDelegate class.
// This lets the SDK's portrait window (and the dedicated Safari portrait window)
// rotate to portrait even when the host app's Info.plist is landscape-only —
// the common case for Unity, Unreal, and other landscape-locked game engines.
//
// The swizzle is surgical: for non-SDK windows it always calls through to the
// original implementation, so nothing else in the app changes behaviour.
// dispatch_once guarantees the swizzle is installed exactly once and only when
// it is first needed (not at app launch).
// ============================================================================

// Returns the orientation mask from the host app's Info.plist (UISupportedInterfaceOrientations).
// Used as fallback when the app had no application:supportedInterfaceOrientationsForWindow:.
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
// when the caller should apply its own default (host window, or no card presented). Shared by the
// auto-managed swizzle and the public +supportedInterfaceOrientationsForWindow: forwarder so the
// two cannot drift; each keeps its own nil-window guard and fall-through tail.
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

        // We need a stable reference to originalIMP that the block can capture and call.
        // __block + a C-function-pointer typedef makes this safe.
        typedef UIInterfaceOrientationMask (*OriginalIMP)(id, SEL, UIApplication *, UIWindow *);
        __block OriginalIMP originalIMP = NULL;

        IMP newIMP = imp_implementationWithBlock(
            ^UIInterfaceOrientationMask(id blockSelf, UIApplication *app, UIWindow *window) {
                StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
                // Card window, Safari portrait window, or a system window (keyboard/alert) over the
                // card: lock to the card's orientation so a physical rotation can't flip it, and so
                // iOS 15 (which has no scene-geometry path) constrains rotation correctly.
                UIInterfaceOrientationMask mask;
                if (stashResolveCardWindowOrientationMask(internal, window, &mask)) {
                    return mask;
                }
                // Host app's window (or no card presented): forward to original.
                if (originalIMP) {
                    return originalIMP(blockSelf, sel, app, window);
                }
                // App had no original implementation -- return Info.plist orientations
                // so the swizzle does not permanently unlock all orientations for the host.
                return stashInfoPlistSupportedOrientationMask();
            });

        Method method = class_getInstanceMethod(delegateClass, sel);
        if (method) {
            // Method exists on this class (or a superclass) — replace and save the original.
            originalIMP = (OriginalIMP)method_setImplementation(method, newIMP);
        } else {
            // Method doesn't exist — add it; "originalIMP" stays NULL (no original to call).
            // Type encoding: return UIInterfaceOrientationMask (NSUInteger = 8 bytes on 64-bit),
            // args: self (id @8), _cmd (SEL @8), UIApplication * (@8), UIWindow * (@8) → 40 bytes.
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
    // Host window, or no card presented: 0 lets the caller's own mask take effect.
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

    // MaskAll means "opened from portrait/neutral -- no forced rotation needed on restore."
    // Requesting MaskAll would unlock all orientations and potentially cause an unwanted rotation
    // from the accelerometer. Instead, just let the window teardown return control to the app.
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
        // UIDevice hack only needed for landscape restore; portrait/neutral returns naturally.
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
        // Restore scene orientation whenever it was locked during this session.
        // restorePrePortraitOrientation is a no-op if previousSceneOrientationMask == 0.
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
        // iOS 15: trigger re-query of supportedInterfaceOrientationsForWindow so the
        // swizzle sees isIPhoneCardKeyboardVisible == YES and returns the lock mask.
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
        // iOS 15: reinforce the card's orientation so the next keyboard presented
        // appears in portrait (or the locked orientation). Without this, the device
        // is still physically rotated and the next keyboard would follow that.
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
