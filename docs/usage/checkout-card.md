---
title: Checkout card
parent: Usage reference
nav_order: 2
description: Open Stash Pay checkout in the responsive native card. Configuration, sizing, orientation, and the Android portrait backdrop.
---

# Checkout card

`openCard` loads a checkout URL in a WebView inside a native card and reports payment events through the delegate or listener. It is the only presentation that injects the [`window.stash_sdk` bridge](../stash-sdk-js.md).

![Checkout card in dark mode on iPhone, unfolded iPhone Duo, and iPad](https://raw.githubusercontent.com/stashgg/stash-native/main/.github/assets/opencard-devices-dark.png)

## Open a card

Swift:

```swift
let stash = StashNativeCard.sharedInstance()
stash.delegate = self
stash.openCard(withURL: checkoutURL, from: self, config: nil)
```

Objective-C:

```objc
StashNativeCard *stash = [StashNativeCard sharedInstance];
stash.delegate = self;
[stash openCardWithURL:checkoutURL fromViewController:self config:nil];
```

Java:

```java
StashNativeCard stash = StashNativeCard.getInstance();
stash.setListener(listener);
stash.openCard(activity, checkoutUrl, null);
```

`nil` or `null` uses the default config. The call is ignored when another presentation is active, the URL is not `http` or `https`, the iOS presenter is not in a window, or the Android activity is finishing or destroyed. See [call rules](index.md#call-rules).

## Configuration

`StashNativeCardConfig` on iOS, `StashNativeCard.CardConfig` on Android. Dimensions are logical units: points on iOS, dp on Android. They describe web content and exclude safe areas and native chrome.

| Property | Type | Default | Accepted values | Meaning |
|---|---|---|---|---|
| `preferredContentWidth` | `CGFloat` / `float` | `400` | Finite, greater than 0 | Card width when the usable region is at least 600 wide. Narrower regions use their full width. |
| `preferredContentHeight` | `CGFloat` / `float` | `560` | Finite, greater than 0 | Resting height ceiling, and the resting height when the page reports no content height |
| `maximumContentHeight` | `CGFloat` / `float` | `720` | Finite, 0 or greater | Expanded height cap. `0` allows all available height. |
| `edgeMargin` | `CGFloat` / `float` | `16` | Finite, 0 or greater | Margin around the card, limited to a quarter of the region's smaller side |
| `allowDismiss` | `BOOL` / `boolean` | `true` | | Allows user dismissal: swipe or handle drag, backdrop tap, Android Back, VoiceOver escape |
| `autoClose` | `BOOL` / `boolean` | `true` | | Closes the card after a payment success or failure signal |
| `orientationPreference` | `StashNativeOrientationPreference` / `int` | Follow host | Follow host, portrait | Requests portrait checkout on phones. See [Orientation](#orientation). |

Values outside the accepted range fall back to the default. Available space always wins over requested dimensions.

`allowDismiss = false` blocks only user gestures. The page's `window.close()`, payment callbacks with `autoClose`, and native `dismiss()` still close the card.

`autoClose = false` keeps the card open after payment signals. Every success or failure signal is then delivered, and the card closes later through the page, the user, or `dismiss()`, which reports a dismissal.

Swift:

```swift
let config = StashNativeCardConfig()
config.maximumContentHeight = 0
config.allowDismiss = false
config.orientationPreference = .portrait
stash.openCard(withURL: checkoutURL, from: self, config: config)
```

Java:

```java
StashNativeCard.CardConfig config = new StashNativeCard.CardConfig();
config.maximumContentHeight = 0;
config.allowDismiss = false;
config.orientationPreference = StashNativeCard.CardConfig.ORIENTATION_PORTRAIT;
stash.openCard(activity, checkoutUrl, config);
```

The defaults are tuned for Stash Pay. Change them only for a specific layout requirement.

## Sizing and states

The card has two states: resting and expanded. Heights come from the current window:

- Expanded: available height minus margins, capped by `maximumContentHeight` when it is greater than 0.
- Resting: `min(preferredContentHeight, expanded height, measured content height)`.
- Usable regions narrower than 600 get a full-width, bottom-attached card. Wider regions get a card `preferredContentWidth` wide.

The selected state survives rotation, resizing, folding, and keyboard changes. The keyboard expands the card temporarily. The page selects a state with `stash_sdk.expand()` and `stash_sdk.collapse()`, and can report its content height so the resting card fits the content. Full rules: [Presentation sizing](../architecture/index.md#presentation-sizing). Page-side contract: [Content sizing](../stash-sdk-js.md#content-sizing).

| Platform | User controls |
|---|---|
| iOS | Upward drag on content expands a resting compact card (iOS 16+). The grabber resizes and dismisses. Content drags never dismiss. |
| Android | The handle toggles on tap, resizes on drag, and dismisses on a downward drag. Upward drag on content expands a resting bottom card. |

## Orientation

`orientationPreference` defaults to follow host.

| Platform | Portrait behavior |
|---|---|
| iPhone | The card opens in an SDK-owned portrait `UIWindow`, also for landscape-only games. The SDK scopes orientation overrides to that window, restores the previous orientation on close, and then returns the key window. The game's view controller orientation settings are not changed. |
| iPad | Preference ignored |
| Android phone | The checkout activity requests portrait in compact fullscreen windows (`smallestScreenWidthDp < 600`, not multi-window) |
| Android tablet, unfolded large screen, multi-window | Preference released. It is requested again when the window becomes compact fullscreen. |

Rotation is best effort. System windowing rules, foldable postures, and newer Android target SDK policies can refuse it. The card then lays out in the host's geometry. Platform details: [iOS portrait presentation](../architecture/ios.md#portrait-presentation).

## Android portrait backdrop

On Android, forcing portrait over a landscape game rotates the host activity behind the card. A screenshot backdrop hides that rotation.

```java
StashNativeCard.setBackdropBitmap(screenshot);      // or setBackdropBytes(pngOrJpegBytes)
config.orientationPreference = StashNativeCard.CardConfig.ORIENTATION_PORTRAIT;
StashNativeCard.getInstance().openCard(activity, checkoutUrl, config);
```

| Rule | Detail |
|---|---|
| Timing | Call immediately before `openCard`. |
| Ownership | The SDK takes the bitmap and recycles it. Do not reuse, mutate, or recycle it yourself. |
| Bytes | `setBackdropBytes` decodes PNG or JPEG, downsampled so the longest side is at most 2400 px. Null or invalid input clears the pending image. |
| Consumption | The next accepted card takes the image. Rejected opens, CodeLink, and `openBrowser` leave it pending. |
| Discarded | When the card follows the host, or portrait is not applied (tablet, multi-window) |
| Release | Replacing the image, `resetPresentationState()`, a failed launch, and activity teardown release it |
| Storage | Kept in memory in the host process. Never written to an `Intent` or saved state. |

The backdrop rotates and center-crops with the window. When a portrait card closes over a landscape host, the backdrop stays visible while the host rotates back, for at most 800 ms. `resetPresentationState()` closes immediately without waiting.

iOS has no backdrop API. Its SDK window keeps the game window untouched.

## Appearance

- The SDK adds `theme=light` or `theme=dark` to the checkout URL from the host's current appearance: the presenter's trait collection on iOS, the activity's night mode on Android. An existing `theme` parameter is replaced.
- Native surfaces follow the page background automatically. There is no color configuration.
- Android never applies algorithmic darkening to checkout content.

## Related

- [Callbacks and lifecycle](callbacks.md): payment, dismissal, page load, network error, external payment.
- [JavaScript bridge](../stash-sdk-js.md): page API and page layout contract.
