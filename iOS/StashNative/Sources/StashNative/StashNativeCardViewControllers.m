//
//  StashNativeCardViewControllers.m
//  StashNative
//
//  View controller and view classes for card presentation.
//  Shared state via extern declarations; see StashNativeCard.m for definitions.
//

#import "StashNativeCard.h"
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static const void *kRotationResizeCardViewKey = &kRotationResizeCardViewKey;
static const void *kRotationResizeDisplayLinkKey = &kRotationResizeDisplayLinkKey;

#pragma mark - Extern declarations (defined in StashNativeCard.m)

extern BOOL _usePopupPresentation;
extern BOOL _useModalPresentation;
extern BOOL _modalAllowDismiss;
extern BOOL _useCustomPopupSize;
extern CGFloat _customPortraitWidthMultiplier;
extern CGFloat _customPortraitHeightMultiplier;
extern CGFloat _customLandscapeWidthMultiplier;
extern CGFloat _customLandscapeHeightMultiplier;
extern const CGFloat kPopupPortraitWidthMultiplier;
extern const CGFloat kPopupPortraitHeightMultiplier;
extern const CGFloat kPopupLandscapeWidthMultiplier;
extern const CGFloat kPopupLandscapeHeightMultiplier;
extern const CGFloat kCornerRadiusDefault;
extern const CGFloat kDragTrayHeight;
extern const CGFloat kHandleBarWidth;
extern const CGFloat kHandleBarHeight;
extern const CGFloat kHandleBarTopInset;
extern const CGFloat kHandleHitAreaInset;
extern const CGFloat kPopupBaseSizePercentageIPad;
extern const CGFloat kPopupBaseSizePercentagePhone;
extern const CGFloat kPopupBaseSizeMinIPad;
extern const CGFloat kPopupBaseSizeMinPhone;
extern const CGFloat kPopupBaseSizeMax;
extern const NSTimeInterval kPopupFrameAnimationDuration;
extern const NSInteger kCardViewTag;
extern const NSInteger kDragTrayViewTag;
extern const NSInteger kDragHandleViewTag;
extern NSString * const StashNativeAssociatedKeyOverlayView;

extern BOOL isRunningOniPad(void);
extern CGSize calculateiPadCardSize(CGRect screenBounds);
extern CGRect stashFrameForIPadSdkCard(CGRect screenBounds, UIView *cardView);
extern CAShapeLayer* createCornerRadiusMask(CGRect bounds, UIRectCorner corners, CGFloat radius);
extern UIInterfaceOrientation getInterfaceOrientation(void);
extern CGRect computePopupFrameForScreenBounds(CGRect screenBounds);
extern CGRect computeModalFrameForScreenBounds(CGRect screenBounds);
extern void updateDragTrayAndHandleInCardView(UIView *cardView, CGFloat cardWidth);
extern void layoutCardContentToBounds(UIView *cardView);
extern WKWebView *switchWebViewToFrameLayoutInCardView(UIView *cardView);
extern CGRect computePhoneCardFrameForBoundsAndOrientation(CGRect bounds, BOOL isLandscape);
extern void updateOriginalCardRatiosForOrientation(BOOL isLandscape);
extern void resetCardExpandedStateAfterRotation(void);

#pragma mark - DragTrayView

@interface DragTrayView : UIView
@end

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

@interface IPhoneCardViewController : UIViewController
@property (nonatomic, assign) CGRect cardFrame;
@property (nonatomic, assign) CGRect customFrame;
@property (nonatomic, assign) BOOL skipLayoutDuringInitialSetup;
- (void)updateCornerRadiusMask;
@end

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
    CAShapeLayer *maskLayer = createCornerRadiusMask(self.view.bounds, cornersToRound, kCornerRadiusDefault);
    self.view.layer.mask = maskLayer;
}

@end

#pragma mark - IPhoneCardCurrentOrientationViewController (no rotation; allows all orientations)

@interface IPhoneCardCurrentOrientationViewController : UIViewController
@property (nonatomic, assign) CGRect cardFrame;
@property (nonatomic, assign) CGRect customFrame;
@property (nonatomic, assign) BOOL skipLayoutDuringInitialSetup;
- (void)updateCornerRadiusMask;
@end

@implementation IPhoneCardCurrentOrientationViewController

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (void)updateCornerRadiusMask {
    UIRectCorner cornersToRound = UIRectCornerTopLeft | UIRectCornerTopRight;
    CAShapeLayer *maskLayer = createCornerRadiusMask(self.view.bounds, cornersToRound, kCornerRadiusDefault);
    self.view.layer.mask = maskLayer;
}

- (void)rotationResizeTick:(CADisplayLink *)link {
    UIView *cardView = objc_getAssociatedObject(self, kRotationResizeCardViewKey);
    if (cardView) {
        layoutCardContentToBounds(cardView);
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    UIWindow *window = self.view.window;
    if (!window) return;
    UIView *cardView = [window viewWithTag:kCardViewTag];
    UIView *overlayView = objc_getAssociatedObject(self, (__bridge const void *)StashNativeAssociatedKeyOverlayView);
    
    if (!cardView) return;
    
    resetCardExpandedStateAfterRotation();
    
    CGRect targetBounds = CGRectMake(0, 0, size.width, size.height);
    BOOL isLandscape = size.width > size.height;
    CGRect newCardFrame = computePhoneCardFrameForBoundsAndOrientation(targetBounds, isLandscape);
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        switchWebViewToFrameLayoutInCardView(cardView);
        if (overlayView) {
            overlayView.frame = targetBounds;
        }
        cardView.frame = newCardFrame;
        layoutCardContentToBounds(cardView);
        [cardView layoutIfNeeded];
        objc_setAssociatedObject(self, kRotationResizeCardViewKey, cardView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CADisplayLink *resizeLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(rotationResizeTick:)];
        objc_setAssociatedObject(self, kRotationResizeDisplayLinkKey, resizeLink, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [resizeLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        CADisplayLink *resizeLink = objc_getAssociatedObject(self, kRotationResizeDisplayLinkKey);
        [resizeLink invalidate];
        objc_setAssociatedObject(self, kRotationResizeDisplayLinkKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kRotationResizeCardViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cardView.frame = newCardFrame;
        self.cardFrame = newCardFrame;
        self.customFrame = newCardFrame;
        updateOriginalCardRatiosForOrientation(isLandscape);
        resetCardExpandedStateAfterRotation();
        layoutCardContentToBounds(cardView);
        [cardView setNeedsLayout];
        [cardView layoutIfNeeded];
        for (UIView *subview in cardView.subviews) {
            [subview setNeedsLayout];
            [subview layoutIfNeeded];
        }
        CAShapeLayer *maskLayer = createCornerRadiusMask(cardView.bounds, UIRectCornerTopLeft | UIRectCornerTopRight, kCornerRadiusDefault);
        cardView.layer.mask = maskLayer;
    }];
}

@end

#pragma mark - IPadModalViewController

@interface IPadModalViewController : UIViewController
@property (nonatomic, assign) CGSize previousScreenSize;
@property (nonatomic, assign) CGRect customFrame;
@property (nonatomic, assign) BOOL skipLayoutDuringInitialSetup;
- (void)updateCornerRadiusMaskForCardView;
@end

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
    
    CAShapeLayer *maskLayer = createCornerRadiusMask(cardView.bounds, UIRectCornerAllCorners, kCornerRadiusDefault);
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
        layoutCardContentToBounds(cardView);
        [cardView layoutIfNeeded];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        self.previousScreenSize = size;
        self.customFrame = newFrame;
        cardView.frame = newFrame;
        layoutCardContentToBounds(cardView);
        [cardView layoutIfNeeded];
        [self updateCornerRadiusMaskForCardView];
    }];
}

@end

#pragma mark - ModalViewController (Window-based modal, no portrait lock; same pattern as iPad checkout)

@interface ModalViewController : UIViewController
@property (nonatomic, assign) CGRect customFrame;
@property (nonatomic, assign) BOOL skipLayoutDuringInitialSetup;
- (void)updateCornerRadiusMaskForCardView;
@end

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
    CGRect newCardFrame = computeModalFrameForScreenBounds(targetBounds);
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
    
    CAShapeLayer *maskLayer = createCornerRadiusMask(cardView.bounds, UIRectCornerAllCorners, kCornerRadiusDefault);
    cardView.layer.mask = maskLayer;
}

@end

#pragma mark - OrientationLockedViewController (Popup rotation only; modal uses ModalViewController)

@interface OrientationLockedViewController : UIViewController
@property (nonatomic, assign) CGRect customFrame;
@property (nonatomic, assign) BOOL enforcePortrait;
@property (nonatomic, assign) BOOL skipLayoutDuringInitialSetup;
@property (nonatomic, assign) CGSize previousScreenSize;
- (void)updateCornerRadiusMask;
@end

@implementation OrientationLockedViewController

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    if (!_usePopupPresentation) {
        return;
    }
    
    CGRect targetBounds = CGRectMake(0, 0, size.width, size.height);
    UIView *overlayView = objc_getAssociatedObject(self, (__bridge const void *)StashNativeAssociatedKeyOverlayView);
    CGRect newCardFrame = computePopupFrameForScreenBounds(targetBounds);
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        if (overlayView) {
            overlayView.frame = targetBounds;
        }
        if (_usePopupPresentation) {
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
    
    // Handle both popup and modal presentation rotation/resize
    if (!_usePopupPresentation) {
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
    CGRect newFrame = computePopupFrameForScreenBounds(containerBounds);
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
    CAShapeLayer *maskLayer = createCornerRadiusMask(self.view.bounds, UIRectCornerAllCorners, kCornerRadiusDefault);
    self.view.layer.mask = maskLayer;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (self.enforcePortrait && !isRunningOniPad()) {
        return UIInterfaceOrientationMaskPortrait;
    }
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if (self.enforcePortrait && !isRunningOniPad()) {
        return UIInterfaceOrientationPortrait;
    }
    return getInterfaceOrientation();
}

@end
