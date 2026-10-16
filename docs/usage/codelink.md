---
title: CodeLink
parent: Usage
nav_order: 4
description: Scan Stash webshop QR codes in the native card to link accounts.
---

# CodeLink

![CodeLink scanners on iPhone and Android](https://raw.githubusercontent.com/stashgg/stash-native/main/.github/assets/codelink-devices-dark.png)

## Open

Opens a QR scanner in the native card. The first code in the frame shows a Connected confirmation, closes the card, and returns the raw payload once. Use the payload to link the player's webshop account.

iOS needs `NSCameraUsageDescription`. Android needs CameraX 1.4.2 and ZXing 3.5.3 ([Installation](installation.md#aar)). The scanner asks for camera access when it opens.

```swift
StashNativeCard.sharedInstance().codeLink(from: self, config: nil)
```

```java
StashNativeCard.getInstance().codeLink(activity, null);
```

## Configuration

Replaces or hides the scanner text. Empty values keep the defaults.

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

| Event | iOS | Android |
|---|---|---|
| Code scanned | `stashNativeCardDidScanQRCode(_:)` | `onQrCodeScanned(content)` |
| Camera error | `stashNativeCardCodeLinkDidEncounterError(_:)` | `onCodeLinkError(error)` |
| Closed without a scan | `stashNativeCardDidDismiss()` | `onDialogDismissed()` |

## Errors

Each error is reported once per scanner. The card stays open so the user can fix the problem or close it, except when Android lacks CameraX or ZXing.

| Cause | iOS `StashNativeCodeLinkError.Code` | Android `CodeLinkError` |
|---|---|---|
| Camera access denied | `.cameraPermissionDenied` | `CAMERA_PERMISSION_DENIED` |
| No camera | `.cameraUnavailable` | `CAMERA_UNAVAILABLE` |
| Camera setup failed | `.cameraConfigurationFailed` | `CAMERA_CONFIGURATION_FAILED` |
| CameraX or ZXing missing; the card closes | Not applicable | `CAMERA_CONFIGURATION_FAILED` |
| `NSCameraUsageDescription` missing | `.missingCameraUsageDescription` | Not applicable |
| `CAMERA` removed from the manifest | Not applicable | `CAMERA_PERMISSION_NOT_DECLARED` |

```swift
func stashNativeCardCodeLinkDidEncounterError(_ error: Error) {
    if (error as? StashNativeCodeLinkError)?.code == .cameraPermissionDenied {
        showCameraSettingsHint()
    }
}
```
