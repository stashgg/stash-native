---
title: Callbacks
parent: Usage
nav_order: 5
description: Receive payment, dismissal, browser, and CodeLink events, and control what is open.
---

# Callbacks

One delegate (iOS) or listener (Android) receives events from the checkout card, the browser, and CodeLink. Events arrive on the main thread. Use them to update the game's UI; grant items only after your backend confirms the purchase.

## Set the receiver

Set it once, before you open anything, so no event is missed.

```swift
StashNativeCard.sharedInstance().delegate = self

extension StoreViewController: StashNativeCardDelegate {
    func stashNativeCardDidCompletePayment(withOrder order: String?) {}
    func stashNativeCardDidFailPayment() {}
    func stashNativeCardDidDismiss() {}
}
```

```java
StashNativeCard.getInstance().setListener(new StashNativeCard.StashNativeCardListenerAdapter() {
    @Override public void onPaymentSuccess(String order) {}
    @Override public void onPaymentFailure() {}
    @Override public void onDialogDismissed() {}
});
```

On iOS every delegate method is optional, and the SDK holds the delegate weakly, so keep your own reference to it or events stop. On Android, extend `StashNativeCardListenerAdapter` to override only what you need. The SDK keeps the listener alive.

## Events

| Event | iOS | Android | Fires when |
|---|---|---|---|
| Payment success | `stashNativeCardDidCompletePayment(withOrder:)` | `onPaymentSuccess(order)` | The player completes a payment in the card |
| Payment failure | `stashNativeCardDidFailPayment()` | `onPaymentFailure()` | The payment fails |
| Dismissed | `stashNativeCardDidDismiss()` | `onDialogDismissed()` | The player or checkout closes the card, or you call `dismiss()` |
| Page loaded | `stashNativeCardDidLoadPage(_:)` | `onPageLoaded(loadTimeMs)` | Checkout finished loading. Reports the load time in milliseconds. |
| Network error | `stashNativeCardDidEncounterNetworkError()` | `onNetworkError()` | Checkout could not load. The card closes. |
| External payment | `stashNativeCardDidRequestExternalPayment(with:)` | `onExternalPayment(url)` | Checkout continues the payment in the browser. The card closes and the browser opens. |
| Browser closed | `stashNativeCardDidCloseBrowser()` | `onBrowserClosed()` | The browser from `openBrowser` or an external payment closes |
| Code scanned | `stashNativeCardDidScanQRCode(_:)` | `onQrCodeScanned(content)` | CodeLink reads a QR code |
| CodeLink error | `stashNativeCardCodeLinkDidEncounterError(_:)` | `onCodeLinkError(error)` | The scanner cannot use the camera |

`order` holds the order details checkout sends, as a string or JSON, or `nil`/`null` when there are none. Use it for your UI or to look up the order, never as proof of payment.

## Order of events

| What happens | Events you receive |
|---|---|
| Payment succeeds or fails | The payment event. The card closes without a dismissal event. |
| Payment succeeds or fails with `autoClose` off | The payment event. The card stays open until it is dismissed. |
| The player closes the card | Dismissed |
| Checkout cannot load | Network error, without a dismissal event |
| Checkout continues in the browser | External payment, then browser closed |
| You call `closeBrowser()` or `dismiss()` while Safari is open (iOS) | Dismissed, then browser closed |
| A QR code is scanned | Code scanned, after the card closes |

## Open the next presentation

To chain presentations, open the next one from the dismissed, network error, browser closed, or code scanned event. On iOS, a call made inside a payment event is ignored while the card is still closing.

## Check what is open

| Query | Returns `true` |
|---|---|
| `isCurrentlyPresented` | While a card or scanner is open. On iOS also while Safari is open. |
| `isPurchaseProcessing` | While checkout is processing a payment. The player cannot close the card during that time. |

## Close from code

```swift
StashNativeCard.sharedInstance().dismiss()
StashNativeCard.sharedInstance().resetPresentationState()
```

```java
StashNativeCard.getInstance().dismiss();
StashNativeCard.getInstance().resetPresentationState();
```

- `dismiss()` closes the card with its animation and sends the dismissed event. It closes the card even while a payment is processing, so check `isPurchaseProcessing` first. On iOS it closes Safari too.
- `resetPresentationState()` closes everything at once and sends no events. Use it when the game must abandon checkout, for example on logout or when the player leaves the store scene.
