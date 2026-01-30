//
//  StashPayCardGestureHandler.m
//  StashPay
//
//  Gesture handling for card drag interactions.
//

#import "StashPayCardGestureHandler.h"
#import "StashPayCardViewController.h"

// Forward declaration
extern BOOL isRunningOniPad(void);

@implementation StashPayCardGestureHandler

- (instancetype)init {
    self = [super init];
    if (self) {
        _cardState = StashPayCardStateCollapsed;
        _isInteractionBlocked = NO;
        _initialY = 0;
    }
    return self;
}

#pragma mark - Drag Tray Creation

- (UIView *)createDragTrayWithWidth:(CGFloat)width isTablet:(BOOL)isTablet {
    StashPayDragTrayView *dragTrayView = [[StashPayDragTrayView alloc] init];
    dragTrayView.frame = CGRectMake(0, 0, width, kDragTrayHeight);
    dragTrayView.tag = kDragTrayViewTag;
    dragTrayView.backgroundColor = [UIColor clearColor];
    
    // Add handle view - simple bar matching Android style (no gradient, no shadow)
    UIView *handleView = [[UIView alloc] init];
    handleView.backgroundColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    handleView.layer.cornerRadius = kDragHandleCornerRadius;
    handleView.tag = kDragHandleViewTag;
    
    CGFloat handleX = (width / 2.0) - (kDragHandleWidth / 2.0);
    handleView.frame = CGRectMake(handleX, kDragHandleTopOffset, kDragHandleWidth, kDragHandleHeight);
    handleView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    
    [dragTrayView addSubview:handleView];
    
    return dragTrayView;
}

- (void)attachGestureRecognizer:(UIView *)dragTray {
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] 
                                          initWithTarget:self 
                                          action:@selector(handlePanGesture:)];
    panGesture.delegate = self;
    [dragTray addGestureRecognizer:panGesture];
    self.dragTrayView = dragTray;
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer 
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([gestureRecognizer.view isEqual:self.dragTrayView] || 
        [otherGestureRecognizer.view isEqual:self.dragTrayView]) {
        return NO;
    }
    return YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    // iPad: Block upward drags (dismiss only mode)
    if (isRunningOniPad() && [gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        UIPanGestureRecognizer *panGesture = (UIPanGestureRecognizer *)gestureRecognizer;
        if ([panGesture.view isEqual:self.dragTrayView]) {
            UIView *referenceView = self.cardWindow ?: panGesture.view.superview;
            CGPoint translation = [panGesture translationInView:referenceView];
            CGPoint velocity = [panGesture velocityInView:referenceView];
            
            // Block upward drags on iPad
            if (translation.y < 0 || velocity.y < 0) {
                return NO;
            }
        }
    }
    return YES;
}

#pragma mark - Pan Gesture Handling

- (void)handlePanGesture:(UIPanGestureRecognizer *)gesture {
    if (self.isInteractionBlocked) return;
    
    UIView *cardView = gesture.view.superview;
    if (!cardView) return;
    
    UIView *referenceView = self.cardWindow ?: cardView.superview;
    CGPoint translation = [gesture translationInView:referenceView];
    CGPoint velocity = [gesture velocityInView:referenceView];
    
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            [self handleGestureBegan:gesture cardView:cardView];
            break;
            
        case UIGestureRecognizerStateChanged:
            [self handleGestureChanged:gesture cardView:cardView translation:translation velocity:velocity];
            break;
            
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
            [self handleGestureEnded:gesture cardView:cardView translation:translation velocity:velocity];
            break;
            
        default:
            break;
    }
}

- (void)handleGestureBegan:(UIPanGestureRecognizer *)gesture cardView:(UIView *)cardView {
    UIView *referenceView = self.cardWindow ?: cardView.superview;
    CGPoint translation = [gesture translationInView:referenceView];
    
    // iPad: Block upward drags
    if (isRunningOniPad() && translation.y < 0) {
        gesture.enabled = NO;
        gesture.enabled = YES;
        return;
    }
    
    self.initialY = cardView.frame.origin.y;
    
    [self.delegate gestureHandler:self didBeginDragOnCardView:cardView];
}

- (void)handleGestureChanged:(UIPanGestureRecognizer *)gesture 
                    cardView:(UIView *)cardView 
                 translation:(CGPoint)translation
                    velocity:(CGPoint)velocity {
    [self.delegate gestureHandler:self 
                    didDragCardView:cardView 
                        translation:translation 
                           velocity:velocity];
}

- (void)handleGestureEnded:(UIPanGestureRecognizer *)gesture 
                  cardView:(UIView *)cardView 
               translation:(CGPoint)translation
                  velocity:(CGPoint)velocity {
    CGFloat currentTravel = translation.y;
    CGFloat height = cardView.frame.size.height;
    
    BOOL shouldExpand = NO;
    BOOL shouldCollapse = NO;
    BOOL shouldDismiss = NO;
    
    if (isRunningOniPad()) {
        // iPad: Dismiss only (no expand/collapse)
        [self evaluateiPadGesture:cardView 
                     currentTravel:currentTravel 
                          velocity:velocity 
                    shouldDismiss:&shouldDismiss];
    } else {
        // iPhone: Three-state system with velocity support
        [self evaluateiPhoneGesture:currentTravel 
                              height:height 
                            velocity:velocity 
                        shouldExpand:&shouldExpand 
                      shouldCollapse:&shouldCollapse 
                       shouldDismiss:&shouldDismiss];
    }
    
    // Execute the appropriate action
    if (shouldExpand) {
        [self.delegate gestureHandler:self shouldExpandCardView:cardView velocity:velocity.y];
    } else if (shouldCollapse) {
        [self.delegate gestureHandler:self shouldCollapseCardView:cardView velocity:velocity.y];
    } else if (shouldDismiss) {
        [self.delegate gestureHandler:self shouldDismissCardView:cardView velocity:velocity.y];
    } else {
        [self.delegate gestureHandler:self shouldSnapBackCardView:cardView velocity:velocity.y];
    }
}

#pragma mark - Gesture Evaluation

- (void)evaluateiPadGesture:(UIView *)cardView
               currentTravel:(CGFloat)currentTravel
                    velocity:(CGPoint)velocity
              shouldDismiss:(BOOL *)shouldDismiss {
    if (currentTravel <= 0) {
        *shouldDismiss = NO;
        return;
    }
    
    CGFloat height = cardView.frame.size.height;
    CGFloat currentY = cardView.frame.origin.y;
    CGFloat screenHeight = self.cardWindow ? self.cardWindow.bounds.size.height : cardView.superview.bounds.size.height;
    CGFloat cardBottom = currentY + height;
    CGFloat distanceToBottom = screenHeight - cardBottom;
    
    // Dismiss if close to bottom OR velocity threshold met with sufficient travel
    if (distanceToBottom < 10.0 || 
        (velocity.y > kDismissVelocityThresholdiPad && currentTravel > height * kDismissDistanceThresholdiPad)) {
        *shouldDismiss = YES;
    } else {
        *shouldDismiss = NO;
    }
}

- (void)evaluateiPhoneGesture:(CGFloat)currentTravel
                        height:(CGFloat)height
                      velocity:(CGPoint)velocity
                  shouldExpand:(BOOL *)shouldExpand
                shouldCollapse:(BOOL *)shouldCollapse
                 shouldDismiss:(BOOL *)shouldDismiss {
    
    CGFloat expandThreshold = height * kExpandDistanceThreshold;
    CGFloat collapseThreshold = height * kCollapseDistanceThreshold;
    CGFloat dismissThreshold = height * kDismissDistanceThreshold;
    
    // Upward drag: Check for expand
    if (currentTravel < -expandThreshold || velocity.y < kExpandVelocityThreshold) {
        if (self.cardState != StashPayCardStateExpanded) {
            *shouldExpand = YES;
            return;
        }
    }
    
    // Downward drag
    if (currentTravel > 0) {
        if (self.cardState == StashPayCardStateExpanded) {
            // From expanded: Check for dismiss or collapse
            if (currentTravel > dismissThreshold && velocity.y > kDismissVelocityThreshold) {
                *shouldDismiss = YES;
            } else if (currentTravel > collapseThreshold || velocity.y > kCollapseVelocityThreshold) {
                *shouldCollapse = YES;
            }
        } else {
            // From collapsed: Check for dismiss
            if (currentTravel > dismissThreshold || velocity.y > kDismissVelocityThreshold) {
                *shouldDismiss = YES;
            }
        }
    }
}

@end
