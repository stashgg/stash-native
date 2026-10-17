---
title: QR Code Linking
parent: Usage
nav_order: 4
description: Link a player's Stash webshop account by scanning the webshop's QR code in the game.
---

# QR Code Linking

QR code linking lets players link their Stash webshop account to the game by scanning the QR code that the webshop shows. The scanner opens in the native card. When it reads a code, it shows a confirmation, closes, and returns the code's content to the game.

![QR code scanners on iPhone and Android](https://raw.githubusercontent.com/stashgg/stash-native/main/.github/assets/codelink-devices-dark.png)

## Requirements

| Platform | Requirement |
|---|---|
| iOS | `NSCameraUsageDescription` in Info.plist. iOS shows this text when the scanner asks for the camera. |
| Android | CameraX and ZXing from [Package Installation](installation.md#android) |

The scanner asks for camera access the first time it opens. Decoding runs on the device, and no images are saved.

## Open the scanner

```swift
StashNative.sharedInstance().codeLink(from: self, config: nil)
```

```java
StashNative.getInstance().codeLink(activity, null);
```

The scanner follows the game's orientation. `dismiss()` closes it from code.

## Configuration

Pass a `StashNativeCodeLinkConfig` (iOS) or `StashNative.CodeLinkConfig` (Android) to translate the scanner text or hide the info callout. `nil` or empty values keep the defaults.

| Property | Default |
|---|---|
| `headerText` | Scan QR code |
| `calloutTitle` | Scan the webshop code |
| `calloutSubtitle` | Keep the QR code centered inside the frame. |
| `cameraUnavailableText` | Camera unavailable |
| `connectedText` | Connected |
| `showCallout` | `true` |

```swift
let config = StashNativeCodeLinkConfig()
config.headerText = "Escanear código QR"
config.showCallout = false
StashNative.sharedInstance().codeLink(from: self, config: config)
```

```java
StashNative.CodeLinkConfig config = new StashNative.CodeLinkConfig();
config.headerText = "Escanear código QR";
config.showCallout = false;
StashNative.getInstance().codeLink(activity, config);
```

## Callbacks

See [QR Code Linking callbacks](callbacks.md#qr-code-linking) for the scanned content, dismissal, and camera errors.
