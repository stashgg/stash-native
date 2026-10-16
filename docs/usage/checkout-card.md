---
title: Checkout card
parent: Usage
nav_order: 2
description: Open Stash Pay checkout in the native card, configure its size and dismissal, and request portrait.
---

# Checkout card

![Checkout card on iPhone, unfolded iPhone Duo, and iPad](https://raw.githubusercontent.com/stashgg/stash-native/main/.github/assets/opencard-devices-dark.png)

## Open

Loads a checkout URL in a native card and reports payment events through your [callbacks](callbacks.md). The SDK appends `theme=light` or `theme=dark` to the URL from the app's appearance.

```swift
StashNativeCard.sharedInstance().openCard(withURL: checkoutURL, from: self, config: nil)
```

```java
StashNativeCard.getInstance().openCard(activity, checkoutUrl, null);
```

## Configuration

A `nil` or `null` config uses these defaults. Sizes are points on iOS and dp on Android. The card never exceeds the available space, and invalid values fall back to the defaults.

| Property | Default | Effect |
|---|---|---|
| `preferredContentWidth` | `400` | Card width in windows at least 600 wide. Narrower windows use the full width. |
| `preferredContentHeight` | `560` | Maximum resting height |
| `maximumContentHeight` | `720` | Maximum expanded height. `0` allows all available height. |
| `edgeMargin` | `16` | Space around the card |
| `allowDismiss` | `true` | Swipe, backdrop tap, and Android Back close the card |
| `autoClose` | `true` | A payment result closes the card |
| `orientationPreference` | Follow host | Portrait checkout on phones |

```swift
let config = StashNativeCardConfig()
config.allowDismiss = false
config.maximumContentHeight = 0
StashNativeCard.sharedInstance().openCard(withURL: checkoutURL, from: self, config: config)
```

```java
StashNativeCard.CardConfig config = new StashNativeCard.CardConfig();
config.allowDismiss = false;
config.maximumContentHeight = 0;
StashNativeCard.getInstance().openCard(activity, checkoutUrl, config);
```

`allowDismiss = false` blocks only user gestures. `window.close()` from the page and native `dismiss()` still close the card. With `autoClose = false`, every payment signal reaches your callbacks and the card stays open.

## States

Resting height is `preferredContentHeight`, or less when the page reports shorter content. Expanded height is the available height, up to `maximumContentHeight`. The page switches states with `stash_sdk.expand()` and `collapse()`. The keyboard expands the card until it closes. Rotation and resizing keep the state, the page, and form input.

## Portrait

Shows checkout in portrait over a landscape game, then restores the game's orientation.

```swift
config.orientationPreference = .portrait
```

```java
config.orientationPreference = StashNativeCard.CardConfig.ORIENTATION_PORTRAIT;
```

iPhone presents the card in an SDK-owned window. Android requests portrait in compact fullscreen windows. iPad, tablets, and multi-window keep the host orientation. The OS can refuse to rotate.

## Android portrait backdrop

Covers the game with a screenshot while Android rotates it behind a portrait card.

```java
StashNativeCard.setBackdropBitmap(screenshot); // or setBackdropBytes(pngOrJpegBytes)
StashNativeCard.getInstance().openCard(activity, checkoutUrl, config);
```

Call it right before `openCard`. The SDK takes ownership of the bitmap and recycles it. The next accepted card uses the image if portrait applies and discards it otherwise.
