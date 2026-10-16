---
title: CodeLink
parent: Usage
nav_order: 4
description: Link a player's Stash webshop account by scanning the webshop's QR code in the game.
---

# CodeLink

CodeLink lets players link their Stash webshop account to the game by scanning the QR code the webshop shows. The scanner opens in the same native card as checkout. The first QR code in the frame shows a Connected confirmation, closes the card, and returns the code's content to the game. Use that content to link the account.

![CodeLink scanners on iPhone and Android](https://raw.githubusercontent.com/stashgg/stash-native/main/.github/assets/codelink-devices-dark.png)

## Requirements

| Platform | Requirement |
|---|---|
| iOS | `NSCameraUsageDescription` in Info.plist. iOS shows this text when the scanner asks for the camera. |
| Android | CameraX 1.4.2 and ZXing 3.5.3 ([Installation](installation.md#aar)) |

The scanner asks for camera access the first time it opens. Decoding happens on the device, and no images are saved.

## Open the scanner

```swift
StashNativeCard.sharedInstance().codeLink(from: self, config: nil)
```

```java
StashNativeCard.getInstance().codeLink(activity, null);
```

The scanner follows the game's orientation.

## Configuration

Translate the scanner text to the game's language, or hide the info callout to give the camera more room. `nil` or empty values keep the defaults.

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
StashNativeCard.sharedInstance().codeLink(from: self, config: config)
```

```java
StashNativeCard.CodeLinkConfig config = new StashNativeCard.CodeLinkConfig();
config.headerText = "Escanear código QR";
config.showCallout = false;
StashNativeCard.getInstance().codeLink(activity, config);
```

## Callbacks

| Event | iOS | Android | What to do |
|---|---|---|---|
| Code scanned | `stashNativeCardDidScanQRCode(_:)` | `onQrCodeScanned(content)` | Use the content to link the account. The card has already closed. |
| Camera error | `stashNativeCardCodeLinkDidEncounterError(_:)` | `onCodeLinkError(error)` | Log it or guide the player. See [Errors](#errors). |
| Closed without a scan | `stashNativeCardDidDismiss()` | `onDialogDismissed()` | Resume the game |

The scan callback fires once per scanner.

## Errors

After an error the card stays open, so the player can grant camera access in Settings and return to scanning, or close the card. Each error is reported once per scanner.

| Cause | iOS `StashNativeCodeLinkError.Code` | Android `CodeLinkError` | Fix |
|---|---|---|---|
| Camera access denied | `.cameraPermissionDenied` | `CAMERA_PERMISSION_DENIED` | The card offers a Settings button |
| No camera available | `.cameraUnavailable` | `CAMERA_UNAVAILABLE` | Offer another way to link |
| Camera setup failed | `.cameraConfigurationFailed` | `CAMERA_CONFIGURATION_FAILED` | Retry later |
| CameraX or ZXing missing | Not applicable | `CAMERA_CONFIGURATION_FAILED` | Add the dependencies. The card closes. |
| Usage description missing | `.missingCameraUsageDescription` | Not applicable | Add `NSCameraUsageDescription` |
| Camera permission removed from the manifest | Not applicable | `CAMERA_PERMISSION_NOT_DECLARED` | Keep `CAMERA` in the manifest |

```swift
func stashNativeCardCodeLinkDidEncounterError(_ error: Error) {
    if (error as? StashNativeCodeLinkError)?.code == .cameraPermissionDenied {
        // The card already shows a Settings button; log it for analytics.
    }
}
```

```java
@Override
public void onCodeLinkError(StashNativeCard.CodeLinkError error) {
    if (error == StashNativeCard.CodeLinkError.CAMERA_PERMISSION_DENIED) {
        // The card already shows a Settings button; log it for analytics.
    }
}
```
