//
//  StashPayCardViewController.h
//  StashPay
//
//  View controller for card presentation with orientation control.
//

#import <UIKit/UIKit.h>
#import "StashPayCardConstants.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - DragTrayView

/**
 * Custom view that only intercepts touches in the drag handle area.
 * This allows the WebView beneath to receive touches outside the handle.
 */
@interface StashPayDragTrayView : UIView
@end

#pragma mark - OrientationLockedViewController

/**
 * View controller that manages card presentation and orientation locking.
 * - On iPhone: Enforces portrait orientation for card mode
 * - On iPad: Allows all orientations
 * - Handles layout updates during rotation and gestures
 */
@interface StashPayCardViewController : UIViewController

/**
 * The current frame of the card view.
 * Updated during animations and gestures.
 */
@property (nonatomic, assign) CGRect customFrame;

/**
 * Whether to enforce portrait orientation (iPhone only).
 */
@property (nonatomic, assign) BOOL enforcePortrait;

/**
 * Skip layout recalculation during initial setup or animations.
 * Set to YES during animations to prevent interference.
 */
@property (nonatomic, assign) BOOL skipLayoutDuringInitialSetup;

/**
 * Current state of the card (collapsed, expanded, dismissing, dismissed).
 */
@property (nonatomic, assign) StashPayCardState cardState;

/**
 * Updates the corner radius mask based on current card position.
 */
- (void)updateCornerRadiusMask;

/**
 * Calculates the appropriate size for iPad card presentation.
 * @param screenBounds The current screen bounds
 * @return The calculated card size
 */
+ (CGSize)calculateiPadCardSizeForScreenBounds:(CGRect)screenBounds
                               tabletWidthRatio:(CGFloat)tabletWidthRatio
                              tabletHeightRatio:(CGFloat)tabletHeightRatio;

@end

NS_ASSUME_NONNULL_END
