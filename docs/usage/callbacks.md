---
title: Callbacks
parent: Usage
nav_order: 5
description: Delegate and listener callbacks, their order, presentation state, dismiss, and reset.
---

# Callbacks

One delegate (iOS) or listener (Android) receives events from every presentation, on the main thread. Payment callbacks only update the UI; your backend confirms the purchase.

## Set the receiver

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

iOS holds the delegate weakly, so keep a reference to it. Every delegate method is optional. Android holds the listener strongly; `StashNativeCardListenerAdapter` implements every method as a no-op.

## Events

| Event | iOS | Android | Fires when |
|---|---|---|---|
| Payment success | `stashNativeCardDidCompletePayment(withOrder:)` | `onPaymentSuccess(order)` | The page calls `onPaymentSuccess(order)` or opens a `stash-pay/success` deep link |
| Payment failure | `stashNativeCardDidFailPayment()` | `onPaymentFailure()` | The page calls `onPaymentFailure()` or opens a `stash-pay/failure` deep link |
| Dismissed | `stashNativeCardDidDismiss()` | `onDialogDismissed()` | The user, the page, or `dismiss()` closes the card |
| Page loaded | `stashNativeCardDidLoadPage(_:)` | `onPageLoaded(loadTimeMs)` | The first page finishes loading |
| Network error | `stashNativeCardDidEncounterNetworkError()` | `onNetworkError()` | The first load fails or the WebView process dies. The card closes. |
| External payment | `stashNativeCardDidRequestExternalPayment(with:)` | `onExternalPayment(url)` | The page calls `openExternalBrowser(url)` |
| Browser closed | `stashNativeCardDidCloseBrowser()` | `onBrowserClosed()` | A browser from `openBrowser` or an external payment closes |
| Code scanned | `stashNativeCardDidScanQRCode(_:)` | `onQrCodeScanned(content)` | CodeLink reads a QR code |
| CodeLink error | `stashNativeCardCodeLinkDidEncounterError(_:)` | `onCodeLinkError(error)` | The scanner cannot use the camera |

`order` is the string the page sent, JSON for objects, or `nil`/`null` when the page sent nothing.

## Order

| Outcome | Callbacks |
|---|---|
| Payment result, `autoClose` on | Payment callback. The card closes with no dismissal callback. |
| Payment result, `autoClose` off | Payment callback for every signal. The card stays open. |
| Dismissal | Dismissed |
| Load failure | Network error, with no dismissal callback |
| External payment | External payment, then browser closed |
| `closeBrowser()` or `dismiss()` while Safari is open (iOS) | Dismissed, then browser closed |
| Successful scan | Code scanned, after the card closes |
| `resetPresentationState()` | None |

To open the next presentation, do it from the dismissed, network error, browser closed, or code scanned callback. On iOS, an open call made inside a payment callback with `autoClose` is ignored because the card is still closing.

## State

| Query | iOS | Android |
|---|---|---|
| `isCurrentlyPresented` | `true` until the card, scanner, or Safari has closed | `true` from `openCard` or `codeLink` until a terminal callback. Always `false` for `openBrowser`. |
| `isPurchaseProcessing` | `true` between the page's `onPurchaseProcessing()` and `onProcessingCompleted()` or a payment result | Same as iOS |

## Dismiss and reset

```swift
StashNativeCard.sharedInstance().dismiss()                 // animated, reports a dismissal
StashNativeCard.sharedInstance().resetPresentationState()  // immediate, no callbacks
```

`dismiss()` works during purchase processing. On iOS it also closes Safari. Use `resetPresentationState()` only when the game must abandon the presentation, for example on logout.
