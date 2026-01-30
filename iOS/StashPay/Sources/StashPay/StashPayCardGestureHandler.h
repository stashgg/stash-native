//
//  StashPayCardGestureHandler.h
//  StashPay
//
//  Gesture handling for card drag interactions.
//

#import <UIKit/UIKit.h>
#import "StashPayCardConstants.h"

NS_ASSUME_NONNULL_BEGIN

@protocol StashPayCardGestureHandlerDelegate;

/**
 * Handles drag gestures for card expand/collapse/dismiss.
 * - iPhone: Supports three states (collapsed → expanded → dismissed)
 * - iPad: Supports dismiss only (no expand/collapse)
 */
@interface StashPayCardGestureHandler : NSObject <UIGestureRecognizerDelegate>

/**
 * Delegate for gesture state changes.
 */
@property (nonatomic, weak, nullable) id<StashPayCardGestureHandlerDelegate> delegate;

/**
 * The window containing the card (for coordinate conversion).
 */
@property (nonatomic, weak, nullable) UIWindow *cardWindow;

/**
 * The drag tray view that receives gestures.
 */
@property (nonatomic, weak, nullable) UIView *dragTrayView;

/**
 * Current state of the card.
 */
@property (nonatomic, assign) StashPayCardState cardState;

/**
 * Whether gesture interaction is blocked (e.g., during purchase processing).
 */
@property (nonatomic, assign) BOOL isInteractionBlocked;

/**
 * Initial Y position when drag started.
 */
@property (nonatomic, assign) CGFloat initialY;

/**
 * Creates the drag tray view with handle.
 * @param width Width of the card
 * @param isTablet Whether running on iPad
 * @return Configured drag tray view
 */
- (UIView *)createDragTrayWithWidth:(CGFloat)width isTablet:(BOOL)isTablet;

/**
 * Attaches the pan gesture recognizer to the drag tray.
 * @param dragTray The drag tray view
 */
- (void)attachGestureRecognizer:(UIView *)dragTray;

@end

#pragma mark - Delegate Protocol

@protocol StashPayCardGestureHandlerDelegate <NSObject>

@required

/**
 * Called when drag gesture begins.
 * @param gestureHandler The gesture handler
 * @param cardView The card view being dragged
 */
- (void)gestureHandler:(StashPayCardGestureHandler *)gestureHandler
      didBeginDragOnCardView:(UIView *)cardView;

/**
 * Called during drag gesture with current translation.
 * @param gestureHandler The gesture handler
 * @param cardView The card view being dragged
 * @param translation Current translation
 * @param velocity Current velocity
 */
- (void)gestureHandler:(StashPayCardGestureHandler *)gestureHandler
     didDragCardView:(UIView *)cardView
         translation:(CGPoint)translation
            velocity:(CGPoint)velocity;

/**
 * Called when drag gesture ends.
 * @param gestureHandler The gesture handler
 * @param cardView The card view
 * @param translation Final translation
 * @param velocity Final velocity
 */
- (void)gestureHandler:(StashPayCardGestureHandler *)gestureHandler
      didEndDragOnCardView:(UIView *)cardView
               translation:(CGPoint)translation
                  velocity:(CGPoint)velocity;

/**
 * Called when card should expand to full screen.
 * @param gestureHandler The gesture handler
 * @param cardView The card view
 * @param velocity Gesture velocity for animation
 */
- (void)gestureHandler:(StashPayCardGestureHandler *)gestureHandler
   shouldExpandCardView:(UIView *)cardView
               velocity:(CGFloat)velocity;

/**
 * Called when card should collapse to original size.
 * @param gestureHandler The gesture handler
 * @param cardView The card view
 * @param velocity Gesture velocity for animation
 */
- (void)gestureHandler:(StashPayCardGestureHandler *)gestureHandler
  shouldCollapseCardView:(UIView *)cardView
                velocity:(CGFloat)velocity;

/**
 * Called when card should be dismissed.
 * @param gestureHandler The gesture handler
 * @param cardView The card view
 * @param velocity Gesture velocity for animation
 */
- (void)gestureHandler:(StashPayCardGestureHandler *)gestureHandler
   shouldDismissCardView:(UIView *)cardView
                velocity:(CGFloat)velocity;

/**
 * Called when card should snap back to current position.
 * @param gestureHandler The gesture handler
 * @param cardView The card view
 * @param velocity Gesture velocity for animation
 */
- (void)gestureHandler:(StashPayCardGestureHandler *)gestureHandler
  shouldSnapBackCardView:(UIView *)cardView
                velocity:(CGFloat)velocity;

@end

NS_ASSUME_NONNULL_END
