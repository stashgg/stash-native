---
title: Callbacks and lifecycle
parent: Usage reference
nav_order: 5
description: Every delegate and listener callback, when it fires, delivery order for each outcome, state queries, dismissal, and reset.
---

# Callbacks and lifecycle

One delegate (iOS) or listener (Android) receives events from every presentation: card, browser, and CodeLink. Set it before opening. Callbacks run on the main thread.

Payment callbacks are client-side UI signals. Grant purchases only after your backend confirms the payment.

## Setting the receiver

Swift:

```swift
final class StoreViewController: UIViewController, StashNativeCardDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        StashNativeCard.sharedInstance().delegate = self
    }

    func stashNativeCardDidCompletePayment(withOrder order: String?) {
        // Ask your backend to confirm the purchase.
    }

    func stashNativeCardDidFailPayment() {}

    func stashNativeCardDidDismiss() {}
}
```

All delegate methods are optional. The `delegate` property is weak under ARC and `assign` under manual reference counting: keep the delegate object alive while presentations can run.

Java:

```java
StashNativeCard.getInstance().setListener(new StashNativeCard.StashNativeCardListenerAdapter() {
    @Override
    public void onPaymentSuccess(String order) {
        // Ask your backend to confirm the purchase.
    }

    @Override
    public void onDialogDismissed() {}
});
```

`StashNativeCardListenerAdapter` implements every method as a no-op. The SDK holds the listener strongly, so anonymous classes stay alive while the game is in the background.

## Callback reference

| Event | iOS | Android | Payload |
|---|---|---|---|
| Payment success | `stashNativeCardDidCompletePayment(withOrder:)` | `onPaymentSuccess(String order)` | Order string, or `nil` / `null` |
| Payment success, legacy | `stashNativeCardDidCompletePayment` | None | None |
| Payment failure | `stashNativeCardDidFailPayment` | `onPaymentFailure()` | None |
| Dismissed | `stashNativeCardDidDismiss` | `onDialogDismissed()` | None |
| Page loaded | `stashNativeCardDidLoadPage(_:)` | `onPageLoaded(long loadTimeMs)` | Milliseconds (`double` on iOS, `long` on Android) |
| Network error | `stashNativeCardDidEncounterNetworkError` | `onNetworkError()` | None |
| External payment | `stashNativeCardDidRequestExternalPayment(with:)` | `onExternalPayment(String url)` | Validated `http` or `https` URL including the `theme` parameter |
| Browser closed | `stashNativeCardDidCloseBrowser` | `onBrowserClosed()` | None |
| QR code scanned | `stashNativeCardDidScanQRCode(_:)` | `onQrCodeScanned(String content)` | Raw QR payload |
| CodeLink error | `stashNativeCardCodeLinkDidEncounterError(_:)` | `onCodeLinkError(CodeLinkError error)` | `NSError` or enum value. See [CodeLink errors](codelink.md#errors). |

Objective-C selectors: `stashNativeCardDidCompletePaymentWithOrder:`, `stashNativeCardDidLoadPage:`, `stashNativeCardDidRequestExternalPaymentWithURL:`, `stashNativeCardDidScanQRCode:`, `stashNativeCardCodeLinkDidEncounterError:`; the others match their Swift names.

### Triggers

| Event | Fires when |
|---|---|
| Payment success | The page calls `stash_sdk.onPaymentSuccess(order)`, or navigates to a non-web URL containing `stash-pay/success` (order is `nil`). On iOS, also `dismissSafariViewController(withResult: true)`. |
| Payment success, legacy | Same as payment success, only when the delegate does not implement the `withOrder` variant |
| Payment failure | The page calls `stash_sdk.onPaymentFailure()`, or navigates to `stash-pay/failure`. On iOS, also `dismissSafariViewController(withResult: false)`. |
| Dismissed | User dismissal; page `window.close()` or `stash-pay/cancel` outside purchase processing; native `dismiss()`; a main-frame load failure after the first load; CodeLink closed without a scan. On iOS, also `closeBrowser()` or `dismiss()` while Safari is open. |
| Page loaded | Once per card, when the first page finishes. iOS measures from presentation start to the first finished navigation. Android measures from the last navigation start before the content appears to the end of the loading crossfade. |
| Network error | The initial load fails (no connection, a main-frame HTTP status of 400 or higher, or 15 s of foreground time without a response), or the WebView renderer is lost and cannot be recovered. The card closes. See [Loading and recovery](../architecture/index.md#loading-and-recovery). |
| External payment | The page calls `stash_sdk.openExternalBrowser(url)` with a valid URL |
| Browser closed | The browser from `openBrowser` or an external payment closes |
| QR code scanned | CodeLink reads a nonempty QR code. Delivered after the card closes. |
| CodeLink error | The scanner cannot use the camera. At most once per scanner session. |

The order payload is the page's string argument unchanged. Non-string arguments arrive as `JSON.stringify` output. An omitted, `null`, `undefined`, or empty argument arrives as `nil` or `null`.

## Delivery order

| Outcome | Callbacks, in order | Card |
|---|---|---|
| Payment success or failure, `autoClose = true` | Payment callback | Closes. No dismissal callback. |
| Payment success or failure, `autoClose = false` | Payment callback for every signal | Stays open. A later close reports a dismissal. |
| User, page, or native dismissal | Dismissed | Closes |
| Initial load failure or unrecoverable renderer loss | Network error | Closes. No dismissal callback. |
| External payment | External payment, then browser closed | Card closes before the browser opens. No dismissal callback. |
| `openBrowser`, user closes Safari or the tab | Browser closed | |
| `openBrowser`, iOS `closeBrowser()` or `dismiss()` | Dismissed, then browser closed | |
| CodeLink scan | QR code scanned | Closes before the callback |
| CodeLink camera error, then user closes | CodeLink error, then dismissed | Stays open after the error |
| Android CodeLink without CameraX or ZXing | CodeLink error | Closes. No dismissal callback. |
| `resetPresentationState()` | None | Closes immediately |

Platform timing:

- iOS delivers the dismissal and network error callbacks after the dismissal animation and, for portrait cards, after the orientation is restored. Payment callbacks run before the card starts closing.
- Android delivers events through package-local broadcasts posted to the main thread. The dismissal callback follows the checkout activity's destruction. Network errors are reported while the activity finishes without animation.

Guarantees:

- With `autoClose`, each session reports at most one terminal outcome: one payment result, one dismissal, one network error, one external payment, or one scan.
- Events from an ended session never reach a newer session.
- After process death on Android, the checkout is not restored and no callback is delivered to the new process.

## Opening the next presentation

Open calls made while a session is active are ignored. Whether a callback can open the next presentation depends on when each platform ends the session:

| Callback | iOS: open allowed inside it | Android: open allowed inside it |
|---|---|---|
| Dismissed, network error, QR code scanned | Yes | Yes |
| Browser closed | Yes | Yes |
| Payment result with `autoClose` | No. The card is still closing. | Yes |
| External payment | No | Do not open here. The SDK is handing off to the browser. |
| CodeLink error | No | No, unless the scanner closed for a missing dependency |

On iOS, after a payment callback with `autoClose`, wait until `isCurrentlyPresented` is false before opening another presentation.

## State queries

| Query | iOS | Android |
|---|---|---|
| `isCurrentlyPresented` | `true` while a session exists: from an accepted open until the card, scanner, or Safari is fully closed. Stays `true` through an external payment browser. | `true` from an accepted `openCard` or `codeLink` until a terminal event is dispatched, or until an external payment handoff starts. Always `false` for `openBrowser`. |
| `isPurchaseProcessing` | `true` between the page's `onPurchaseProcessing()` and `onProcessingCompleted()` or a payment result | Same |

There is no callback for processing changes. Query `isPurchaseProcessing` when you need the current state.

## Processing lock

The page calls `stash_sdk.onPurchaseProcessing()` while a payment is in flight. Until it calls `onProcessingCompleted()` or reports a payment result:

- Swipe, grabber or handle drags, backdrop taps, Android Back, and VoiceOver escape do nothing.
- `window.close()` and `stash-pay/cancel` do nothing.
- The grabber or handle is hidden, and active card drags are cancelled.
- Native `dismiss()` still closes the card and reports a dismissal.

A renderer or web content process loss during processing ends the session with a network error instead of reloading the payment page.

## Dismiss and reset

| Method | Effect |
|---|---|
| `dismiss()` | Animated close of the card or scanner. Reports a dismissal, even during purchase processing. On iOS, closes Safari when a browser presentation is active. On Android it does not affect browsers. |
| `resetPresentationState()` | Immediate teardown with no animation and no callbacks. On Android it also unregisters the SDK's broadcast receiver and lifecycle observer, clears a pending backdrop, and cancels browser close tracking. |

Use `resetPresentationState()` when the host must abandon the presentation, for example on logout or engine shutdown. Do not use it for normal closing; the app then receives no outcome for that session.
