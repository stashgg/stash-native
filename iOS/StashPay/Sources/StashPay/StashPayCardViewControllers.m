//
//  StashPayCardViewControllers.m
//  StashPay
//
//  View controller and view classes for card presentation.
//  Shared state via extern declarations; see StashPayCard.m for definitions.
//

#import "StashPayCard.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#pragma mark - Extern declarations (defined in StashPayCard.m)

extern BOOL _usePopupPresentation;
extern BOOL _useModalPresentation;
extern BOOL _modalShowDragBar;
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
extern NSString * const StashPayAssociatedKeyOverlayView;

extern BOOL isRunningOniPad(void);
extern CGSize calculateiPadCardSize(CGRect screenBounds);
extern CAShapeLayer* createCornerRadiusMask(CGRect bounds, UIRectCorner corners, CGFloat radius);
extern UIInterfaceOrientation getInterfaceOrientation(void);
extern CGRect computePopupFrameForScreenBounds(CGRect screenBounds);
extern CGRect computeModalFrameForScreenBounds(CGRect screenBounds);
extern void updateDragTrayAndHandleInCardView(UIView *cardView, CGFloat cardWidth);

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
    CGSize newCardSize = calculateiPadCardSize(targetScreenBounds);
    
    CGFloat newX = (size.width - newCardSize.width) / 2.0;
    CGFloat newY = (size.height - newCardSize.height) / 2.0;
    CGRect newFrame = CGRectMake(newX, newY, newCardSize.width, newCardSize.height);
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        cardView.frame = newFrame;
        updateDragTrayAndHandleInCardView(cardView, newCardSize.width);
        [cardView layoutIfNeeded];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        self.previousScreenSize = size;
        self.customFrame = newFrame;
        [self updateCornerRadiusMaskForCardView];
    }];
}

@end

#pragma mark - OrientationLockedViewController (Modal / Popup rotation)

@interface OrientationLockedViewController : UIViewController
@property (nonatomic, assign) CGRect customFrame;
@property (nonatomic, assign) BOOL enforcePortrait;
@property (nonatomic, assign) BOOL skipLayoutDuringInitialSetup;
@property (nonatomic, assign) CGSize previousScreenSize;
@property (nonatomic, assign) BOOL isModalPresentation;
- (void)updateCornerRadiusMask;
@end

@implementation OrientationLockedViewController

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    if (!self.isModalPresentation && !_usePopupPresentation) {
        return;
    }
    
    CGRect targetBounds = CGRectMake(0, 0, size.width, size.height);
    UIView *overlayView = objc_getAssociatedObject(self, (__bridge const void *)StashPayAssociatedKeyOverlayView);
    CGRect newCardFrame = self.isModalPresentation
        ? computeModalFrameForScreenBounds(targetBounds)
        : computePopupFrameForScreenBounds(targetBounds);
    UIView *cardView = self.isModalPresentation ? [self.view viewWithTag:kCardViewTag] : nil;
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        if (overlayView) {
            overlayView.frame = targetBounds;
        }
        if (self.isModalPresentation && cardView) {
            cardView.frame = newCardFrame;
            if (_modalShowDragBar) {
                updateDragTrayAndHandleInCardView(cardView, newCardFrame.size.width);
            }
            [cardView layoutIfNeeded];
        } else if (_usePopupPresentation) {
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
    if (!_usePopupPresentation && !self.isModalPresentation) {
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
    UIView *overlayView = objc_getAssociatedObject(self, (__bridge const void *)StashPayAssociatedKeyOverlayView);
    if (overlayView && !CGRectEqualToRect(overlayView.frame, containerBounds)) {
        overlayView.frame = containerBounds;
    }
    
    // Use appropriate frame calculation based on presentation type
    CGRect newFrame;
    if (self.isModalPresentation) {
        newFrame = computeModalFrameForScreenBounds(containerBounds);
    } else {
        newFrame = computePopupFrameForScreenBounds(containerBounds);
    }
    
    // For modal, update the cardView frame; for popup, update the view frame
    if (self.isModalPresentation) {
        UIView *cardView = [self.view viewWithTag:kCardViewTag];
        if (cardView && !CGRectEqualToRect(cardView.frame, newFrame)) {
            [UIView animateWithDuration:kPopupFrameAnimationDuration animations:^{
                cardView.frame = newFrame;
                if (_modalShowDragBar) {
                    updateDragTrayAndHandleInCardView(cardView, newFrame.size.width);
                }
                [cardView layoutIfNeeded];
            } completion:^(BOOL finished) {
                self.customFrame = newFrame;
                [self updateCornerRadiusMask];
            }];
        }
    } else {
        if (!CGRectEqualToRect(self.view.frame, newFrame)) {
            [UIView animateWithDuration:kPopupFrameAnimationDuration animations:^{
                self.view.frame = newFrame;
                self.customFrame = newFrame;
            } completion:^(BOOL finished) {
                [self updateCornerRadiusMask];
            }];
        }
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
