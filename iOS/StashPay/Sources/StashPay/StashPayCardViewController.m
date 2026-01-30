//
//  StashPayCardViewController.m
//  StashPay
//
//  View controller for card presentation with orientation control.
//

#import "StashPayCardViewController.h"
#import <objc/runtime.h>

// Forward declaration for helper functions (defined in main implementation)
extern BOOL isRunningOniPad(void);
extern UIRectCorner getCornersToRoundForPosition(CGFloat verticalPosition, BOOL isiPad);
extern CAShapeLayer* createCornerRadiusMask(CGRect bounds, UIRectCorner corners, CGFloat radius);
extern CGFloat _cardVerticalPosition;
extern CGFloat _cardHeightRatio;
extern CGFloat _cardWidthRatio;
extern CGFloat _tabletWidthRatio;
extern CGFloat _tabletHeightRatio;
extern BOOL _usePopupPresentation;
extern BOOL _isCardExpanded;

#pragma mark - DragTrayView Implementation

@implementation StashPayDragTrayView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *handleView = [self viewWithTag:kDragHandleViewTag];
    if (handleView) {
        CGPoint pointInHandle = [self convertPoint:point toView:handleView];
        CGRect handleBounds = handleView.bounds;
        // Expand touch target for better usability
        CGRect expandedBounds = CGRectInset(handleBounds, -15, -15);
        if (CGRectContainsPoint(expandedBounds, pointInHandle)) {
            return [super hitTest:point withEvent:event];
        }
    }
    // Return nil to pass touches through to underlying views
    return nil;
}

@end

#pragma mark - StashPayCardViewController Implementation

@implementation StashPayCardViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        _cardState = StashPayCardStateCollapsed;
        _enforcePortrait = NO;
        _skipLayoutDuringInitialSetup = NO;
        _customFrame = CGRectZero;
    }
    return self;
}

#pragma mark - Layout

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    
    if (self.skipLayoutDuringInitialSetup) {
        return;
    }
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    UIWindow *cardWindow = self.view.window;
    
    // Ensure window frame matches screen
    if (cardWindow && !CGRectEqualToRect(cardWindow.frame, screenBounds)) {
        cardWindow.frame = screenBounds;
    }
    
    // Update overlay frame
    UIView *overlayView = objc_getAssociatedObject(self, "overlayView");
    if (overlayView && !CGRectEqualToRect(overlayView.frame, screenBounds)) {
        overlayView.frame = screenBounds;
    }
    
    if (_usePopupPresentation) {
        [self layoutForPopupMode:screenBounds];
    } else {
        [self layoutForCardMode:screenBounds];
    }
}

- (void)layoutForPopupMode:(CGRect)screenBounds {
    BOOL isLandscape = UIInterfaceOrientationIsLandscape([[UIApplication sharedApplication] statusBarOrientation]);
    
    CGFloat smallerDimension = fmin(screenBounds.size.width, screenBounds.size.height);
    CGFloat percentage = isRunningOniPad() ? 0.5 : 0.75;
    CGFloat baseSize = fmax(
        isRunningOniPad() ? 400.0 : 300.0,
        fmin(isRunningOniPad() ? 500.0 : 500.0, smallerDimension * percentage)
    );
    
    CGFloat widthMult = isLandscape ? kDefaultPopupLandscapeWidthMultiplier : kDefaultPopupPortraitWidthMultiplier;
    CGFloat heightMult = isLandscape ? kDefaultPopupLandscapeHeightMultiplier : kDefaultPopupPortraitHeightMultiplier;
    
    CGFloat popupWidth = baseSize * widthMult;
    CGFloat popupHeight = baseSize * heightMult;
    
    CGRect newFrame = CGRectMake(
        (screenBounds.size.width - popupWidth) / 2,
        (screenBounds.size.height - popupHeight) / 2,
        popupWidth,
        popupHeight
    );
    
    [self applyNewFrame:newFrame];
}

- (void)layoutForCardMode:(CGRect)screenBounds {
    if (self.skipLayoutDuringInitialSetup) {
        return;
    }
    
    // Don't recalculate during expand animation on iPhone
    if (!isRunningOniPad() && _isCardExpanded) {
        return;
    }
    
    CGFloat width, height, x, y;
    
    if (isRunningOniPad()) {
        // Check for rotation
        BOOL screenSizeChanged = [self detectRotationChange:screenBounds];
        
        if (screenSizeChanged || CGRectIsEmpty(self.customFrame) || 
            self.customFrame.size.width <= 0 || self.customFrame.size.height <= 0) {
            CGSize cardSize = [[self class] calculateiPadCardSizeForScreenBounds:screenBounds
                                                                 tabletWidthRatio:_tabletWidthRatio
                                                                tabletHeightRatio:_tabletHeightRatio];
            if (_isCardExpanded) {
                width = cardSize.width;
                height = cardSize.height;
            } else {
                width = cardSize.width * 0.7;
                height = cardSize.height * 0.7;
            }
            x = (screenBounds.size.width - width) / 2;
            y = (screenBounds.size.height - height) / 2;
        } else {
            // Same orientation - just recenter
            width = self.customFrame.size.width;
            height = self.customFrame.size.height;
            x = (screenBounds.size.width - width) / 2;
            y = (screenBounds.size.height - height) / 2;
        }
    } else {
        // iPhone: Use portrait dimensions
        CGRect portraitBounds = screenBounds;
        if (portraitBounds.size.width > portraitBounds.size.height) {
            CGFloat temp = portraitBounds.size.width;
            portraitBounds.size.width = portraitBounds.size.height;
            portraitBounds.size.height = temp;
        }
        width = portraitBounds.size.width * _cardWidthRatio;
        height = portraitBounds.size.height * _cardHeightRatio;
        x = (portraitBounds.size.width - width) / 2;
        y = portraitBounds.size.height * _cardVerticalPosition - height;
        if (y < 0) y = 0;
    }
    
    CGRect newFrame = CGRectMake(x, y, width, height);
    [self applyNewFrame:newFrame];
}

- (BOOL)detectRotationChange:(CGRect)screenBounds {
    if (CGRectIsEmpty(self.customFrame) || CGRectIsNull(self.customFrame) ||
        self.customFrame.size.width <= 0 || self.customFrame.size.height <= 0) {
        return YES;
    }
    
    BOOL wasLandscape = (self.customFrame.size.width > self.customFrame.size.height);
    BOOL isNowLandscape = (screenBounds.size.width > screenBounds.size.height);
    return (wasLandscape != isNowLandscape);
}

- (void)applyNewFrame:(CGRect)newFrame {
    if (CGRectEqualToRect(self.view.frame, newFrame)) {
        self.customFrame = newFrame;
        [self updateCornerRadiusMask];
        return;
    }
    
    CGFloat frameDifference = fabs(self.view.frame.origin.x - newFrame.origin.x) +
                              fabs(self.view.frame.origin.y - newFrame.origin.y) +
                              fabs(self.view.frame.size.width - newFrame.size.width) +
                              fabs(self.view.frame.size.height - newFrame.size.height);
    
    if (frameDifference > 50.0) {
        // Animate significant changes
        [UIView animateWithDuration:0.3 animations:^{
            self.view.frame = newFrame;
            self.customFrame = newFrame;
            [self updateDragTrayFrame:newFrame.size.width];
        } completion:^(BOOL finished) {
            [self updateCornerRadiusMask];
        }];
    } else {
        // Apply small changes immediately
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.view.frame = newFrame;
        self.customFrame = newFrame;
        [self updateDragTrayFrame:newFrame.size.width];
        [CATransaction commit];
        [self updateCornerRadiusMask];
    }
}

- (void)updateDragTrayFrame:(CGFloat)width {
    UIView *dragTray = [self.view viewWithTag:kDragTrayViewTag];
    if (dragTray) {
        dragTray.frame = CGRectMake(0, 0, width, kDragTrayHeight);
        UIView *handle = [dragTray viewWithTag:kDragHandleViewTag];
        if (handle) {
            CGFloat handleX = (width / 2.0) - (kDragHandleWidth / 2.0);
            handle.frame = CGRectMake(handleX, kDragHandleTopOffset, kDragHandleWidth, kDragHandleHeight);
        }
    }
}

#pragma mark - Corner Radius

- (void)updateCornerRadiusMask {
    CAShapeLayer *maskLayer = (CAShapeLayer *)self.view.layer.mask;
    if (!maskLayer) {
        maskLayer = [[CAShapeLayer alloc] init];
        self.view.layer.mask = maskLayer;
    }
    
    CGRect viewBounds = self.view.bounds;
    UIRectCorner cornersToRound;
    
    if (isRunningOniPad() || _usePopupPresentation) {
        cornersToRound = UIRectCornerAllCorners;
    } else {
        cornersToRound = getCornersToRoundForPosition(_cardVerticalPosition, NO);
    }
    
    CAShapeLayer *newMaskLayer = createCornerRadiusMask(viewBounds, cornersToRound, kCornerRadiusDefault);
    maskLayer.frame = viewBounds;
    maskLayer.path = newMaskLayer.path;
}

#pragma mark - Orientation Support

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (self.enforcePortrait && !isRunningOniPad()) {
        return UIInterfaceOrientationMaskPortrait;
    }
    
    if (isRunningOniPad()) {
        return UIInterfaceOrientationMaskAll;
    }
    
    if (_usePopupPresentation) {
        return UIInterfaceOrientationMaskAll;
    }
    
    UIInterfaceOrientation currentOrientation = [[UIApplication sharedApplication] statusBarOrientation];
    return (1 << currentOrientation);
}

- (BOOL)shouldAutorotate {
    if (isRunningOniPad()) {
        return YES;
    }
    return _usePopupPresentation;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if (self.enforcePortrait && !isRunningOniPad()) {
        return UIInterfaceOrientationPortrait;
    }
    return [[UIApplication sharedApplication] statusBarOrientation];
}

#pragma mark - iPad Size Calculation

+ (CGSize)calculateiPadCardSizeForScreenBounds:(CGRect)screenBounds
                               tabletWidthRatio:(CGFloat)tabletWidthRatio
                              tabletHeightRatio:(CGFloat)tabletHeightRatio {
    if (screenBounds.size.width <= 0 || screenBounds.size.height <= 0) {
        return CGSizeMake(600, 700);
    }
    
    CGFloat screenWidth = screenBounds.size.width;
    CGFloat screenHeight = screenBounds.size.height;
    
    CGFloat cardWidth = screenWidth * tabletWidthRatio;
    CGFloat cardHeight = screenHeight * tabletHeightRatio;
    
    if (cardWidth <= 0 || cardHeight <= 0) {
        return CGSizeMake(600, 700);
    }
    
    // Enforce minimum sizes
    if (cardWidth < kMinTabletCardWidth) {
        cardWidth = kMinTabletCardWidth;
    }
    if (cardHeight < kMinTabletCardHeight) {
        cardHeight = kMinTabletCardHeight;
    }
    
    return CGSizeMake(cardWidth, cardHeight);
}

@end
