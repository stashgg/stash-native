//
//  StashPayCardAnimator.m
//  StashPay
//
//  Animation utilities for card presentation.
//

#import "StashPayCardAnimator.h"

// Forward declarations for helper functions
extern CAShapeLayer* createCornerRadiusMask(CGRect bounds, UIRectCorner corners, CGFloat radius);
extern BOOL isRunningOniPad(void);
extern CGFloat _cardVerticalPosition;

@implementation StashPayCardAnimator

#pragma mark - Card Expansion/Collapse

+ (void)updateCardExpansionProgress:(CGFloat)progress
                           cardView:(UIView *)cardView
                       screenBounds:(CGRect)screenBounds
                        safeAreaTop:(CGFloat)safeAreaTop
                    collapsedHeight:(CGFloat)collapsedHeight
                     collapsedWidth:(CGFloat)collapsedWidth
                           isTablet:(BOOL)isTablet {
    if (!cardView) return;
    
    progress = MAX(0.0, MIN(1.0, progress));
    
    CGFloat expandedWidth, expandedHeight, expandedX, expandedY;
    CGFloat collapsedX, collapsedY;
    
    if (isTablet) {
        // iPad: expand from 70% to 100% of configured size
        expandedWidth = collapsedWidth / 0.7;
        expandedHeight = collapsedHeight / 0.7;
        expandedX = (screenBounds.size.width - expandedWidth) / 2;
        expandedY = (screenBounds.size.height - expandedHeight) / 2;
        
        collapsedX = (screenBounds.size.width - collapsedWidth) / 2;
        collapsedY = (screenBounds.size.height - collapsedHeight) / 2;
    } else {
        // iPhone: expand to full screen minus safe area
        expandedWidth = screenBounds.size.width;
        expandedHeight = screenBounds.size.height - safeAreaTop;
        expandedX = 0;
        expandedY = safeAreaTop;
        
        collapsedX = (screenBounds.size.width - collapsedWidth) / 2;
        collapsedY = screenBounds.size.height - collapsedHeight;
        if (collapsedY < 0) collapsedY = 0;
    }
    
    // Interpolate frame
    CGFloat currentWidth = collapsedWidth + (expandedWidth - collapsedWidth) * progress;
    CGFloat currentHeight = collapsedHeight + (expandedHeight - collapsedHeight) * progress;
    CGFloat currentX = collapsedX + (expandedX - collapsedX) * progress;
    CGFloat currentY = collapsedY + (expandedY - collapsedY) * progress;
    
    cardView.frame = CGRectMake(currentX, currentY, currentWidth, currentHeight);
    
    // Update subviews
    [self updateSubviewsForCardView:cardView width:currentWidth];
    
    // Update corner mask based on progress
    [self updateCornerMaskForProgress:progress cardView:cardView isTablet:isTablet];
}

+ (void)updateSubviewsForCardView:(UIView *)cardView width:(CGFloat)width {
    // Update drag tray
    UIView *dragTray = [cardView viewWithTag:kDragTrayViewTag];
    if (dragTray) {
        dragTray.frame = CGRectMake(0, 0, width, kDragTrayHeight);
        
        // Update handle
        UIView *handle = [dragTray viewWithTag:kDragHandleViewTag];
        if (handle) {
            CGFloat handleX = (width / 2.0) - (kDragHandleWidth / 2.0);
            handle.frame = CGRectMake(handleX, kDragHandleTopOffset, kDragHandleWidth, kDragHandleHeight);
        }
    }
}

+ (void)updateCornerMaskForProgress:(CGFloat)progress cardView:(UIView *)cardView isTablet:(BOOL)isTablet {
    UIRectCorner corners;
    
    if (isTablet) {
        corners = UIRectCornerAllCorners;
    } else {
        if (progress > 0.9) {
            corners = UIRectCornerTopLeft | UIRectCornerTopRight;
        } else if (progress > 0.5) {
            corners = UIRectCornerTopLeft | UIRectCornerTopRight | UIRectCornerBottomLeft | UIRectCornerBottomRight;
        } else {
            corners = UIRectCornerTopLeft | UIRectCornerTopRight;
        }
    }
    
    CAShapeLayer *maskLayer = createCornerRadiusMask(cardView.bounds, corners, kCornerRadiusDefault);
    cardView.layer.mask = maskLayer;
}

#pragma mark - Spring Animations

+ (void)animateWithSpring:(CGFloat)duration
               animations:(void (^)(void))animations
               completion:(void (^)(BOOL))completion {
    [self animateWithSpring:duration
                    damping:kSpringDampingDefault
                   velocity:kSpringVelocityDefault
                 animations:animations
                 completion:completion];
}

+ (void)animateWithSpring:(CGFloat)duration
                  damping:(CGFloat)damping
                 velocity:(CGFloat)velocity
               animations:(void (^)(void))animations
               completion:(void (^)(BOOL))completion {
    [UIView animateWithDuration:duration
                          delay:0
         usingSpringWithDamping:damping
          initialSpringVelocity:velocity
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:animations
                     completion:completion];
}

#pragma mark - Entry Animations

+ (void)animateSlideUpEntry:(UIView *)cardView
                 finalFrame:(CGRect)finalFrame
                overlayView:(UIView *)overlayView
                 completion:(void (^)(void))completion {
    // First fade in overlay
    [UIView animateWithDuration:0.1 animations:^{
        overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:kOverlayOpacityiPhone];
    }];
    
    // Then slide up card with spring animation
    [UIView animateWithDuration:kAnimationDurationSlideUp
                          delay:kAnimationDelaySlideUp
         usingSpringWithDamping:kSpringDampingSlideUp
          initialSpringVelocity:kSpringVelocitySlideUp
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        cardView.frame = finalFrame;
        cardView.alpha = 1.0;
    } completion:^(BOOL finished) {
        if (completion) completion();
    }];
}

+ (void)animateFadeInEntry:(UIView *)cardView
               overlayView:(UIView *)overlayView
            overlayOpacity:(CGFloat)overlayOpacity
                completion:(void (^)(void))completion {
    [UIView animateWithDuration:kAnimationDurationDefault
                          delay:0
         usingSpringWithDamping:kSpringDampingDefault
          initialSpringVelocity:kSpringVelocityDefault
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        cardView.alpha = 1.0;
        cardView.transform = CGAffineTransformIdentity;
        overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:overlayOpacity];
    } completion:^(BOOL finished) {
        if (completion) completion();
    }];
}

#pragma mark - Dismiss Animations

+ (void)animateSlideDownDismiss:(UIView *)cardView
                       dismissY:(CGFloat)dismissY
                    overlayView:(UIView *)overlayView
                       velocity:(CGFloat)velocity
                     completion:(void (^)(void))completion {
    CGFloat duration = (velocity > 1000) ? 0.22 : kAnimationDurationDismiss;
    CGFloat springVelocity = velocity / 1000.0;
    
    [UIView animateWithDuration:duration
                          delay:0
         usingSpringWithDamping:kSpringDampingTight
          initialSpringVelocity:springVelocity
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        CGRect dismissFrame = cardView.frame;
        dismissFrame.origin.y = dismissY;
        cardView.frame = dismissFrame;
        
        if (overlayView) {
            overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.0];
        }
    } completion:^(BOOL finished) {
        if (completion) completion();
    }];
}

+ (void)animateFadeOutDismiss:(UIView *)cardView
                  overlayView:(UIView *)overlayView
                   completion:(void (^)(void))completion {
    [UIView animateWithDuration:kAnimationDurationPopup
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        cardView.alpha = 0.0;
        cardView.transform = CGAffineTransformMakeScale(0.9, 0.9);
        
        if (overlayView) {
            overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.0];
        }
    } completion:^(BOOL finished) {
        if (completion) completion();
    }];
}

#pragma mark - Snap Back Animation

+ (void)animateSnapBack:(UIView *)cardView
          originalFrame:(CGRect)originalFrame
               velocity:(CGFloat)velocity
             completion:(void (^)(void))completion {
    CGFloat springVelocity = fabs(velocity) / 1000.0;
    
    [UIView animateWithDuration:kAnimationDurationFast
                          delay:0
         usingSpringWithDamping:0.92
          initialSpringVelocity:springVelocity
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        cardView.frame = originalFrame;
    } completion:^(BOOL finished) {
        if (completion) completion();
    }];
}

@end
