---
title: Callbacks
parent: Usage
nav_order: 5
description: Receive payment, dismissal, browser, and CodeLink events, and control what is open.
---

# Callbacks

One delegate (iOS) or listener (Android) receives events from the checkout card, the browser, and CodeLink. Events arrive on the main thread. Use them to update the game's UI; grant items only after your backend confirms the purchase.

## Set the receiver

Register, read, replace, and clear the receiver on the platform main thread. Register before opening; open calls may come from any thread and dispatch to main. A stable app or engine coordinator makes a useful receiver.

```swift
StashNative.sharedInstance().delegate = self

extension StoreViewController: StashNativeDelegate {
    func stashNativeDidCompletePayment(withOrder order: String?) {}
    func stashNativeDidFailPayment() {}
    func stashNativeDidDismissCard() {}
    func stashNativeDidDismissScan() {}
    func stashNativeDidDismissBrowser() {}
}
```

```java
StashNative.getInstance().setListener(new StashNative.StashNativeListenerAdapter() {
    @Override public void onPaymentSuccess(String order) {}
    @Override public void onPaymentFailure() {}
    @Override public void onCardDismissed() {}
    @Override public void onScanDismissed() {}
    @Override public void onBrowserDismissed() {}
});
```

The SDK selects the current receiver for each event. Replacing it affects future events from flows that are already open. Clearing it stops future delivery; it does not cancel an executing callback or events your wrapper has already queued. Events are never replayed.

On iOS every delegate method is optional. Keep your own strong reference: the SDK uses `weak` under ARC and `assign` under manual reference counting. Under manual reference counting, clear the delegate on main before releasing it, and synchronize teardown with callbacks. On Android, extend `StashNativeListenerAdapter` to override only what you need; the SDK holds one strong listener reference. Clear it when its owner is finished.

```swift
StashNative.sharedInstance().delegate = nil // On main.
```

```java
StashNative.getInstance().setListener(null); // On main.
```

## Events

| Event | iOS | Android | Fires when |
|---|---|---|---|
| Payment success | `stashNativeDidCompletePayment(withOrder:)` | `onPaymentSuccess(order)` | The player completes a payment in the card |
| Payment failure | `stashNativeDidFailPayment()` | `onPaymentFailure()` | The payment fails |
| Card dismissed | `stashNativeDidDismissCard()` | `onCardDismissed()` | The player, checkout page, or app dismisses the card |
| Scan dismissed | `stashNativeDidDismissScan()` | `onScanDismissed()` | The player or app dismisses the scanner without a result |
| Page loaded | `stashNativeDidLoadPage(_:)` | `onPageLoaded(loadTimeMs)` | Checkout finished loading. Reports the load time in milliseconds. |
| Network error | `stashNativeDidEncounterNetworkError()` | `onNetworkError()` | Checkout could not load. The card closes. |
| External payment | `stashNativeDidRequestExternalPayment(with:)` | `onExternalPayment(url)` | Checkout continues the payment in the browser. The card closes and the browser opens. |
| Browser dismissed | `stashNativeDidDismissBrowser()` | `onBrowserDismissed()` | The browser closes, whether opened directly or through checkout's payment handoff |
| Code scanned | `stashNativeDidScanQRCode(_:)` | `onQrCodeScanned(content)` | CodeLink reads a QR code |
| CodeLink error | `stashNativeCodeLinkDidEncounterError(_:)` | `onCodeLinkError(error)` | The scanner cannot start or use the camera; see [errors](codelink.md#errors) |

`order` holds the order details checkout sends, as a string or JSON, or `nil`/`null` when there are none. Use it for your UI or to look up the order, never as proof of payment.

## Order of events

| What happens | Events you receive |
|---|---|
| Payment succeeds or fails | The payment event. The card closes without a dismissal event. |
| Payment succeeds or fails with `autoClose` off | Each payment event. Events can repeat; the card stays open until it is dismissed. |
| The player closes the card | Card dismissed |
| The player closes the scanner without a result | Scan dismissed |
| Checkout cannot load | Network error, without a dismissal event |
| Checkout continues in the browser | External payment, then browser dismissed; no card dismissal |
| The browser opened with `openBrowser` closes | Browser dismissed |
| Safari Done, `closeBrowser()`, or `dismiss()` while Safari is open (iOS) | Browser dismissed; no card or scan dismissal |
| `dismissSafariViewController(withResult:)` (iOS) | The requested payment result, then browser dismissed; no card or scan dismissal |
| A QR code is scanned | Code scanned after teardown, without a dismissal event |
| Android scanner dependencies are missing | `onCodeLinkError(SCANNER_UNAVAILABLE)` after teardown, without a dismissal event |
| You call `resetPresentationState()` | No events; receiver registration stays in place |

## Open the next presentation

To chain presentations, open the next one from a dismissal, network error, or code scanned event. Most camera errors leave the scanner open. A payment callback is not a portable signal to open the next presentation: iOS delivers it before teardown and ignores an open made inside it.

## Check what is open

| Query | Returns `true` |
|---|---|
| `isCurrentlyPresented` | While a card or scanner is open. On iOS also while Safari is open. |
| `isPurchaseProcessing` | While checkout is processing a payment. The player cannot close the card during that time. |

These queries are informational. `isCurrentlyPresented` cannot reserve a slot or prove an open was accepted. Busy state, an invalid host, or an invalid URL can cause an open to be silently ignored; there is no admission result callback.

## Close from code

```swift
StashNative.sharedInstance().dismiss()
StashNative.sharedInstance().resetPresentationState()
```

```java
StashNative.getInstance().dismiss();
StashNative.getInstance().resetPresentationState();
```

- `dismiss()` closes the card or scanner with its animation and sends card dismissed or scan dismissed. It closes the card even while a payment is processing, so check `isPurchaseProcessing` first. On iOS it closes Safari too, sending only browser dismissed.
- `resetPresentationState()` tears down the card or scanner and SDK tracking silently, preserving receiver registration. It closes Safari on iOS; Android cannot close an already-open Custom Tab or system browser. Use it when the game must abandon checkout, for example on logout.
