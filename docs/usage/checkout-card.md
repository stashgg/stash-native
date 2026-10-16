---
title: Checkout card
parent: Usage
nav_order: 2
description: Show Stash Pay checkout in an in-game card with direct payment callbacks.
---

# Checkout card

The checkout card shows a Stash Pay checkout link inside your game. Players pay without leaving the app, and the game receives success, failure, and dismissal events directly. Use it for in-game purchases.

![Checkout card on iPhone, unfolded iPhone Duo, and iPad](https://raw.githubusercontent.com/stashgg/stash-native/main/.github/assets/opencard-devices-dark.png)

The card adapts to phones, tablets, foldables, and split screen. It follows the device's light or dark appearance.

## Open the card

Pass the checkout link from your backend, the view controller or activity showing the game, and an optional configuration. Set your [callbacks](#handle-the-result) first.

```swift
StashNativeCard.sharedInstance().openCard(withURL: checkoutURL, from: self, config: nil)
```

```java
StashNativeCard.getInstance().openCard(activity, checkoutUrl, null);
```

## Configuration

Pass `StashNativeCardConfig` (iOS) or `StashNativeCard.CardConfig` (Android), or `nil`/`null` for the defaults. Sizes are points on iOS and dp on Android. The card never grows past the screen.

| Property | Default | Effect |
|---|---|---|
| `preferredContentWidth` | `400` | Card width on wide screens. Phones in portrait use the full width. |
| `preferredContentHeight` | `560` | Height when the card opens. Short checkout pages open shorter. |
| `maximumContentHeight` | `720` | Height when the card expands, for example while the keyboard is open. `0` allows the full screen height. |
| `edgeMargin` | `16` | Space between the card and the screen edges |
| `allowDismiss` | `true` | Players can close the card by swiping it down, tapping outside it, or pressing Back |
| `autoClose` | `true` | The card closes as soon as a payment succeeds or fails |
| `orientationPreference` | Follow host | Shows checkout in portrait on phones. See [Portrait checkout](#portrait-checkout). |

The defaults fit Stash Pay checkout. Common changes:

- Set `allowDismiss` to `false` to prevent accidental closes. Players can still leave through checkout's own close button.
- Set `autoClose` to `false` to keep checkout on screen after the payment, for example so players see its confirmation. Close the card yourself with `dismiss()`, or let the player close it.

```swift
let config = StashNativeCardConfig()
config.allowDismiss = false
StashNativeCard.sharedInstance().openCard(withURL: checkoutURL, from: self, config: config)
```

```java
StashNativeCard.CardConfig config = new StashNativeCard.CardConfig();
config.allowDismiss = false;
StashNativeCard.getInstance().openCard(activity, checkoutUrl, config);
```

## Portrait checkout

Checkout is laid out for portrait on phones. A landscape game can request portrait for the card; the game returns to its own orientation when the card closes.

```swift
config.orientationPreference = .portrait
```

```java
config.orientationPreference = StashNativeCard.CardConfig.ORIENTATION_PORTRAIT;
```

This works even when the game only supports landscape, and your orientation settings stay unchanged. iPads, tablets, unfolded foldables, and split screen keep the game's orientation. The system can still refuse to rotate, so the card also works in landscape.

## Android portrait backdrop

On Android, the game rotates behind a portrait card, and some games show glitches while that happens. To hide them, pass a screenshot of the game right before opening the card:

```java
StashNativeCard.setBackdropBitmap(screenshot); // or setBackdropBytes(pngOrJpegBytes)
StashNativeCard.getInstance().openCard(activity, checkoutUrl, config);
```

The SDK takes ownership of the bitmap, so do not reuse or recycle it. The next card you open uses the image if it shows in portrait, and discards it otherwise. iOS does not need a backdrop.

## Handle the result

Set a delegate or listener before opening. These events matter for the card:

| Event | iOS | Android | What to do |
|---|---|---|---|
| Payment success | `stashNativeCardDidCompletePayment(withOrder:)` | `onPaymentSuccess(order)` | Ask your backend to confirm the purchase, then grant the items |
| Payment failure | `stashNativeCardDidFailPayment()` | `onPaymentFailure()` | Update your store UI |
| Dismissed | `stashNativeCardDidDismiss()` | `onDialogDismissed()` | Resume the game |
| Network error | `stashNativeCardDidEncounterNetworkError()` | `onNetworkError()` | Tell the player checkout could not load. The card is already closed. |

```swift
extension StoreViewController: StashNativeCardDelegate {
    func stashNativeCardDidCompletePayment(withOrder order: String?) {
        // Confirm the purchase on your backend before granting items.
    }

    func stashNativeCardDidFailPayment() {
        // Update the store UI.
    }

    func stashNativeCardDidDismiss() {
        // Resume the game.
    }
}
```

```java
StashNativeCard.getInstance().setListener(new StashNativeCard.StashNativeCardListenerAdapter() {
    @Override
    public void onPaymentSuccess(String order) {
        // Confirm the purchase on your backend before granting items.
    }

    @Override
    public void onPaymentFailure() {
        // Update the store UI.
    }

    @Override
    public void onDialogDismissed() {
        // Resume the game.
    }
});
```

`order` contains the order details that checkout sends, as a string or JSON, or `nil`/`null`. All events, their order, and closing the card from code: [Callbacks](callbacks.md).
