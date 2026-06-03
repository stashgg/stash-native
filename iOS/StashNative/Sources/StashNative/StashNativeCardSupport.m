//
//  StashNativeCardSupport.m
//  StashNative
//
//  Cross-cutting pure helpers (idiom/window/orientation/colors/corner mask) shared across the SDK
//  translation units. All stash_-prefixed plus StashNativeDarkSurfaceColor.
//

#import "StashNativeCardSupport.h"

#if !__has_feature(objc_arc)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshadow"
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

UIColor *StashNativeDarkSurfaceColor(void) {
    return [UIColor colorWithRed:0x1e/255.0 green:0x1e/255.0 blue:0x1e/255.0 alpha:1.0];
}

BOOL stash_isRunningOniPad(void) {
#if !ENABLE_IPAD_SUPPORT
    return NO;
#else
    // Caches the interface idiom on first call via dispatch_once.
    static BOOL result = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        result = ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad);
    });
    return result;
#endif
}

UIColor* stash_getSystemBackgroundColor(void) {
    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle currentStyle = [UITraitCollection currentTraitCollection].userInterfaceStyle;
        return (currentStyle == UIUserInterfaceStyleDark) ? StashNativeDarkSurfaceColor() : [UIColor systemBackgroundColor];
    }
    return [UIColor whiteColor];
}

CAShapeLayer* stash_createCornerRadiusMask(CGRect bounds, UIRectCorner corners, CGFloat radius) {
    UIBezierPath *maskPath = [UIBezierPath bezierPathWithRoundedRect:bounds
                                                  byRoundingCorners:corners
                                                        cornerRadii:CGSizeMake(radius, radius)];
    CAShapeLayer *maskLayer = [[CAShapeLayer alloc] init];
    maskLayer.frame = bounds;
    maskLayer.path = maskPath.CGPath;
    return maskLayer;
}

UIWindow* stash_getKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = [UIApplication sharedApplication].connectedScenes;
        UIWindow * (^pickFromScene)(UIWindowScene *) = ^UIWindow *(UIWindowScene *ws) {
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) {
                    return w;
                }
            }
            return ws.windows.firstObject;
        };
        for (UIScene *scene in scenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            if (scene.activationState != UISceneActivationStateForegroundActive) {
                continue;
            }
            UIWindow *w = pickFromScene((UIWindowScene *)scene);
            if (w) {
                return w;
            }
        }
        for (UIScene *scene in scenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            if (scene.activationState != UISceneActivationStateForegroundActive &&
                scene.activationState != UISceneActivationStateForegroundInactive) {
                continue;
            }
            UIWindow *w = pickFromScene((UIWindowScene *)scene);
            if (w) {
                return w;
            }
        }
        for (UIScene *scene in scenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            UIWindow *w = pickFromScene((UIWindowScene *)scene);
            if (w) {
                return w;
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
}

UIViewController *stash_getTopPresentedViewController(void) {
    UIViewController *rootVC = stash_getKeyWindow().rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    return rootVC;
}

UIInterfaceOrientation stash_getInterfaceOrientation(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                return ((UIWindowScene *)scene).interfaceOrientation;
            }
        }
        return UIInterfaceOrientationUnknown;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].statusBarOrientation;
#pragma clang diagnostic pop
}

#if !__has_feature(objc_arc)
#pragma clang diagnostic pop
#endif
