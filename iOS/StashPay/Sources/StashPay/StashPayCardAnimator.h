//
//  StashPayCardAnimator.h
//  StashPay
//
//  Animation utilities for card presentation.
//

#import <UIKit/UIKit.h>
#import "StashPayCardConstants.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Provides animation utilities for card presentation.
 * All animations use spring physics aligned with Android for consistent UX.
 */
@interface StashPayCardAnimator : NSObject

#pragma mark - Card Expansion/Collapse

/**
 * Animates the card expansion progress.
 * @param progress Value from 0.0 (collapsed) to 1.0 (expanded)
 * @param cardView The card view to animate
 * @param screenBounds Current screen bounds
 * @param safeAreaTop Safe area top inset
 * @param collapsedHeight Original collapsed height
 * @param collapsedWidth Original collapsed width
 * @param isTablet Whether running on iPad
 */
+ (void)updateCardExpansionProgress:(CGFloat)progress
                           cardView:(UIView *)cardView
                       screenBounds:(CGRect)screenBounds
                        safeAreaTop:(CGFloat)safeAreaTop
                    collapsedHeight:(CGFloat)collapsedHeight
                     collapsedWidth:(CGFloat)collapsedWidth
                           isTablet:(BOOL)isTablet;

#pragma mark - Spring Animations

/**
 * Executes a spring animation with default parameters.
 * @param duration Animation duration
 * @param animations Animation block
 * @param completion Completion handler
 */
+ (void)animateWithSpring:(CGFloat)duration
               animations:(void (^)(void))animations
               completion:(nullable void (^)(BOOL finished))completion;

/**
 * Executes a spring animation with custom parameters.
 * @param duration Animation duration
 * @param damping Spring damping (0.0-1.0)
 * @param velocity Initial spring velocity
 * @param animations Animation block
 * @param completion Completion handler
 */
+ (void)animateWithSpring:(CGFloat)duration
                  damping:(CGFloat)damping
                 velocity:(CGFloat)velocity
               animations:(void (^)(void))animations
               completion:(nullable void (^)(BOOL finished))completion;

#pragma mark - Entry Animations

/**
 * Animates card sliding up from bottom (iPhone).
 * @param cardView The card view
 * @param finalFrame The final frame position
 * @param overlayView The dark overlay view
 * @param completion Completion handler
 */
+ (void)animateSlideUpEntry:(UIView *)cardView
                 finalFrame:(CGRect)finalFrame
                overlayView:(UIView *)overlayView
                 completion:(nullable void (^)(void))completion;

/**
 * Animates card fade-in (iPad/Popup).
 * @param cardView The card view
 * @param overlayView The dark overlay view
 * @param overlayOpacity Final overlay opacity
 * @param completion Completion handler
 */
+ (void)animateFadeInEntry:(UIView *)cardView
               overlayView:(UIView *)overlayView
            overlayOpacity:(CGFloat)overlayOpacity
                completion:(nullable void (^)(void))completion;

#pragma mark - Dismiss Animations

/**
 * Animates card sliding down to dismiss (iPhone).
 * @param cardView The card view
 * @param dismissY The Y position below screen
 * @param overlayView The dark overlay view
 * @param velocity Swipe velocity for responsive feel
 * @param completion Completion handler
 */
+ (void)animateSlideDownDismiss:(UIView *)cardView
                       dismissY:(CGFloat)dismissY
                    overlayView:(nullable UIView *)overlayView
                       velocity:(CGFloat)velocity
                     completion:(nullable void (^)(void))completion;

/**
 * Animates card fade-out to dismiss (iPad/Popup).
 * @param cardView The card view
 * @param overlayView The dark overlay view
 * @param completion Completion handler
 */
+ (void)animateFadeOutDismiss:(UIView *)cardView
                  overlayView:(nullable UIView *)overlayView
                   completion:(nullable void (^)(void))completion;

#pragma mark - Snap Back Animation

/**
 * Animates card snapping back to original position.
 * @param cardView The card view
 * @param originalFrame The original frame to snap back to
 * @param velocity Current gesture velocity
 * @param completion Completion handler
 */
+ (void)animateSnapBack:(UIView *)cardView
          originalFrame:(CGRect)originalFrame
               velocity:(CGFloat)velocity
             completion:(nullable void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
