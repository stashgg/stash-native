---
title: Callbacks
parent: Usage
nav_order: 5
description: Receive Checkout Card, In-Game Browser, and QR Code Linking events in the game.
---

# Callbacks

One delegate (iOS) or listener (Android) receives all events, on the main thread.

## Set the receiver

Set the receiver on the main thread before you open anything:

```swift
StashNative.sharedInstance().delegate = self
```

```java
StashNative.getInstance().setListener(listener);
```

- iOS: all `StashNativeDelegate` methods are optional. The SDK does not retain the delegate; keep your own reference.
- Android: extend `StashNative.StashNativeListenerAdapter` and override only what you need. The SDK keeps the listener until you call `setListener(null)`.

## Checkout Card

| Event | iOS | Android | Fires when |
|---|---|---|---|
| Payment success | `stashNativeDidCompletePayment(withOrder:)` | `onPaymentSuccess(order)` | The player completes a payment |
| Payment failure | `stashNativeDidFailPayment()` | `onPaymentFailure()` | The payment fails |
| Card dismissed | `stashNativeDidDismissCard()` | `onCardDismissed()` | The player or checkout closes the card, or you call `dismiss()` |
| Page loaded | `stashNativeDidLoadPage(_:)` | `onPageLoaded(loadTimeMs)` | Checkout finished loading. Reports the load time in milliseconds. |
| Network error | `stashNativeDidEncounterNetworkError()` | `onNetworkError()` | Checkout failed to load or lost its connection. The card closes. |
| External payment | `stashNativeDidRequestExternalPayment(with:)` | `onExternalPayment(url)` | Checkout moves the payment to the in-game browser. The card closes. |

`order` holds the order details from checkout, as a string or JSON, or `nil`/`null`. Grant items only after your backend [confirms the purchase](https://docs.stash.gg/guides/stash-pay/integration#processing-purchase).

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

## In-Game Browser

| Event | iOS | Android | Fires when |
|---|---|---|---|
| Browser dismissed | `stashNativeDidDismissBrowser()` | `onBrowserDismissed()` | The browser closes, after `openBrowser` or an external payment |

Browser payments arrive through your deep link; see [Return to the game](browser.md#return-to-the-game). On iOS, `dismissSafariViewController(withResult:)` sends the payment result before browser dismissed.

## QR Code Linking

| Event | iOS | Android | Fires when |
|---|---|---|---|
| Code scanned | `stashNativeDidScanQRCode(_:)` | `onQrCodeScanned(content)` | The scanner reads a QR code and closes |
| Scanner dismissed | `stashNativeDidDismissScanner()` | `onScannerDismissed()` | The scanner closes without a result |
| Error | `stashNativeScannerDidEncounterError(_:)` | `onScannerError(error)` | The scanner cannot start or use the camera. See [Errors](#errors). |

### Errors

Most errors leave the scanner open. A missing `StashNativeCodeLink` module presents nothing and sends no dismissal event.

| Cause | iOS `StashNativeScannerError.Code` | Android `ScannerError` | Fix |
|---|---|---|---|
| Camera access denied | `.cameraPermissionDenied` | `CAMERA_PERMISSION_DENIED` | None. The scanner offers a Settings button. |
| No camera | `.cameraUnavailable` | `CAMERA_UNAVAILABLE` | Offer another way to link |
| Camera setup failed | `.cameraConfigurationFailed` | `CAMERA_CONFIGURATION_FAILED` | Retry later |
| Scanner module missing | `.scannerUnavailable` | `SCANNER_UNAVAILABLE` | Add `StashNativeCodeLink` (with CameraX and ZXing on Android) |
| Camera usage description missing | `.missingCameraUsageDescription` | Not applicable | Add `NSCameraUsageDescription` |
| Camera permission removed from the manifest | Not applicable | `CAMERA_PERMISSION_NOT_DECLARED` | Keep the module's `CAMERA` permission in the merged manifest |

## Order of events

Each presentation ends with one final event. Resume the game when it arrives.

| Presentation | Final event |
|---|---|
| Checkout Card | Payment success or failure, card dismissed, or network error. After an external payment, browser dismissed. |
| In-Game Browser | Browser dismissed |
| QR Code Linking | Code scanned, scanner dismissed, or the scanner-unavailable error |

With `autoClose` off, payment events can repeat and the card stays open until dismissed. `resetPresentationState()` closes the card or scanner, and Safari on iOS, without sending events.
