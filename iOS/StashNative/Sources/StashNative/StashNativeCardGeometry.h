//
//  StashNativeCardGeometry.h
//  StashNative
//
//  Sheet sizing/geometry math. Takes caller ratio config (stash_*Ratio / stash_custom*Multiplier
//  externs) and the live orientation/idiom, returns concrete frames. Implementations in
//  StashNativeCardGeometry.m.
//

#import <UIKit/UIKit.h>

/// iPad card size for the screen bounds (orientation-specific tablet ratios, min-clamped).
CGSize stash_calculateiPadCardSize(CGRect screenBounds);

/// Popup frame for the screen bounds; uses current orientation and custom/default multipliers.
CGRect stash_computePopupFrameForScreenBounds(CGRect screenBounds);

/// Modal frame for the screen bounds; uses current orientation and modal ratios.
CGRect stash_computeModalFrameForScreenBounds(CGRect screenBounds);

/// Phone card frame for the given bounds and orientation.
CGRect stash_computePhoneCardFrameForBoundsAndOrientation(CGRect bounds, BOOL isLandscape);

/// iPad SDK-card frame (centered, expand-aware) for the screen bounds.
CGRect stashFrameForIPadSdkCard(CGRect screenBounds, UIView *cardView);

/// Max tablet SDK-card height for the screen bounds (safe-area aware).
CGFloat stashTabletSdkMaxCardHeight(CGRect screenBounds, UIView *cardView);

/// Expanded tablet SDK-card height grown from a base height, clamped to the max.
CGFloat stashTabletSdkExpandedHeightFromBase(CGFloat baseHeight, CGRect screenBounds, UIView *cardView);

/// Top safe-area inset (notch / status bar) for a view, falling back to the active card safe-area.
CGFloat stash_getSafeAreaTopForView(UIView *view);

/// Bottom safe-area inset (home indicator) for a view.
CGFloat stash_getSafeAreaBottomForView(UIView *view);

/// Resets expand/collapse state to collapsed after rotation.
void stash_resetCardExpandedStateAfterRotation(void);
