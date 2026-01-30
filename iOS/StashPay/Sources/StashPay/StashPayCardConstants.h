//
//  StashPayCardConstants.h
//  StashPay
//
//  Shared constants for card presentation, animations, and gestures.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#pragma mark - Feature Flags

#define ENABLE_IPAD_SUPPORT 1

#pragma mark - Animation Constants

// Spring animation parameters (aligned across iOS and Android)
static const CGFloat kSpringDampingDefault = 0.85f;
static const CGFloat kSpringDampingTight = 0.9f;
static const CGFloat kSpringVelocityDefault = 0.5f;

// Animation durations (in seconds)
static const CGFloat kAnimationDurationDefault = 0.4f;
static const CGFloat kAnimationDurationFast = 0.25f;
static const CGFloat kAnimationDurationEntry = 0.3f;
static const CGFloat kAnimationDurationPopup = 0.18f;
static const CGFloat kAnimationDurationExpand = 0.4f;
static const CGFloat kAnimationDurationCollapse = 0.38f;
static const CGFloat kAnimationDurationDismiss = 0.25f;

// iPhone slide-up animation
static const CGFloat kAnimationDurationSlideUp = 0.45f;
static const CGFloat kAnimationDelaySlideUp = 0.05f;
static const CGFloat kSpringDampingSlideUp = 0.88f;
static const CGFloat kSpringVelocitySlideUp = 0.2f;

#pragma mark - Visual Constants

// Corner radius
static const CGFloat kCornerRadiusDefault = 20.0f;
static const CGFloat kCornerRadiusExpanded = 24.0f;

// Drag tray dimensions
static const CGFloat kDragTrayHeight = 44.0f;
static const CGFloat kDragHandleWidth = 36.0f;
static const CGFloat kDragHandleHeight = 5.0f;
static const CGFloat kDragHandleCornerRadius = 3.0f;
static const CGFloat kDragHandleTopOffset = 8.0f;

// Overlay opacity
static const CGFloat kOverlayOpacityiPhone = 0.35f;
static const CGFloat kOverlayOpacityiPad = 0.25f;

#pragma mark - Gesture Thresholds (Velocity-based, aligned across platforms)

// Velocity thresholds (points per second)
static const CGFloat kExpandVelocityThreshold = -300.0f;    // Upward swipe to expand
static const CGFloat kCollapseVelocityThreshold = 300.0f;   // Downward swipe to collapse (when expanded)
static const CGFloat kDismissVelocityThreshold = 500.0f;    // Downward swipe to dismiss (when collapsed)
static const CGFloat kDismissVelocityThresholdiPad = 1040.0f; // iPad dismiss velocity threshold

// Distance thresholds (relative to card height)
static const CGFloat kExpandDistanceThreshold = 0.15f;      // 15% of height
static const CGFloat kCollapseDistanceThreshold = 0.25f;    // 25% of height
static const CGFloat kDismissDistanceThreshold = 0.40f;     // 40% of height (iOS native feel)
static const CGFloat kDismissDistanceThresholdiPad = 0.325f; // 32.5% for iPad

#pragma mark - Default Size Ratios

// iPhone card defaults
static const CGFloat kDefaultCardHeightRatio = 0.6f;
static const CGFloat kDefaultCardWidthRatio = 1.0f;
static const CGFloat kDefaultCardVerticalPosition = 1.0f;

// iPad card defaults
static const CGFloat kDefaultTabletWidthRatio = 0.8f;
static const CGFloat kDefaultTabletHeightRatio = 0.75f;

// Minimum sizes for iPad (in points)
static const CGFloat kMinTabletCardWidth = 400.0f;
static const CGFloat kMinTabletCardHeight = 500.0f;

// Popup size multipliers (defaults)
static const CGFloat kDefaultPopupPortraitWidthMultiplier = 1.0285f;
static const CGFloat kDefaultPopupPortraitHeightMultiplier = 1.485f;
static const CGFloat kDefaultPopupLandscapeWidthMultiplier = 1.2275445f;
static const CGFloat kDefaultPopupLandscapeHeightMultiplier = 1.1385f;

#pragma mark - View Tags

static const NSInteger kDragTrayViewTag = 8888;
static const NSInteger kDragHandleViewTag = 8889;

#pragma mark - Card State

typedef NS_ENUM(NSInteger, StashPayCardState) {
    StashPayCardStateCollapsed = 0,
    StashPayCardStateExpanded = 1,
    StashPayCardStateDismissing = 2,
    StashPayCardStateDismissed = 3
};
