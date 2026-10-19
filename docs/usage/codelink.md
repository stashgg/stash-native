---
title: QR Code Linking
nav_order: 5
description: Link a player's Stash webshop account by scanning the webshop's QR code in the game.
---

# QR Code Linking

{: .warning }
QR Code Linking needs the separate `StashNativeCodeLink` module, which the core SDK does not include. Add it as shown in [Package Installation](../index.md#qr-code-linking-module).

Players link their Stash webshop account by scanning the QR code the webshop shows. The scanner opens in the native card, confirms the scan, closes, and returns the code's content to the game. Use that content to link the account, as described in [Account Linking](https://docs.stash.gg/guides/stash-webshop/player-authentication/account-linking#integrate-account-linking).

![QR code scanners on iPhone and Android](../assets/images/codelink-devices-dark.png)

## Requirements

| Platform | Requirement |
|---|---|
| iOS | `StashNativeCodeLink` (library or XCFramework) and `NSCameraUsageDescription` in Info.plist |
| Android | `StashNativeCodeLink` (AAR or `:stashnative-codelink`) with CameraX and ZXing. Its manifest adds the camera permission. |

The scanner asks for camera access the first time it opens. Decoding runs on the device; no images are saved.

## Open the scanner

```swift
StashNative.sharedInstance().openScanner(from: self, config: nil)
```

```java
StashNative.getInstance().openScanner(activity, null);
```

The scanner follows the game's orientation. `dismiss()` closes it.

## Configuration

Pass `StashNativeScannerConfig` (iOS) or `StashNative.ScannerConfig` (Android) to translate the text or hide the info callout. Empty values keep the defaults.

| Property | Default |
|---|---|
| `headerText` | Scan QR code |
| `calloutTitle` | Scan the webshop code |
| `calloutSubtitle` | Keep the QR code centered inside the frame. |
| `cameraUnavailableText` | Camera unavailable |
| `connectedText` | Connected |
| `showCallout` | `true` |

```swift
let config = StashNativeScannerConfig()
config.headerText = "Escanear código QR"
config.showCallout = false
StashNative.sharedInstance().openScanner(from: self, config: config)
```

```java
StashNative.ScannerConfig config = new StashNative.ScannerConfig();
config.headerText = "Escanear código QR";
config.showCallout = false;
StashNative.getInstance().openScanner(activity, config);
```

## Callbacks

These events go to the shared receiver; see [Setting Callbacks](callbacks.md).

| Callback (iOS / Android) | Fires when |
|---|---|
| `stashNativeDidScanQRCode(_:)`<br>`onQrCodeScanned(content)` | The scanner reads a QR code and closes |
| `stashNativeDidDismissScanner()`<br>`onScannerDismissed()` | The scanner closes without a result |
| `stashNativeScannerDidEncounterError(_:)`<br>`onScannerError(error)` | The scanner cannot start or use the camera. See [Errors](#errors). |

The scanner ends with code scanned, scanner dismissed, or the scanner-unavailable error.

### Errors

Errors are `StashNativeScannerError.Code` values on iOS and `ScannerError` values on Android. Most errors leave the scanner open. A missing `StashNativeCodeLink` module presents nothing and sends no dismissal event.

| Cause | Error (iOS / Android) | Fix |
|---|---|---|
| Camera access denied | `.cameraPermissionDenied`<br>`CAMERA_PERMISSION_DENIED` | None. The scanner offers a Settings button. |
| No camera | `.cameraUnavailable`<br>`CAMERA_UNAVAILABLE` | Offer another way to link |
| Camera setup failed | `.cameraConfigurationFailed`<br>`CAMERA_CONFIGURATION_FAILED` | Retry later |
| Scanner module missing | `.scannerUnavailable`<br>`SCANNER_UNAVAILABLE` | Add `StashNativeCodeLink` (with CameraX and ZXing on Android) |
| Camera usage description missing (iOS) | `.missingCameraUsageDescription` | Add `NSCameraUsageDescription` |
| Camera permission removed from the manifest (Android) | `CAMERA_PERMISSION_NOT_DECLARED` | Keep the module's `CAMERA` permission in the merged manifest |
