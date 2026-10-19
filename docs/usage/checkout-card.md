---
title: Checkout Card
parent: Usage
nav_order: 2
description: Show Stash Pay checkout in a native card over the game.
---

# Checkout Card

The checkout card shows Stash Pay checkout in a native card over the game. Players pay without leaving the game, and the game receives the result through [callbacks](callbacks.md#checkout-card).

![Checkout card on iPhone, unfolded iPhone Duo, and iPad](../assets/images/opencard-devices-dark.png)

The card adapts to phones, tablets, foldables, and split screen, and follows the device's light or dark appearance.

## Open the card

Pass the checkout link from your backend and the view controller or activity that shows the game:

```swift
StashNative.sharedInstance().openCard(withURL: checkoutURL, from: self, config: nil)
```

```java
StashNative.getInstance().openCard(activity, checkoutUrl, null);
```

`dismiss()` closes the card from code, even while a payment is processing. Check `isPurchaseProcessing` before you call it.

## Configuration

Pass a `StashNativeCardConfig` (iOS) or `StashNative.CardConfig` (Android), or `nil`/`null` for the defaults. Sizes are in points on iOS and dp on Android. The card never grows past the screen.

| Property | Default | Description |
|---|---|---|
| `preferredContentWidth` | `400` | Card width on wide screens. Phones in portrait use the full width. |
| `preferredContentHeight` | `560` | Card height when it opens. Short checkout pages open shorter. |
| `maximumContentHeight` | `720` | Card height when it expands, for example for the keyboard. `0` removes the limit. |
| `edgeMargin` | `16` | Space between the card and the screen edges |
| `allowDismiss` | `true` | Players can close the card by swiping down, tapping outside it, or pressing Back |
| `autoClose` | `true` | The card closes when a payment succeeds or fails |
| `orientationPreference` | Follow host | Shows checkout in portrait on phones. See [Portrait checkout](#portrait-checkout). |

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

Checkout is laid out for portrait. On phones, a landscape game can show the card in portrait, even if the game supports only landscape. The game returns to its orientation when the card closes.

```swift
config.orientationPreference = .portrait
```

```java
config.orientationPreference = StashNative.CardConfig.ORIENTATION_PORTRAIT;
```

Tablets, unfolded foldables, and split screen keep the game's orientation.

## Portrait backdrop (Android)

![Portrait checkout card on Android, over a backdrop image](../assets/images/portrait-backdrop-dark.png){: .single-device }

On Android, the game rotates behind a portrait card, and some games show glitches while it does. To hide them, pass a screenshot of the game right before opening the card:

```java
StashNative.setBackdropBitmap(screenshot); // or setBackdropBytes(pngOrJpegBytes)
StashNative.getInstance().openCard(activity, checkoutUrl, config);
```

The SDK takes ownership of the bitmap, so do not reuse or recycle it. iOS needs no backdrop.

## WebView debugging

During development, make checkout inspectable before opening the card:

```swift
StashNative.setInspectableWebViewsEnabled(true)
```

```java
StashNative.setInspectableWebViewsEnabled(true);
```

Then inspect it with Safari Web Inspector (iOS 16.4+) or `chrome://inspect` (Android). Leave it off in release builds.

## Callbacks

See [Checkout Card callbacks](callbacks.md#checkout-card) for payment results, dismissal, and loading events.
