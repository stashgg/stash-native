---
title: Checkout Card
parent: Usage
nav_order: 2
description: Show Stash Pay checkout in a native card over the game.
---

# Checkout Card

The checkout card shows Stash Pay checkout in a native card over the game. Results arrive through [callbacks](callbacks.md#checkout-card).

![Checkout card on iPhone, unfolded iPhone Duo, and iPad](../assets/images/opencard-devices-dark.png)

The card fits phones, tablets, foldables, and split screen, and follows light or dark mode.

## Open the card

Pass the [checkout link](https://docs.stash.gg/guides/stash-pay/integration#create-a-checkout-link) from your backend and the view controller or activity showing the game:

```swift
StashNative.sharedInstance().openCard(withURL: checkoutURL, from: self, config: nil)
```

```java
StashNative.getInstance().openCard(activity, checkoutUrl, null);
```

`dismiss()` closes the card, even during a payment. Check `isPurchaseProcessing` first.

## Configuration

Pass `StashNativeCardConfig` (iOS) or `StashNative.CardConfig` (Android), or `nil`/`null` for the defaults. Sizes are in points (iOS) or dp (Android). The card never exceeds the screen.

| Property | Default | Description |
|---|---|---|
| `preferredContentWidth` | `400` | Card width on wide screens. Portrait phones use the full width. |
| `preferredContentHeight` | `560` | Height when the card opens. Short pages open shorter. |
| `maximumContentHeight` | `720` | Height when expanded, for example for the keyboard. `0` removes the limit. |
| `edgeMargin` | `16` | Space between the card and the screen edges |
| `allowDismiss` | `true` | Players can close the card by swiping down, tapping outside, or pressing Back |
| `autoClose` | `true` | The card closes after a payment succeeds or fails |
| `orientationPreference` | Follow host | Portrait on phones. See [Portrait checkout](#portrait-checkout). |

```swift
let config = StashNativeCardConfig()
config.allowDismiss = false
StashNative.sharedInstance().openCard(withURL: checkoutURL, from: self, config: config)
```

```java
StashNative.CardConfig config = new StashNative.CardConfig();
config.allowDismiss = false;
StashNative.getInstance().openCard(activity, checkoutUrl, config);
```

## Portrait checkout

![Portrait checkout card on iPhone, over an app locked to landscape](../assets/images/portrait-checkout-dark.png){: .single-device }

On phones, the card can open in portrait in a landscape game, including a landscape-only one. The game's orientation returns when the card closes.

```swift
config.orientationPreference = .portrait
```

```java
config.orientationPreference = StashNative.CardConfig.ORIENTATION_PORTRAIT;
```

Tablets, unfolded foldables, and split screen keep the game's orientation.

## Portrait backdrop (Android)

![Portrait checkout card on Android, over a backdrop image](../assets/images/portrait-backdrop-dark.png){: .single-device }

On Android, the game rotates behind a portrait card, which can cause glitches. To hide them, pass a screenshot of the game before opening the card:

```java
StashNative.setBackdropBitmap(screenshot); // or setBackdropBytes(pngOrJpegBytes)
StashNative.getInstance().openCard(activity, checkoutUrl, config);
```

The SDK takes ownership of the bitmap; do not reuse or recycle it. iOS needs no backdrop.

## WebView debugging

During development, make checkout inspectable before opening the card:

```swift
StashNative.setInspectableWebViewsEnabled(true)
```

```java
StashNative.setInspectableWebViewsEnabled(true);
```

Inspect it with Safari Web Inspector (iOS 16.4+) or `chrome://inspect` (Android). Keep it off in release builds.

## Callbacks

See [Checkout Card callbacks](callbacks.md#checkout-card).
