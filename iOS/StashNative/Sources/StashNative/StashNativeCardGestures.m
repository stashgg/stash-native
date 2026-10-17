#import "StashNativePrivate.h"
#import <math.h>

@implementation StashCheckoutViewController (Gestures)
- (BOOL)canExpandFromContent {
    return ![self usesFloatingNativeSizing] && !self.singleDetent && !self.session.expanded &&
        !self.session.keyboardVisible && !self.session.processing && !self.session.closing && !self.geometryTransitioning;
}
- (BOOL)contentPanPreventsActivation:(UIGestureRecognizer *)gesture {
    // Moving the card must not turn the same touch into a page tap or press.
    return [gesture.view isDescendantOfView:self.session.webView] &&
        ([gesture isKindOfClass:UITapGestureRecognizer.class] ||
         ([self canExpandFromContent] && [gesture isKindOfClass:UILongPressGestureRecognizer.class]));
}
- (void)observeContentScrollPans:(UIView *)view {
    if (!self.contentScrollPans) self.contentScrollPans = [NSHashTable weakObjectsHashTable];
    if ([view isKindOfClass:UIScrollView.class]) {
        UIPanGestureRecognizer *pan = ((UIScrollView *)view).panGestureRecognizer;
        if (![self.contentScrollPans containsObject:pan]) {
            [pan requireGestureRecognizerToFail:self.contentPan];
            [pan addTarget:self action:@selector(nativePanChanged:)];
            [self.contentScrollPans addObject:pan];
        }
    }
    for (UIView *child in view.subviews) [self observeContentScrollPans:child];
}
- (void)observeNativePans:(UIView *)view {
    if (!view || view == self.session.webView) return;
    if (view == self.presentationController.containerView && self.touchOriginObserver.view != view) {
        if (!self.touchOriginObserver) {
            UITapGestureRecognizer *observer = [[UITapGestureRecognizer alloc] init];
            observer.delegate = self;
            observer.cancelsTouchesInView = NO;
            observer.delaysTouchesBegan = NO;
            observer.delaysTouchesEnded = NO;
            self.touchOriginObserver = observer;
#if !__has_feature(objc_arc)
            [observer release];
#endif
        }
        [view addGestureRecognizer:self.touchOriginObserver];
    }
    if (!self.observedPans) self.observedPans = [NSMutableArray array];
    for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
        if ([gesture isKindOfClass:UIPanGestureRecognizer.class] && ![self.observedPans containsObject:(UIPanGestureRecognizer *)gesture]) {
            [gesture addTarget:self action:@selector(nativePanChanged:)];
            [self.observedPans addObject:(UIPanGestureRecognizer *)gesture];
        }
    }
    for (UIView *child in view.subviews) [self observeNativePans:child];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer == self.contentPan) {
        if (self.contentPan.state == UIGestureRecognizerStatePossible) self.contentPan.cancelsTouchesInView = NO;
        self.contentTouchView = touch.view;
        [self observeContentScrollPans:self.session.webView];
        return YES;
    }
    if (gestureRecognizer != self.touchOriginObserver) return YES;
    self.touchBeganInWebContent = [touch.view isDescendantOfView:self.session.webView];
    [self updateDismissalPolicy];
    // Observe the origin without recognizing, delaying, or cancelling any touch.
    return NO;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer != self.contentPan) return YES;
    CGPoint velocity = [self.contentPan velocityInView:self.session.webView];
    if (fabs(velocity.y) <= fabs(velocity.x)) return NO;
    if (velocity.y < 0 && [self canExpandFromContent]) {
        if (@available(iOS 16.0, *)) {
            self.contentPan.cancelsTouchesInView = YES;
            return YES;
        }
        return NO;
    }
    for (UIView *view = self.contentTouchView; view && view != self.session.webView; view = view.superview) {
        if (![view isKindOfClass:UIScrollView.class]) continue;
        UIScrollView *scroll = (UIScrollView *)view;
        if (!scroll.scrollEnabled) continue;
        CGFloat minimum = -scroll.adjustedContentInset.top;
        CGFloat maximum = MAX(minimum, scroll.contentSize.height - scroll.bounds.size.height + scroll.adjustedContentInset.bottom);
        if ((velocity.y > 0 && scroll.contentOffset.y > minimum + 0.5) ||
            (velocity.y < 0 && scroll.contentOffset.y < maximum - 0.5)) return NO;
    }
    // Consume an edge pull before WebKit can hand it to the native sheet.
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer != self.contentPan) return NO;
    return [otherGestureRecognizer.view isDescendantOfView:self.session.webView] &&
        ![self contentPanPreventsActivation:otherGestureRecognizer] &&
        ![self.contentScrollPans containsObject:(id)otherGestureRecognizer];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    UIView *otherView = otherGestureRecognizer.view;
    if (gestureRecognizer == self.contentPan && [self contentPanPreventsActivation:otherGestureRecognizer]) return YES;
    return gestureRecognizer == self.contentPan && [otherGestureRecognizer isKindOfClass:UIPanGestureRecognizer.class] && otherView != self.session.webView &&
        ![otherGestureRecognizer isKindOfClass:UIScreenEdgePanGestureRecognizer.class] &&
        [self.session.webView isDescendantOfView:otherView];
}
- (void)finishContentExpansion:(BOOL)expanded animated:(BOOL)animated {
    if (!self.contentExpansionActive) return;
    if (@available(iOS 16.0, *)) {
        UISheetPresentationController *sheet = self.sheetPresentationController;
        BOOL wasUpdatingLayout = self.updatingLayout;
        self.updatingLayout = YES;
        void (^changes)(void) = ^{
            self.contentExpansionActive = NO;
            self.session.expanded = expanded;
            BOOL selection = expanded || self.session.keyboardVisible;
            self.requestedNativeExpanded = selection;
            self.hasRequestedNativeSelection = YES;
            [sheet invalidateDetents];
            sheet.selectedDetentIdentifier = [self nativeDetentIdentifierForExpanded:selection];
        };
        if (animated && !UIAccessibilityIsReduceMotionEnabled()) [sheet animateChanges:changes];
        else changes();
        self.updatingLayout = wasUpdatingLayout;
    }
}
- (void)cancelContentExpansion {
    if (!self.contentExpansionActive) return;
    [self finishContentExpansion:self.session.expanded animated:NO];
    self.contentPan.enabled = NO;
    self.contentPan.enabled = YES;
}
- (void)trackContentExpansion:(UIPanGestureRecognizer *)gesture {
    if (@available(iOS 16.0, *)) {
        CGFloat maximum = [self contentHeightForMaximum:self.nativeMaximumDetentValue expanded:YES];
        if (gesture.state == UIGestureRecognizerStateBegan && [self canExpandFromContent] &&
            self.hasNativeMaximumDetentValue && [gesture velocityInView:self.view.window].y < 0) {
            self.contentExpansionStartHeight = [self contentHeightForMaximum:self.nativeMaximumDetentValue expanded:NO];
            self.contentExpansionHeight = self.contentExpansionStartHeight;
            self.contentExpansionActive = maximum > self.contentExpansionStartHeight + 0.5;
        }
        if (!self.contentExpansionActive) return;
        if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
            CGFloat translation = [gesture translationInView:self.view.window].y;
            self.contentExpansionHeight = MIN(maximum,
                MAX(self.contentExpansionStartHeight, self.contentExpansionStartHeight - translation));
            [self.sheetPresentationController invalidateDetents];
        } else {
            CGFloat velocity = [gesture velocityInView:self.view.window].y;
            CGFloat distance = self.contentExpansionHeight - self.contentExpansionStartHeight;
            BOOL expanded = gesture.state == UIGestureRecognizerStateEnded &&
                (velocity < -400 || (velocity <= 400 && distance > (maximum - self.contentExpansionStartHeight) / 2));
            [self finishContentExpansion:expanded animated:YES];
        }
    }
}
- (void)nativePanChanged:(UIPanGestureRecognizer *)gesture {
    if (gesture == self.contentPan) [self trackContentExpansion:gesture];
    BOOL wasDragging = self.dragging;
    BOOL dragging = gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged;
    UIGestureRecognizerState webState = self.session.webView.scrollView.panGestureRecognizer.state;
    dragging |= webState == UIGestureRecognizerStateBegan || webState == UIGestureRecognizerStateChanged;
    UIGestureRecognizerState expansionState = self.contentPan.state;
    dragging |= expansionState == UIGestureRecognizerStateBegan || expansionState == UIGestureRecognizerStateChanged;
    for (UIPanGestureRecognizer *pan in self.observedPans)
        dragging |= pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged;
    for (UIPanGestureRecognizer *pan in self.contentScrollPans)
        dragging |= pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged;
    self.dragging = dragging;
    if (wasDragging && !dragging) {
        [self.session retryRootOffsetRepair];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self.session isActive] || self.dragging) return;
            BOOL deferred = self.deferredContentLayout;
            self.deferredContentLayout = NO;
            [self.session applyPendingContentHeight];
            if (deferred) [self updatePresentationAnimated:NO];
            [self.viewIfLoaded setNeedsLayout];
        });
    }
}
- (void)updateDismissalPolicy {
    self.modalInPresentation = !self.session.config.allowDismiss || self.session.processing ||
        self.session.codeLinkCompleted || self.touchBeganInWebContent;
    self.sheetPresentationController.prefersGrabberVisible = !self.session.processing;
}
@end
