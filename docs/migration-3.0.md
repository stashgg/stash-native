# Migrating from 2.x to 3.0

3.0 replaces device-specific presentation sizing and implicit host lookup. There are no compatibility aliases for the removed APIs. Update native callers before replacing the 2.x binary; existing Unity and Unreal wrappers must stay pinned to their tested native version until migrated separately.

## Minimum versions

- iOS 15 replaces iOS 13. Xcode 27.1 builds cannot target iOS 13 or 14.
- Android API 21 remains supported. Build with JDK 17; the SDK retains compile SDK 34.
- Build the iOS host with SDK 27.1 for full Duo display adaptation.

## Supply the presenting host

```swift
let stash = StashNativeCard.sharedInstance()
stash.openCard(withURL: checkoutURL, from: self, config: nil)
stash.openBrowser(withURL: checkoutURL, from: self)
```

```java
StashNativeCard stash = StashNativeCard.getInstance();
stash.openCard(activity, checkoutUrl, null);
stash.openBrowser(activity, checkoutUrl);
```

Pass the view controller or activity associated with the initiating app window. Android's ambient `setActivity` setup is removed. Calls belong on the platform UI thread; wrappers must marshal from engine threads.

## Replace sizing ratios

Remove every phone/tablet and portrait/landscape ratio. Start with automatic card defaults; logical dimension overrides are optional:

```swift
let card = StashNativeCardConfig()
card.preferredContentWidth = 400
card.preferredContentHeight = 560
card.maximumContentHeight = 720
card.edgeMargin = 16
stash.openCard(withURL: checkoutURL, from: self, config: card)
```

```java
StashNativeCard.CardConfig card = new StashNativeCard.CardConfig();
card.preferredContentWidth = 400;
card.preferredContentHeight = 560;
card.maximumContentHeight = 720;
card.edgeMargin = 16;
stash.openCard(activity, checkoutUrl, card);
```

Both platforms default to a 400-point/dp card width, a 560-point/dp resting height and a 720-point/dp expansion cap. Explicit `maximumContentHeight = 0` still permits all available height.

There is no ratio-to-dimension conversion that preserves every former device layout. Start with defaults and test the current window sizes your app supports. See [responsive presentation](responsive-presentation.md) for each property's meaning.

`openModal`, modal configuration, `openPopup`, and popup multiplier configuration are removed. Use `openCard` for embedded checkout or `openBrowser` for browser presentation. There is no modal compatibility alias. `backgroundColor` is also removed from SDK and sample configuration; native backgrounds match the page and theme automatically. iOS exposes `StashNativeCardConfig` directly, without a public presentation-config base class.

## Orientation

Replace `forcePortrait` with the card's `orientationPreference`. The default follows the host window. The portrait preference requests portrait only where the host and OS allow it. It does not force a foldable or multitasking window into a portrait-shaped viewport.

Remove SDK orientation swizzles, orientation-unlock integration, and screenshot-backdrop workarounds. The presentation now follows its host rather than creating a separate orientation-locked overlay window.

## Checkout pages and callbacks

Existing payment, processing, external-link, and close messages retain their meanings. Keep backend payment verification; UI callbacks alone are not purchase fulfilment evidence.

`expand()` and `collapse()` operate on card states across window sizes. Optional `setContentHeight(...)` and `[data-stash-content]` enable card content sizing; they are never required for a page to render.

On iOS, checkout now paints through the bottom safe area. The SDK supplies `viewport-fit=cover` and insets scroll indicators; pages own `env(safe-area-inset-bottom)` padding for scrolling content and fixed or sticky bottom controls. The SDK adds no native content inset or automatic page padding. Put the intrinsic content marker inside any outer safe-area padding, and exclude that padding from explicit height reports. See [responsive presentation](responsive-presentation.md) for the hosting contract.

## Android dependencies

Standalone AAR consumers must add the dependencies listed in the root README, including WindowManager 1.4.0 and its Java adapter. A plain AAR does not carry transitive dependency metadata. Do not substitute WindowManager 1.5.x while promising API 21: that line raises its minimum to API 23.

## Integration checks

Test the same active checkout while rotating, resizing, folding, typing, and returning from an external browser. Verify form and scroll state, processing locks, once-only result callbacks, and dismissal. Run on the minimum OS as well as newer OS versions; newer simulators do not prove minimum-version support.
