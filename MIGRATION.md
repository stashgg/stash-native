# StashPay SDK Migration Guide

This guide covers breaking changes and migration steps for the production-ready cleanup of the StashPay SDK.

## Overview

The SDK has been restructured for production readiness with:
- Consistent cross-platform behavior (iOS and Android)
- Improved architecture with modular components
- Memory optimizations
- Unified gesture and animation systems
- Enhanced sample applications

## Breaking Changes

### iOS

#### 1. Default Card Height Ratio Changed

The default card height ratio has been aligned with Android:

```swift
// Before
StashPayCard.sharedInstance().cardHeightRatio // Default: 0.60

// After
StashPayCard.sharedInstance().cardHeightRatio // Default: 0.68
```

**Migration**: If you relied on the previous default, explicitly set it:

```swift
StashPayCard.sharedInstance().cardHeightRatio = 0.60
```

#### 2. Internal Architecture Changes

The internal implementation has been split into modular components:
- `StashPayCardConstants.h` - Shared constants
- `StashPayCardViewController` - View controller management
- `StashPayCardAnimator` - Animation utilities
- `StashPayCardGestureHandler` - Gesture handling
- `StashPayWebViewManager` - WebView configuration

**No public API changes** - these are internal improvements.

#### 3. Gesture Behavior Changes

Gesture thresholds are now percentage-based relative to card height for consistent behavior at any size:
- Expand threshold: 15% of card height
- Collapse threshold: 25% of card height
- Dismiss threshold: 40% of screen height

Velocity thresholds are now used in addition to distance:
- Expand velocity: -300 pts/sec (upward)
- Collapse velocity: 300 pts/sec
- Dismiss velocity: 500 pts/sec

**Migration**: Test your app to ensure gestures feel correct. No code changes required.

### Android

#### 1. CardState Enum Added

A new `CardState` enum replaces boolean flags for clearer state management:

```java
public enum CardState {
    COLLAPSED,  // Default state
    EXPANDED,   // Full screen
    DISMISSING, // Being dismissed
    DISMISSED   // Fully removed
}
```

**No public API changes** - this is internal.

#### 2. Memory Optimizations

Activity references now use `WeakReference` to prevent memory leaks:

```java
// StashPayCardPlugin now uses:
private WeakReference<Activity> activityRef;
```

**Important**: Always call `setActivity(this)` in `onResume()`:

```java
@Override
protected void onResume() {
    super.onResume();
    StashPayCard.getInstance().setActivity(this);
}
```

#### 3. Gesture Thresholds Aligned

Android now uses the same threshold constants as iOS for consistent feel:
- `CardConstants.DISMISS_DISTANCE_THRESHOLD_PHONE = 0.25f` (25% of screen height)
- `CardConstants.DISMISS_DISTANCE_THRESHOLD_TABLET = 0.15f` (15% of screen height)
- `CardConstants.DISMISS_VELOCITY_THRESHOLD = 500f` (pixels/second)

**Migration**: Test your app to ensure gestures feel correct.

## New Features

### Both Platforms

#### 1. Orientation-Specific Sizing (NEW)

Configure different card sizes for portrait and landscape orientations:

**iOS:**
```swift
let stashPay = StashPayCard.sharedInstance()

// Phone sizing
stashPay.cardHeightRatioPortrait = 0.68   // 68% in portrait (default)
stashPay.cardHeightRatioLandscape = 0.5   // 50% in landscape (default)
stashPay.cardWidthRatioPortrait = 1.0     // Full width in portrait
stashPay.cardWidthRatioLandscape = 0.8    // 80% in landscape

// Tablet sizing
stashPay.tabletWidthRatioPortrait = 0.4   // 40% in portrait (default)
stashPay.tabletHeightRatioPortrait = 0.5  // 50% in portrait (default)
stashPay.tabletWidthRatioLandscape = 0.3  // 30% in landscape (default)
stashPay.tabletHeightRatioLandscape = 0.6 // 60% in landscape (default)
```

**Android:**
```java
StashPayCard stashPay = StashPayCard.getInstance();

// Phone sizing
stashPay.setCardHeightRatioPortrait(0.68f);
stashPay.setCardHeightRatioLandscape(0.5f);
stashPay.setCardWidthRatioPortrait(1.0f);
stashPay.setCardWidthRatioLandscape(0.8f);

// Tablet sizing
stashPay.setTabletWidthRatioPortrait(0.4f);
stashPay.setTabletHeightRatioPortrait(0.5f);
stashPay.setTabletWidthRatioLandscape(0.3f);
stashPay.setTabletHeightRatioLandscape(0.6f);
```

The checkout dialog will automatically resize when the device is rotated, providing optimal sizing for each orientation.

**Note**: The legacy single-ratio properties (`cardHeightRatio`, `tabletWidthRatio`, etc.) are still available for backward compatibility but setting the portrait-specific properties is recommended.

#### 2. Tablet-Specific Behavior

Tablets now have dismiss-only gestures (no expand/collapse):
- Drag down to dismiss
- Centered modal presentation
- No forced orientation

#### 3. Velocity-Based Gestures

Both platforms now support velocity-based gesture recognition:
- Quick swipes are recognized even with small distances
- Slow drags require larger distances
- Consistent feel across platforms

#### 4. Enhanced Animation Parameters

Animation parameters are now aligned:
- Spring damping: 0.85 (default), 0.9 (tight)
- Expand duration: 400ms
- Collapse duration: 380ms
- Dismiss duration: 250ms
- Entry duration: 300ms (slide), 200ms (fade)

### iOS

#### Memory Warning Handling

The SDK now responds to memory warnings by cleaning up pre-warmed resources when not actively presenting.

### Android

#### Smart Pre-warming

WebView pre-warming now checks available memory:
- Only pre-warms on devices with >2GB available RAM
- Releases pooled WebView on memory pressure

## Sample Applications

Both sample applications have been redesigned:

### Two-Mode Interface
- **Simple Mode**: URL input, mode toggle, open checkout button
- **Advanced Mode**: Collapsible section with size configuration sliders

### New Features
- Landscape lock toggle for testing
- State preservation across rotation
- Accessibility labels on all controls
- Scrollable layout for small screens

## Best Practices

### Activity Lifecycle (Android)

Always update the activity reference on resume:

```java
@Override
protected void onResume() {
    super.onResume();
    StashPayCard.getInstance().setActivity(this);
}
```

### Configuration Changes (Android)

Add to your Activity in AndroidManifest.xml to prevent recreation:

```xml
<activity
    android:name=".YourActivity"
    android:configChanges="orientation|screenSize|keyboardHidden">
```

### Testing Checklist

- [ ] Test checkout opening on phones (portrait and landscape)
- [ ] Test checkout opening on tablets (all orientations)
- [ ] Test expand/collapse gestures on phones
- [ ] Test dismiss gestures on both device types
- [ ] Test keyboard appearance and input
- [ ] Verify memory usage is stable
- [ ] Test on low-end devices (Android)

## Support

For migration assistance, contact developers@stash.gg.
