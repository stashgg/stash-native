---
title: Checkout Card
nav_order: 3
description: Show Stash Pay checkout in a native card over the game.
---

# Checkout Card

The checkout card shows Stash Pay checkout in a native card over the host application. Results arrive through [callbacks](#callbacks).

![Checkout card on iPhone, unfolded iPhone Duo, and iPad](../assets/images/opencard-devices-dark.png)

The checkout card is fully responsive on both platforms and adapts to the device type, state, and system appearance.

## Open the card

Pass the [checkout link](https://docs.stash.gg/guides/stash-pay/integration#create-a-checkout-link) generated on your backend and the view controller or activity showing the game to trigger the checkout dialog:

```swift
StashNative.sharedInstance().openCard(withURL: checkoutURL, from: self, config: nil)
```

```java
StashNative.getInstance().openCard(activity, checkoutUrl, null);
```

## Configuration

To optionally adjust the card configuration, pass `StashNativeCardConfig` (iOS) or `StashNative.CardConfig` (Android). Sizes are in points (iOS) or dp (Android).

{: .info }
We recommend keeping the default card dimensions unless your integration requires a different size.

| Property | Default | Description |
|---|---|---|
| `preferredContentWidth` | `400` | Preferred width; full width on portrait phones |
| `preferredContentHeight` | `560` | Initial card height |
| `maximumContentHeight` | `720` | Expanded height; `0` removes the limit |
| `edgeMargin` | `16` | Screen edge spacing |
| `allowDismiss` | `true` | Allow swipe, outside tap, or Back dismissal |
| `autoClose` | `true` | Close after payment success or failure |
| `orientationPreference` | Follow host | Follow host or [force portrait on phones](#forcing-portrait-card) |

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

## Forcing Portrait Card

![Portrait checkout card on iPhone, over an app locked to landscape](../assets/images/portrait-checkout-dark.png){: .single-device }

On phones, the SDK makes a best-effort attempt to render the checkout card as a portrait overlay for more comfortable text input. The host application continues running in landscape and does not need to support portrait.

```swift
config.orientationPreference = .portrait
```

```java
config.orientationPreference = StashNative.CardConfig.ORIENTATION_PORTRAIT;
```

### Portrait backdrop (Android)

![Portrait checkout card on Android, over a backdrop image](../assets/images/portrait-backdrop-dark.png){: .single-device }

Forcing a portrait card on Android phones may cause visual glitches in some host applications due to how Android handles screen orientation. To hide these artifacts, set an image backdrop before opening the card. Use a screenshot of the current app state or a custom image:

```java
StashNative.setBackdropBitmap(backdrop); // or setBackdropBytes(pngOrJpegBytes)
StashNative.getInstance().openCard(activity, checkoutUrl, config);
```

## Callbacks

These events go to the shared receiver; see [Setting Callbacks](callbacks.md).

| Callback (iOS / Android) | Fires when |
|---|---|
| <span class="callback-tooltip" title="Order details from checkout, supplied as a JSON string or plain text; nil/null when absent. Confirm the purchase on your backend before granting items."><code>stashNativeDidCompletePayment(withOrder:)</code><br><code>onPaymentSuccess(order)</code></span> | Payment succeeds |
| `stashNativeDidFailPayment()`<br>`onPaymentFailure()` | Payment fails |
| `stashNativeDidDismissCard()`<br>`onCardDismissed()` | The user, checkout page, or app dismisses the card |
| `stashNativeDidLoadPage(_:)`<br>`onPageLoaded(loadTimeMs)` | Checkout loads (includes load time in milliseconds) |
| `stashNativeDidEncounterNetworkError()`<br>`onNetworkError()` | Checkout fails to load or loses its connection |
| `stashNativeDidRequestExternalPayment(with:)`<br>`onExternalPayment(url)` | Payment moves to the in-game browser |

```swift
extension StoreViewController: StashNativeDelegate {
    func stashNativeDidCompletePayment(withOrder order: String?) {
        // Confirm the purchase on your backend, then grant items.
    }

    func stashNativeDidFailPayment() {
        // Update the store UI.
    }

    func stashNativeDidDismissCard() {
        // Resume the game.
    }
}
```

```java
StashNative.getInstance().setListener(new StashNative.StashNativeListenerAdapter() {
    @Override
    public void onPaymentSuccess(String order) {
        // Confirm the purchase on your backend, then grant items.
    }

    @Override
    public void onPaymentFailure() {
        // Update the store UI.
    }

    @Override
    public void onCardDismissed() {
        // Resume the game.
    }
});
```

### External Payment Scenarios

Some alternative payment methods (such as Klarna, Cash App, etc.) require the user to finish the purchase in an external browser or another app. `onExternalPayment` notifies the host application of this handoff. Handling it is optional unless your app needs to react to the handoff.

- By default, the card closes and the payment continues in the [in-game browser](browser.md). The presentation ends with `onBrowserDismissed` instead of `onCardDismissed`, and the result arrives through the [deep link](browser.md#handling-results).
- When the page passes `keepOpen`, the browser opens over the card, which stays open for the player's return. No browser event follows; the card ends with its own events and closes the browser with it.

## Other

### WebView debugging

During development, make checkout inspectable before opening the card:

```swift
StashNative.setInspectableWebViewsEnabled(true)
```

```java
StashNative.setInspectableWebViewsEnabled(true);
```

Inspect it with Safari Web Inspector (iOS 16.4+) or `chrome://inspect` (Android). Keep it off in release builds.

### Checking state

Check whether an SDK presentation is active and whether checkout is processing a payment. On iOS, read these values on the main thread.

```swift
let isPresented = StashNative.sharedInstance().isCurrentlyPresented
let isProcessing = StashNative.sharedInstance().isPurchaseProcessing
```

```java
boolean isPresented = StashNative.getInstance().isCurrentlyPresented();
boolean isProcessing = StashNative.getInstance().isPurchaseProcessing();
```

### Dismissing Card

Force dismiss the checkout card programmatically:

```swift
StashNative.sharedInstance().dismiss()
```

```java
StashNative.getInstance().dismiss();
```
