---
title: QR Code Linking
parent: Usage
nav_order: 4
description: Link a player's Stash webshop account by scanning the webshop's QR code in the game.
---

# QR Code Linking

{: .warning }
QR Code Linking needs the separate `StashNativeCodeLink` module, which the core SDK does not include. Add it as shown in Package Installation for [iOS](installation.md#qr-code-linking-opt-in) and [Android](installation.md#qr-code-linking-opt-in-1). Without the module, `openScanner` reports `scannerUnavailable` (iOS) or `SCANNER_UNAVAILABLE` (Android) and presents nothing.

QR code linking lets players link their Stash webshop account to the game by scanning the QR code that the webshop shows. The scanner opens in the native card. When it reads a code, it shows a confirmation, closes, and returns the code's content to the game.

![QR code scanners on iPhone and Android](../assets/images/codelink-devices-dark.png)

## Requirements

| Platform | Requirement |
|---|---|
| iOS | The `StashNativeCodeLink` library or XCFramework, plus `NSCameraUsageDescription` in Info.plist. iOS shows this text when the scanner asks for the camera. |
| Android | The `StashNativeCodeLink` AAR or `:stashnative-codelink` module with CameraX and ZXing, from [Package Installation](installation.md#android). Its manifest declares the camera permission. |

The scanner asks for camera access the first time it opens. Decoding runs on the device, and no images are saved.

## Open the scanner

```swift
StashNative.sharedInstance().openScanner(from: self, config: nil)
```

```java
StashNative.getInstance().openScanner(activity, null);
```

The scanner follows the game's orientation. `dismiss()` closes it from code.

## Configuration

Pass a `StashNativeScannerConfig` (iOS) or `StashNative.ScannerConfig` (Android) to translate the scanner text or hide the info callout. `nil` or empty values keep the defaults.

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

See [QR Code Linking callbacks](callbacks.md#qr-code-linking) for the scanned content, dismissal, and camera errors.
