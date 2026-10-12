#import "StashNativeCardPrivate.h"
#import <math.h>

static BOOL StashContainsFirstResponder(UIView *view) {
    if (view.isFirstResponder) return YES;
    for (UIView *child in view.subviews) if (StashContainsFirstResponder(child)) return YES;
    return NO;
}

static UIInterfaceOrientation StashKeyboardWindowOrientation(UIWindow *window) {
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) return window.windowScene.effectiveGeometry.interfaceOrientation;
#endif
    return window.windowScene.interfaceOrientation;
}

static BOOL StashKeyboardFrameIsVisible(CGRect frame, UIWindow *window) {
    if (!isfinite(frame.origin.x) || !isfinite(frame.origin.y) || !isfinite(frame.size.width) ||
        !isfinite(frame.size.height) || CGRectIsEmpty(frame)) return NO;
    CGRect overlap = CGRectIntersection(window.bounds, frame);
    CGFloat safeBottom = CGRectGetMaxY(window.bounds) - window.safeAreaInsets.bottom;
    return !CGRectIsNull(overlap) && overlap.size.width > 0.5 && overlap.size.height > 0.5 &&
        CGRectGetMinY(overlap) < safeBottom - 0.5;
}

static BOOL StashKeyboardFrameIsDocked(CGRect frame, UIWindow *window) {
    CGFloat windowBottom = CGRectGetMaxY(window.bounds);
    return StashKeyboardFrameIsVisible(frame, window) &&
        CGRectGetMinX(frame) <= CGRectGetMinX(window.bounds) + 0.5 &&
        CGRectGetMaxX(frame) >= CGRectGetMaxX(window.bounds) - 0.5 &&
        CGRectGetMaxY(frame) >= windowBottom - 0.5;
}

static BOOL StashKeyboardGuideIsInsetDocked(CGRect frame, UIWindow *window, UIView *content) {
    CGFloat bottom = CGRectGetMaxY(frame);
    CGFloat windowBottom = CGRectGetMaxY(window.bounds);
    CGRect contentFrame = [window convertRect:content.bounds fromView:content];
    return StashKeyboardFrameIsVisible(frame, window) &&
        CGRectGetMinX(frame) <= CGRectGetMinX(window.bounds) + 0.5 &&
        CGRectGetMaxX(frame) >= CGRectGetMaxX(window.bounds) - 0.5 &&
        fabs(bottom - CGRectGetMaxY(contentFrame)) <= 0.5 &&
        bottom >= windowBottom - window.safeAreaInsets.bottom - 0.5 && bottom < windowBottom - 0.5;
}

@implementation StashCheckoutViewController (Keyboard)
- (void)keyboardChanged:(NSNotification *)note {
    if (![self.session isActive] || !self.view.window) return;
    BOOL ownsResponder = StashContainsFirstResponder(self.session.webView);
    if (!self.keyboardEpisodeOwned && !ownsResponder) return;
    if ([note.object isKindOfClass:UIScreen.class] && note.object != self.view.window.screen) return;
    StashRemoveFormInputAccessoryView(self.session.webView);
    self.keyboardFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    self.keyboardNotificationWindow = self.view.window;
    self.keyboardNotificationWindowBounds = self.view.window.bounds;
    self.keyboardNotificationOrientation = StashKeyboardWindowOrientation(self.view.window);
    CGRect keyboard = self.view.window ? [self.view.window convertRect:self.keyboardFrame fromCoordinateSpace:self.view.window.screen.coordinateSpace] : CGRectZero;
    BOOL hide = [note.name isEqualToString:UIKeyboardWillHideNotification];
    CGRect overlap = CGRectIntersection(self.view.window.bounds, keyboard);
    CGFloat safeBottom = CGRectGetMaxY(self.view.window.bounds) - self.view.window.safeAreaInsets.bottom;
    BOOL visible = !CGRectIsNull(overlap) && overlap.size.width > 0.5 && overlap.size.height > 0.5 &&
        CGRectGetMinY(overlap) < safeBottom - 0.5;
    // A real keyboard notification establishes ownership; WK can remain first responder for BODY or buttons.
    if (visible && ownsResponder) self.keyboardEpisodeOwned = YES;
    self.keyboardNotificationVisible = visible && (!hide || ownsResponder);
    self.keyboardNotificationHiding = hide;
    [self updateKeyboardGuideOcclusion];
    [self updatePresentationAnimated:YES];
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}
- (void)keyboardSettled:(NSNotification *)note {
    if ([self.session isActive] && self.session.keyboardVisible)
        StashRemoveFormInputAccessoryView(self.session.webView);
    [self scheduleFocusReveal];
}
- (void)updateKeyboardGuideOcclusion {
    if (![self.session isActive] || !self.view.window) return;
    CGRect frame = self.view.keyboardLayoutGuide.layoutFrame;
    BOOL frameChanged = !self.hasKeyboardGuideFrame || !CGRectEqualToRect(frame, self.previousKeyboardGuideFrame);
    self.previousKeyboardGuideFrame = frame;
    self.hasKeyboardGuideFrame = YES;
    UIWindow *window = self.view.window;
    CGRect windowFrame = [window convertRect:frame fromView:self.view];
    CGRect windowOverlap = CGRectIntersection(window.bounds, windowFrame);
    CGFloat safeBottom = CGRectGetMaxY(window.bounds) - window.safeAreaInsets.bottom;
    // The hidden guide can retain the home-indicator inset even with usesBottomSafeArea disabled.
    BOOL inWindow = !CGRectIsNull(windowOverlap) && windowOverlap.size.width > 0.5 &&
        windowOverlap.size.height > 0.5 && CGRectGetMinY(windowOverlap) < safeBottom - 0.5;
    // A floating sheet's hidden guide can extend from its own bottom to the window bottom.
    BOOL belowContentBaseline = CGRectGetMinY(frame) >= CGRectGetMaxY(self.view.bounds) - 0.5 &&
        windowFrame.size.width >= window.bounds.size.width * 0.75 && CGRectGetMaxY(windowFrame) >= safeBottom - 0.5;
    if (!self.keyboardNotificationVisible && belowContentBaseline) inWindow = NO;
    if (self.keyboardEpisodeOwned && inWindow) self.keyboardGuideWasVisible = YES;
    if (self.keyboardNotificationHiding && self.keyboardGuideWasVisible && !inWindow)
        self.keyboardNotificationVisible = NO;
    if (!StashContainsFirstResponder(self.session.webView)) {
        self.keyboardEpisodeOwned = NO;
        self.keyboardNotificationVisible = NO;
    }
    BOOL visible = self.keyboardEpisodeOwned && (self.keyboardNotificationVisible || inWindow);
    if (!visible) {
        self.keyboardEpisodeOwned = NO;
        self.keyboardGuideWasVisible = NO;
        self.keyboardNotificationWindow = nil;
    }
    BOOL visibilityChanged = visible != self.session.keyboardVisible;
    self.session.keyboardVisible = visible;
    if (visibilityChanged && visible) [self cancelContentExpansion];
    BOOL undocked = visible && inWindow && !StashKeyboardFrameIsDocked(windowFrame, window) &&
        !StashKeyboardGuideIsInsetDocked(windowFrame, window, self.view);
    BOOL geometryChanged = visibilityChanged || undocked != self.keyboardGuideUndocked;
    self.keyboardGuideUndocked = undocked;
    if (visibilityChanged) {
        if (visible) [self.session revealInitialContent];
        else [self.session.webView evaluateJavaScript:@"if(window.__stashSetKeyboardOcclusion)window.__stashSetKeyboardOcclusion(null)" completionHandler:nil];
    }
    if (!frameChanged && !geometryChanged) return;
    if ((geometryChanged || (frameChanged && visible)) && !self.keyboardGuideLayoutQueued) {
        self.keyboardGuideLayoutQueued = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.keyboardGuideLayoutQueued = NO;
            if (![self.session isActive] || !self.view.window) return;
            [self updatePresentationAnimated:NO];
            [self.view setNeedsLayout];
            [self.view layoutIfNeeded];
            [self scheduleFocusReveal];
        });
    }
    [self scheduleFocusReveal];
}
- (CGRect)resolvedKeyboardFrameInView:(UIView *)view dockedOnly:(BOOL)dockedOnly {
    UIView *content = self.viewIfLoaded;
    UIWindow *window = content.window;
    if (!self.session.keyboardVisible || !self.keyboardEpisodeOwned || !window ||
        self.session.webView.window != window || (view != window && view.window != window)) return CGRectNull;
    CGRect guide = CGRectNull;
    BOOL clampedBelowContent = NO;
    if (self.hasKeyboardGuideFrame) {
        CGRect local = content.keyboardLayoutGuide.layoutFrame;
        CGRect candidate = [window convertRect:local fromView:content];
        // A floating sheet can clamp the docked guide below its own content bounds.
        clampedBelowContent = StashKeyboardFrameIsDocked(candidate, window) &&
            CGRectGetMinY(local) >= CGRectGetMaxY(content.bounds) - 0.5;
        if (StashKeyboardFrameIsVisible(candidate, window) && !clampedBelowContent) guide = candidate;
    }
    CGRect notification = CGRectNull;
    BOOL sameContext = self.keyboardNotificationWindow == window &&
        CGRectEqualToRect(self.keyboardNotificationWindowBounds, window.bounds) &&
        self.keyboardNotificationOrientation == StashKeyboardWindowOrientation(window);
    if (sameContext && self.keyboardNotificationVisible && !self.keyboardNotificationHiding) {
        CGRect candidate = [window convertRect:self.keyboardFrame fromCoordinateSpace:window.screen.coordinateSpace];
        if (StashKeyboardFrameIsVisible(candidate, window)) notification = candidate;
    }
    CGRect keyboard = CGRectNull;
    BOOL guideDocked = !CGRectIsNull(guide) && (StashKeyboardFrameIsDocked(guide, window) ||
        StashKeyboardGuideIsInsetDocked(guide, window, content));
    if (!CGRectIsNull(guide)) {
        // Native sheets can anchor an otherwise matching guide above the window's bottom inset.
        BOOL insetGuide = StashKeyboardGuideIsInsetDocked(guide, window, content) &&
            StashKeyboardFrameIsDocked(notification, window) &&
            fabs(guide.size.width - notification.size.width) <= 0.5 &&
            fabs(guide.size.height - notification.size.height) <= 0.5 &&
            fabs(CGRectGetMinX(guide) - CGRectGetMinX(notification)) <= 0.5;
        if (insetGuide) {
            keyboard = notification;
        } else if (!guideDocked) {
            // A current undocked guide wins over a previous full-width notification.
            if (dockedOnly) return CGRectNull;
            keyboard = guide;
        } else {
            keyboard = guide;
            // Either source can lag; keep the earlier valid docked top.
            if (StashKeyboardFrameIsDocked(notification, window) &&
                CGRectGetMinY(notification) < CGRectGetMinY(guide)) keyboard = notification;
        }
    } else if (!self.hasKeyboardGuideFrame || !self.keyboardGuideWasVisible || clampedBelowContent) {
        // Notifications provide the initial geometry before a usable guide arrives.
        keyboard = notification;
    }
    if (CGRectIsNull(keyboard) || (dockedOnly && !StashKeyboardFrameIsDocked(keyboard, window) &&
        !(guideDocked && CGRectEqualToRect(keyboard, guide)))) return CGRectNull;
    return view == window ? keyboard : [view convertRect:keyboard fromView:window];
}
- (NSArray<NSNumber *> *)focusKeyboardOcclusion {
    WKWebView *web = self.session.webView;
    if (CGRectIsEmpty(web.bounds)) return nil;
    CGRect keyboard = [self resolvedKeyboardFrameInView:web dockedOnly:NO];
    if (CGRectIsNull(keyboard)) return nil;
    CGRect overlap = CGRectIntersection(web.bounds, keyboard);
    if (CGRectIsNull(overlap) || CGRectIsEmpty(overlap)) return nil;
    return @[@(overlap.origin.x - web.bounds.origin.x), @(overlap.origin.y - web.bounds.origin.y),
        @(overlap.size.width), @(overlap.size.height), @(web.bounds.size.width), @(web.bounds.size.height)];
}
- (void)scheduleFocusReveal {
    if (![self.session isActive] || !self.session.keyboardVisible || !self.view.window) return;
    if (self.focusRevealQueued) return;
    self.focusRevealQueued = YES;
    WKWebView *web = self.session.webView;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.focusRevealQueued = NO;
        if (![self.session isActive] || !self.session.keyboardVisible || !self.view.window || self.session.webView != web) return;
        [web layoutIfNeeded];
        [self normalizeIdleRootScrollOffset];
        NSArray *occlusion = [self focusKeyboardOcclusion];
        NSData *data = occlusion ? [NSJSONSerialization dataWithJSONObject:occlusion options:0 error:nil] : nil;
        NSString *value = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        NSString *script = [NSString stringWithFormat:@"if(window.__stashSetKeyboardOcclusion)window.__stashSetKeyboardOcclusion(%@);"
            @"if(window.__stashRevealFocusedElement)window.__stashRevealFocusedElement()", value ?: @"null"];
        [web evaluateJavaScript:script completionHandler:nil];
#if !__has_feature(objc_arc)
        [value release];
#endif
    });
}
- (BOOL)canNormalizeIdleRootScrollOffset {
    WKWebView *web = self.session.webView;
    UIScrollView *scroll = web.scrollView;
    return [self.session isActive] && web.window && !self.geometryTransitioning && !self.dragging && !self.updatingLayout &&
        !scroll.tracking && !scroll.dragging && !scroll.decelerating && !scroll.zooming && !scroll.zoomBouncing;
}
- (BOOL)normalizeIdleRootScrollOffset {
    WKWebView *web = self.session.webView;
    UIScrollView *scroll = web.scrollView;
    if (![self canNormalizeIdleRootScrollOffset]) return NO;
    UIEdgeInsets insets = scroll.adjustedContentInset;
    CGRect keyboard = [self resolvedKeyboardFrameInView:web dockedOnly:YES];
    if (!CGRectIsNull(keyboard) && fabs(CGRectGetMinY(keyboard) - CGRectGetMaxY(web.bounds)) <= 1 &&
        CGRectGetMinX(keyboard) <= CGRectGetMinX(web.bounds) + 0.5 &&
        CGRectGetMaxX(keyboard) >= CGRectGetMaxX(web.bounds) - 0.5 && isfinite(scroll.contentInset.bottom)) {
        // The viewport already ends above this keyboard; its automatic bottom inset is redundant.
        insets.bottom = scroll.contentInset.bottom;
    }
    CGPoint minimum = CGPointMake(-insets.left, -insets.top);
    CGPoint maximum = CGPointMake(MAX(minimum.x, scroll.contentSize.width - scroll.bounds.size.width + insets.right),
        MAX(minimum.y, scroll.contentSize.height - scroll.bounds.size.height + insets.bottom));
    CGPoint offset = scroll.contentOffset;
    if (!isfinite(offset.x) || !isfinite(offset.y) || !isfinite(maximum.x) || !isfinite(maximum.y)) return NO;
    CGPoint clamped = CGPointMake(MIN(maximum.x, MAX(minimum.x, offset.x)), MIN(maximum.y, MAX(minimum.y, offset.y)));
    if (fabs(clamped.x - offset.x) < 0.5 && fabs(clamped.y - offset.y) < 0.5) return NO;
    // WebKit can retain a pre-resize root offset after keyboard expansion, shifting DOM and accessibility coordinates.
    [scroll setContentOffset:clamped animated:NO];
    return YES;
}
@end
