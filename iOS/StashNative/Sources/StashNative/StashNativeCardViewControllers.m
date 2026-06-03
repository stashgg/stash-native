//
//  StashNativeCardViewControllers.m
//  StashNative
//
//  View controller and view classes for card presentation.
//  Shared state via extern declarations; see StashNativeCard.m for definitions.
//

#import "StashNativeCard.h"
#import "StashNativeCardPrivate.h"
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static const void *kRotationResizeCardViewKey = &kRotationResizeCardViewKey;
static const void *kRotationResizeDisplayLinkKey = &kRotationResizeDisplayLinkKey;

static BOOL stashCGRectSizeDiffers(CGRect a, CGRect b) {
    return fabs(a.size.width - b.size.width) > 0.5 || fabs(a.size.height - b.size.height) > 0.5
        || fabs(a.origin.x - b.origin.x) > 0.5 || fabs(a.origin.y - b.origin.y) > 0.5;
}

#pragma mark - DragTrayView

@implementation DragTrayView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *handleView = [self viewWithTag:kDragHandleViewTag];
    if (handleView) {
        CGPoint pointInHandle = [self convertPoint:point toView:handleView];
        CGRect handleBounds = handleView.bounds;
        CGRect expandedBounds = CGRectInset(handleBounds, -kHandleHitAreaInset, -kHandleHitAreaInset);
        if (CGRectContainsPoint(expandedBounds, pointInHandle)) {
            return [super hitTest:point withEvent:event];
        }
    }
    return nil;
}

@end

#pragma mark - IPhoneCardViewController

@implementation IPhoneCardViewController

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotate {
    return NO;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationPortrait;
}

- (void)updateCornerRadiusMask {
    UIRectCorner cornersToRound = UIRectCornerTopLeft | UIRectCornerTopRight;
    CAShapeLayer *maskLayer = stash_createCornerRadiusMask(self.view.bounds, cornersToRound, kCornerRadiusDefault);
    self.view.layer.mask = maskLayer;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    if (self.skipLayoutDuringInitialSetup) {
        return;
    }
    // iOS 15: system may deliver a landscape transition even though this VC
    // returns portrait-only. Coerce to portrait to prevent broken layout.
    if (size.width > size.height) {
        size = CGSizeMake(size.height, size.width);
    }
    stash_resetCardExpandedStateAfterRotation();
    CGRect target = CGRectMake(0, 0, size.width, size.height);
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        stashRelayoutIPhoneCardWindowWithTargetBoundsAndProgress(target, 0.0);
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        stashRelayoutIPhoneCardWindowWithTargetBoundsAndProgress(target, 0.0);
    }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.skipLayoutDuringInitialSetup) {
        return;
    }
    UIWindow *w = self.view.window;
    if (!w) {
        return;
    }
    CGRect expected = stashSceneCoordinateBoundsForIPhoneCardWindow(w);
    // iOS 15: scene may report landscape bounds when this portrait-only card is presented.
    if (expected.size.width > expected.size.height) {
        expected = CGRectMake(0, 0, expected.size.height, expected.size.width);
    }
    if (stashCGRectSizeDiffers(w.frame, expected)) {
        stashRelayoutIPhoneCardWindowWithTargetBoundsAndProgress(expected, -1.0);
    }
}

@end

#pragma mark - IPhoneCardCurrentOrientationViewController (no rotation; allows all orientations)

@implementation IPhoneCardCurrentOrientationViewController

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (self.lockedOrientationMask != 0) {
        return self.lockedOrientationMask;
    }
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotate {
    return (self.lockedOrientationMask == 0);
}

- (void)updateCornerRadiusMask {
    UIRectCorner cornersToRound = UIRectCornerTopLeft | UIRectCornerTopRight;
    CAShapeLayer *maskLayer = stash_createCornerRadiusMask(self.view.bounds, cornersToRound, kCornerRadiusDefault);
    self.view.layer.mask = maskLayer;
}

- (void)rotationResizeTick:(CADisplayLink *)link {
    UIView *cardView = objc_getAssociatedObject(self, kRotationResizeCardViewKey);
    if (cardView) {
        stash_layoutCardContentToBounds(cardView);
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    UIWindow *window = self.view.window;
    if (!window) return;
    UIView *cardView = [window viewWithTag:kCardViewTag];
    if (!cardView) return;
    
    stash_resetCardExpandedStateAfterRotation();
    
    CGRect targetBounds = CGRectMake(0, 0, size.width, size.height);

    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        stash_switchWebViewToFrameLayoutInCardView(cardView);
        stashRelayoutIPhoneCardWindowWithTargetBoundsAndProgress(targetBounds, 0.0);
        objc_setAssociatedObject(self, kRotationResizeCardViewKey, cardView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CADisplayLink *resizeLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(rotationResizeTick:)];
        objc_setAssociatedObject(self, kRotationResizeDisplayLinkKey, resizeLink, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [resizeLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        CADisplayLink *resizeLink = objc_getAssociatedObject(self, kRotationResizeDisplayLinkKey);
        [resizeLink invalidate];
        objc_setAssociatedObject(self, kRotationResizeDisplayLinkKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kRotationResizeCardViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        stashRelayoutIPhoneCardWindowWithTargetBoundsAndProgress(targetBounds, 0.0);
        self.cardFrame = cardView.frame;
        self.customFrame = cardView.frame;
        stash_resetCardExpandedStateAfterRotation();
        stash_layoutCardContentToBounds(cardView);
        [cardView setNeedsLayout];
        [cardView layoutIfNeeded];
        for (UIView *subview in cardView.subviews) {
            [subview setNeedsLayout];
            [subview layoutIfNeeded];
        }
        CAShapeLayer *maskLayer = stash_createCornerRadiusMask(cardView.bounds, UIRectCornerTopLeft | UIRectCornerTopRight, kCornerRadiusDefault);
        cardView.layer.mask = maskLayer;
    }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.skipLayoutDuringInitialSetup) {
        return;
    }
    UIWindow *w = self.view.window;
    if (!w) {
        return;
    }
    CGRect expected = stashSceneCoordinateBoundsForIPhoneCardWindow(w);
    // iOS 15: scene may report bounds that violate the locked orientation.
    if (self.lockedOrientationMask != 0) {
        BOOL boundsLandscape = expected.size.width > expected.size.height;
        BOOL lockPortrait = (self.lockedOrientationMask == UIInterfaceOrientationMaskPortrait);
        BOOL lockLandscape = (self.lockedOrientationMask & UIInterfaceOrientationMaskLandscape) &&
                             !(self.lockedOrientationMask & UIInterfaceOrientationMaskPortrait);
        if ((lockPortrait && boundsLandscape) || (lockLandscape && !boundsLandscape)) {
            expected = CGRectMake(0, 0, expected.size.height, expected.size.width);
        }
    }
    if (stashCGRectSizeDiffers(w.frame, expected)) {
        stashRelayoutIPhoneCardWindowWithTargetBoundsAndProgress(expected, -1.0);
    }
}

@end

#pragma mark - IPadModalViewController

@implementation IPadModalViewController

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (void)updateCornerRadiusMaskForCardView {
    UIView *cardView = [self.view viewWithTag:kCardViewTag];
    if (!cardView) return;
    
    CAShapeLayer *maskLayer = stash_createCornerRadiusMask(cardView.bounds, UIRectCornerAllCorners, kCornerRadiusDefault);
    cardView.layer.mask = maskLayer;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    UIView *cardView = [self.view viewWithTag:kCardViewTag];
    if (!cardView) return;
    
    CGRect targetScreenBounds = CGRectMake(0, 0, size.width, size.height);
    CGRect newFrame = stashFrameForIPadSdkCard(targetScreenBounds, cardView);
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        cardView.frame = newFrame;
        stash_layoutCardContentToBounds(cardView);
        [cardView layoutIfNeeded];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        self.customFrame = newFrame;
        cardView.frame = newFrame;
        stash_layoutCardContentToBounds(cardView);
        [cardView layoutIfNeeded];
        [self updateCornerRadiusMaskForCardView];
    }];
}

@end

#pragma mark - ModalViewController (Window-based modal, no portrait lock; same pattern as iPad checkout)

@implementation ModalViewController

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    CGRect targetBounds = CGRectMake(0, 0, size.width, size.height);
    UIView *overlayView = objc_getAssociatedObject(self, (__bridge const void *)StashNativeAssociatedKeyOverlayView);
    CGRect newCardFrame = stash_computeModalFrameForScreenBounds(targetBounds);
    UIView *cardView = [self.view viewWithTag:kCardViewTag];
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        if (overlayView) {
            overlayView.frame = targetBounds;
        }
        if (cardView) {
            cardView.frame = newCardFrame;
            [cardView layoutIfNeeded];
        }
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        self.customFrame = newCardFrame;
        [self updateCornerRadiusMaskForCardView];
    }];
}

- (void)updateCornerRadiusMaskForCardView {
    UIView *cardView = [self.view viewWithTag:kCardViewTag];
    if (!cardView) return;
    
    CAShapeLayer *maskLayer = stash_createCornerRadiusMask(cardView.bounds, UIRectCornerAllCorners, kCornerRadiusDefault);
    cardView.layer.mask = maskLayer;
}

@end

#pragma mark - SafariPortraitContainerViewController

/// Minimal portrait-only root VC for the dedicated UIWindow used to host SFSafariViewController
/// on the external-payment path (when the card window has already been dismissed and the game's
/// landscape window is key).  Presenting Safari from this VC gives it — and the system keyboard —
/// the correct portrait orientation and safe-area insets.
@implementation SafariPortraitContainerViewController

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotate {
    return NO;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationPortrait;
}

@end

#pragma mark - OrientationLockedViewController (Popup rotation only; modal uses ModalViewController)

@implementation OrientationLockedViewController

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    if (!stash_usePopupPresentation) {
        return;
    }
    
    CGRect targetBounds = CGRectMake(0, 0, size.width, size.height);
    UIView *overlayView = objc_getAssociatedObject(self, (__bridge const void *)StashNativeAssociatedKeyOverlayView);
    CGRect newCardFrame = stash_computePopupFrameForScreenBounds(targetBounds);
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        if (overlayView) {
            overlayView.frame = targetBounds;
        }
        if (stash_usePopupPresentation) {
            self.view.frame = newCardFrame;
            self.customFrame = newCardFrame;
        }
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        self.customFrame = newCardFrame;
        [self updateCornerRadiusMask];
    }];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    
    if (!stash_usePopupPresentation) {
        return;
    }
    
    CGRect containerBounds = self.view.bounds;
    UIWindow *cardWindow = self.view.window;
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    if (cardWindow && !CGRectEqualToRect(cardWindow.frame, screenBounds)) {
        cardWindow.frame = screenBounds;
    }
    
    // Use container view bounds for overlay so it stays in sync during rotation
    // (screen bounds can swap at a different time than the view hierarchy, causing rotation artifacts)
    UIView *overlayView = objc_getAssociatedObject(self, (__bridge const void *)StashNativeAssociatedKeyOverlayView);
    if (overlayView && !CGRectEqualToRect(overlayView.frame, containerBounds)) {
        overlayView.frame = containerBounds;
    }
    
    // Use appropriate frame calculation based on presentation type
    CGRect newFrame = stash_computePopupFrameForScreenBounds(containerBounds);
    if (!CGRectEqualToRect(self.view.frame, newFrame)) {
        [UIView animateWithDuration:kPopupFrameAnimationDuration animations:^{
            self.view.frame = newFrame;
            self.customFrame = newFrame;
        } completion:^(BOOL finished) {
            [self updateCornerRadiusMask];
        }];
    }
}

- (void)updateCornerRadiusMask {
    CAShapeLayer *maskLayer = stash_createCornerRadiusMask(self.view.bounds, UIRectCornerAllCorners, kCornerRadiusDefault);
    self.view.layer.mask = maskLayer;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (self.enforcePortrait && !stash_isRunningOniPad()) {
        return UIInterfaceOrientationMaskPortrait;
    }
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if (self.enforcePortrait && !stash_isRunningOniPad()) {
        return UIInterfaceOrientationPortrait;
    }
    return stash_getInterfaceOrientation();
}

@end
