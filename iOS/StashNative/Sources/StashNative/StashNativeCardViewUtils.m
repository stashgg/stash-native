//
//  StashNativeCardViewUtils.m
//  StashNative
//
//  View, layer, and window plumbing shared by presentation and interaction code:
//  corner masks, shadows, drag tray layout, scroll config, overlay creation,
//  key window / top VC lookup, and external-payment URL normalization.
//  Shared constants are defined in StashNativeCard.m; extern'd via StashNativeCardPrivate.h.
//

#import "StashNativeCard.h"
#import "StashNativeCardPrivate.h"
#import <WebKit/WebKit.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

// Non-ARC compatibility: These warnings are suppressed when compiling without ARC
// (e.g., in game engines like Unreal Engine that manage memory manually).
// ARC builds do not need these suppressions.
#if !__has_feature(objc_arc)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshadow"
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

#pragma mark - Local Constants

static const CGFloat kOverlayDismissAlpha = 0.0f;

static const CGFloat kVerticalPositionThresholdBottom = 0.1f;
static const CGFloat kVerticalPositionThresholdTop = 0.9f;

#pragma mark - View Helpers

/// Recursively find the first WKWebView in a view subtree.
WKWebView *findWebViewInView(UIView *view) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[WKWebView class]]) return (WKWebView *)sub;
        WKWebView *found = findWebViewInView(sub);
        if (found) return found;
    }
    return nil;
}

WKWebView* switchWebViewToFrameLayoutInCardView(UIView *cardView) {
    if (!cardView) return nil;
    for (UIView *subview in cardView.subviews) {
        if ([subview isKindOfClass:[WKWebView class]]) {
            WKWebView *webView = (WKWebView *)subview;
            NSMutableArray *constraintsToRemove = [NSMutableArray array];
            for (NSLayoutConstraint *constraint in cardView.constraints) {
                if (constraint.firstItem == webView || constraint.secondItem == webView) {
                    [constraintsToRemove addObject:constraint];
                }
            }
            [NSLayoutConstraint deactivateConstraints:constraintsToRemove];
            webView.translatesAutoresizingMaskIntoConstraints = YES;
            return webView;
        }
    }
    return nil;
}

/// Pins every direct subview except the drag tray to cardView.bounds (strips edge constraints first).
/// Needed after rotation or when the WebView was switched to frame layout during SDK expand/collapse.
void layoutCardContentToBounds(UIView *cardView) {
    if (!cardView) return;
    CGRect bounds = cardView.bounds;
    for (UIView *subview in cardView.subviews) {
        if (subview.tag == kDragTrayViewTag) {
            continue;
        }
        NSMutableArray *constraintsToRemove = [NSMutableArray array];
        for (NSLayoutConstraint *constraint in cardView.constraints) {
            if (constraint.firstItem == subview || constraint.secondItem == subview) {
                [constraintsToRemove addObject:constraint];
            }
        }
        [NSLayoutConstraint deactivateConstraints:constraintsToRemove];
        subview.translatesAutoresizingMaskIntoConstraints = YES;
        subview.frame = bounds;
    }
    updateDragTrayAndHandleInCardView(cardView, bounds.size.width);
}

void updateDragTrayAndHandleInCardView(UIView *cardView, CGFloat cardWidth) {
    if (!cardView) return;
    UIView *dragTray = [cardView viewWithTag:kDragTrayViewTag];
    if (dragTray) {
        dragTray.frame = CGRectMake(0, 0, cardWidth, kDragTrayHeight);
        UIView *handle = [dragTray viewWithTag:kDragHandleViewTag];
        if (handle) {
            CGFloat handleX = (cardWidth / 2.0) - kHandleBarHalfWidth;
            handle.frame = CGRectMake(handleX, kHandleBarTopInset, kHandleBarWidth, kHandleBarHeight);
        }
    }
}

void configureScrollViewForWebView(UIScrollView* scrollView) {
    if (!scrollView) {
        return;
    }
    if (@available(iOS 11.0, *)) {
        scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    scrollView.contentInset = UIEdgeInsetsZero;
    scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
    scrollView.bounces = NO;
    scrollView.alwaysBounceVertical = NO;
    scrollView.alwaysBounceHorizontal = NO;
    scrollView.bouncesZoom = NO;
    if (@available(iOS 17.4, *)) {
        scrollView.bouncesVertically = NO;
        scrollView.bouncesHorizontally = NO;
        scrollView.transfersVerticalScrollingToParent = NO;
        scrollView.transfersHorizontalScrollingToParent = NO;
    }
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) {
        UIScrollEdgeEffectStyle *hardStyle = [UIScrollEdgeEffectStyle hardStyle];
        scrollView.topEdgeEffect.style = hardStyle;
        scrollView.bottomEdgeEffect.style = hardStyle;
        scrollView.leftEdgeEffect.style = hardStyle;
        scrollView.rightEdgeEffect.style = hardStyle;
    }
#endif
}

UIRectCorner getCornersToRoundForPosition(CGFloat verticalPosition, BOOL isiPad) {
    if (isiPad) {
        return UIRectCornerAllCorners;
    }
    if (verticalPosition < kVerticalPositionThresholdBottom) {
        return UIRectCornerBottomLeft | UIRectCornerBottomRight;
    } else if (verticalPosition > kVerticalPositionThresholdTop) {
        return UIRectCornerTopLeft | UIRectCornerTopRight;
    }
    return UIRectCornerAllCorners;
}

void setWebViewBackgroundColor(WKWebView* webView, UIColor* color) {
    webView.backgroundColor = color;
    webView.scrollView.backgroundColor = color;
    for (UIView *subview in webView.subviews) {
        subview.backgroundColor = color;
        subview.opaque = YES;
    }
    for (UIView *subview in webView.scrollView.subviews) {
        subview.backgroundColor = color;
        subview.opaque = YES;
    }
}

CAShapeLayer* createCornerRadiusMask(CGRect bounds, UIRectCorner corners, CGFloat radius) {
    UIBezierPath *maskPath = [UIBezierPath bezierPathWithRoundedRect:bounds
                                                  byRoundingCorners:corners
                                                        cornerRadii:CGSizeMake(radius, radius)];
    CAShapeLayer *maskLayer = [[CAShapeLayer alloc] init];
    maskLayer.frame = bounds;
    maskLayer.path = maskPath.CGPath;
    return maskLayer;
}

/// Attach cardWindow to the same UIWindowScene as the app (e.g. Unreal) so it renders in game engines.
void attachWindowToKeyWindowScene(UIWindow *cardWindow, UIWindow *keyWindow) {
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

UIWindow* getKeyWindow(void) {
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

UIViewController *getTopPresentedViewController(void) {
    UIViewController *rootVC = getKeyWindow().rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    return rootVC;
}

void runWithoutImplicitAnimations(void (^block)(void)) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (block) block();
    [CATransaction commit];
}

UIView* createOverlayViewWithFrame(CGRect frame, UIView *parentView, NSInteger index, UIViewController *vc) {
    UIView *overlayView = [[UIView alloc] initWithFrame:frame];
    overlayView.backgroundColor = [UIColor clearColor];
    overlayView.userInteractionEnabled = YES;
    overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [parentView insertSubview:overlayView atIndex:index];
    if (vc) {
        objc_setAssociatedObject(vc, (__bridge const void *)StashNativeAssociatedKeyOverlayView, overlayView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return overlayView;
}

void applyCardShadowToLayer(CALayer *layer, BOOL phoneStyle) {
    if (!layer) return;
    layer.shadowColor = [UIColor blackColor].CGColor;
    if (phoneStyle) {
        layer.shadowOffset = CGSizeMake(0, kShadowOffsetYPhone);
        layer.shadowOpacity = kShadowOpacityPhone;
        layer.shadowRadius = kShadowRadiusPhone;
    } else {
        layer.shadowOffset = CGSizeMake(0, kShadowOffsetYPopup);
        layer.shadowOpacity = kShadowOpacityPopup;
        layer.shadowRadius = kShadowRadiusPopup;
    }
}

void setOverlayToDismissAppearance(UIView *overlayView) {
    if (overlayView) {
        overlayView.backgroundColor = [UIColor colorWithWhite:kOverlayDismissAlpha alpha:kOverlayDismissAlpha];
    }
}

NSString *NormalizeExternalPaymentURL(NSString *raw) {
    if (raw == nil) {
        return nil;
    }
    NSString *s = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length == 0) {
        return nil;
    }
    NSString *lower = [s lowercaseString];
    if ([lower hasPrefix:@"javascript:"] || [lower hasPrefix:@"file:"] || [lower hasPrefix:@"data:"]) {
        return nil;
    }
    if (![lower hasPrefix:@"http://"] && ![lower hasPrefix:@"https://"]) {
        s = [@"https://" stringByAppendingString:s];
    }
    NSURL *u = [NSURL URLWithString:s];
    if (u == nil || u.scheme.length == 0) {
        return nil;
    }
    NSString *scheme = [u.scheme lowercaseString];
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return nil;
    }
    if (u.host.length == 0) {
        return nil;
    }
    return u.absoluteString;
}

#if !__has_feature(objc_arc)
#pragma clang diagnostic pop
#endif
