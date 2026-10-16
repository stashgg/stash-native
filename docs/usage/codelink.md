---
title: CodeLink
parent: Usage reference
nav_order: 4
description: Scan Stash webshop QR codes in the native card for account linking. Configuration, permissions, callbacks, and errors.
---

# CodeLink

`codeLink` opens a camera QR scanner inside the responsive card. The first QR code found inside the scan frame shows a Connected confirmation, closes the card, and returns the raw payload to the app. The SDK opens no URL and sends no payment callback. Use the payload to link the player's account to the webshop.

![CodeLink scanners on iPhone and Android](https://raw.githubusercontent.com/stashgg/stash-native/main/.github/assets/codelink-devices-dark.png)

## Requirements

| Platform | Requirement |
|---|---|
| iOS | `NSCameraUsageDescription` in the app's Info.plist. Camera access is requested when the scanner opens. The scanner uses no microphone and saves no images. |
| Android | CameraX (`camera-camera2`, `camera-lifecycle`, `camera-view` 1.4.2) and ZXing Core 3.5.3. See [Installation](installation.md#aar). `CAMERA` permission in the merged manifest; the SDK declares it and requests it when the scanner opens. |

## Open the scanner

Swift:

```swift
StashNativeCard.sharedInstance().codeLink(from: self, config: nil)
```

Objective-C:

```objc
[[StashNativeCard sharedInstance] codeLinkFromViewController:self config:nil];
```

Java:

```java
StashNativeCard.getInstance().codeLink(activity, null);
```

CodeLink always follows the host orientation, including in landscape-only games. It shares the single presentation slot with the checkout card.

## Configuration

`StashNativeCodeLinkConfig` on iOS, `StashNativeCard.CodeLinkConfig` on Android. Use it to translate or customize the scanner text. `nil`, `null`, or empty strings keep the built-in text; on Android the built-in text includes the SDK's resource translations.

| Property | Default |
|---|---|
| `headerText` | Scan QR code |
| `calloutTitle` | Scan the webshop code |
| `calloutSubtitle` | Keep the QR code centered inside the frame. |
| `cameraUnavailableText` | Camera unavailable |
| `connectedText` | Connected |
| `showCallout` | `true` |

`showCallout = false` removes the callout from layout and accessibility and gives its space to the scan frame. The camera's region of interest follows the resulting frame, including after rotation and resizing. The unavailable status has no subtitle. VoiceOver and TalkBack announce `connectedText` with the confirmation.

The config is copied when `codeLink` is called. It does not change orientation, camera access, the confirmation, or callbacks.

## Callbacks

| Event | iOS | Android |
|---|---|---|
| QR code scanned | `stashNativeCardDidScanQRCode(_:)` | `onQrCodeScanned(String content)` |
| Camera or setup error | `stashNativeCardCodeLinkDidEncounterError(_:)` | `onCodeLinkError(CodeLinkError error)` |
| Closed without a scan | `stashNativeCardDidDismiss()` | `onDialogDismissed()` |

- The scan callback runs once, after the card has closed. It carries the unmodified QR payload. No dismissal callback accompanies it.
- User dismissal is locked during the Connected confirmation. Calling `dismiss()` during it reports a dismissal and cancels the scan callback. `resetPresentationState()` is silent.
- The error callback runs at most once per scanner session.
- On Android, `onQrCodeScanned` and `onCodeLinkError` are default interface methods, so existing listeners compile unchanged.

## Errors

The card stays open after a camera error so the user can close it, or grant access in Settings and return to scanning. The exception is a missing Android dependency, which closes the card.

| Condition | iOS `StashNativeCodeLinkError` | Android `CodeLinkError` | Card |
|---|---|---|---|
| Camera access denied or restricted | `CameraPermissionDenied` (1) | `CAMERA_PERMISSION_DENIED` | Stays open, shows a Settings button |
| No usable camera | `CameraUnavailable` (2) | `CAMERA_UNAVAILABLE` | Stays open, shows `cameraUnavailableText` |
| Capture setup failed | `CameraConfigurationFailed` (3) | `CAMERA_CONFIGURATION_FAILED` | Stays open |
| CameraX or ZXing missing or incompatible | Not applicable | `CAMERA_CONFIGURATION_FAILED` | Closes without a dismissal callback |
| Info.plist lacks `NSCameraUsageDescription` | `MissingCameraUsageDescription` (4) | Not applicable | Stays open, camera never requested |
| Merged manifest lacks `CAMERA` | Not applicable | `CAMERA_PERMISSION_NOT_DECLARED` | Stays open |

iOS errors are `NSError` values in `StashNativeCodeLinkErrorDomain` (`"gg.stash.native.CodeLink"`) with a localized description.

Swift:

```swift
func stashNativeCardCodeLinkDidEncounterError(_ error: Error) {
    guard let codeLinkError = error as? StashNativeCodeLinkError else { return }
    switch codeLinkError.code {
    case .cameraPermissionDenied: showCameraSettingsHint()
    case .missingCameraUsageDescription: assertionFailure("Add NSCameraUsageDescription")
    default: break
    }
}
```

Java:

```java
@Override
public void onCodeLinkError(StashNativeCard.CodeLinkError error) {
    if (error == StashNativeCard.CodeLinkError.CAMERA_CONFIGURATION_FAILED) {
        // On a missing dependency the scanner has already closed.
    }
}
```

## Scanning details

| | iOS | Android |
|---|---|---|
| Detection | AVFoundation metadata output, QR type only | ZXing on the luminance plane of the scan frame region |
| Region | Scan frame only | Scan frame only; QR corners must lie inside it |
| Network | None | None. No Play Services or model download. |

On Android, the confirmation pauses while the activity is in the background and respects disabled animations and accessibility timing settings.
