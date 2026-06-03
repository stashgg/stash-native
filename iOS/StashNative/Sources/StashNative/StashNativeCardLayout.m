//
//  StashNativeCardLayout.m
//  StashNative
//
//  Stateless card view-layout utilities (WebView frame/scroll setup, drag-tray + handle layout,
//  background color). Moved verbatim from StashNativeCard.m. These read no file-scope state; the
//  frame geometry that depends on the sizing-config statics stays in StashNativeCard.m.
//

#import "StashNativeCardPrivate.h"

#if !__has_feature(objc_arc)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshadow"
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

WKWebView* stash_switchWebViewToFrameLayoutInCardView(UIView *cardView) {
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

void stash_layoutCardContentToBounds(UIView *cardView) {
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
    stash_updateDragTrayAndHandleInCardView(cardView, bounds.size.width);
}

void stash_updateDragTrayAndHandleInCardView(UIView *cardView, CGFloat cardWidth) {
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

void stash_configureScrollViewForWebView(UIScrollView* scrollView) {
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

void stash_setWebViewBackgroundColor(WKWebView* webView, UIColor* color) {
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

#if !__has_feature(objc_arc)
#pragma clang diagnostic pop
#endif
