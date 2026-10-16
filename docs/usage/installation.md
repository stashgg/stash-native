---
title: Installation
parent: Usage reference
nav_order: 1
description: Add Stash Native to an iOS app with Swift Package Manager or the XCFramework, and to an Android app with the AAR.
---

# Installation

Prebuilt binaries are attached to [GitHub Releases](https://github.com/stashgg/stash-native/releases): `StashNative-<tag>.aar` and `StashNative-<tag>.xcframework.zip`.

## iOS

Requirements: iOS 15 or later. Build release apps with Xcode 27.1 and the iOS 27.1 SDK; iPhone Duo layout adoption requires the host app itself to be linked against SDK 27.1. See [Compatibility](../compatibility.md#ios).

### Swift Package Manager

In Xcode, choose **File > Add Package Dependencies**, enter `https://github.com/stashgg/stash-native.git`, and add the `StashNative` library to your app target.

In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/stashgg/stash-native.git", from: "3.0.0"),
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "StashNative", package: "stash-native"),
    ]),
]
```

### XCFramework

1. Download `StashNative-<tag>.xcframework.zip` from the release and unzip it.
2. Drag `StashNative.xcframework` into the Xcode project.
3. Under **Frameworks, Libraries, and Embedded Content**, set it to **Embed & Sign**.

The framework depends only on system frameworks: UIKit, WebKit, SafariServices, AVFoundation, and QuartzCore.

### Import

```swift
import StashNative
```

```objc
#import <StashNative/StashNative.h>
```

### Info.plist

| Key | Required when |
|---|---|
| `NSCameraUsageDescription` | The app uses CodeLink. Without it, CodeLink reports `StashNativeCodeLinkErrorMissingCameraUsageDescription` and never requests camera access. |

Checkout and browser need no Info.plist entries.

## Android

Requirements: API 21 or later. The SDK is built with JDK 17 and compile SDK 34.

### AAR

1. Download `StashNative-<tag>.aar` from the release and copy it to `app/libs/`.
2. Declare the AAR and its base dependencies. A plain AAR file carries no dependency metadata, so Gradle does not add them for you.

```groovy
dependencies {
    implementation files('libs/StashNative-<tag>.aar')

    // Required
    implementation 'androidx.core:core:1.12.0'
    implementation 'androidx.webkit:webkit:1.11.0'
    implementation 'androidx.window:window:1.4.0'
    implementation 'androidx.window:window-java:1.4.0'

    // Optional: Chrome Custom Tabs for openBrowser and external payment.
    // Without it, the SDK opens the system browser with ACTION_VIEW.
    implementation 'androidx.browser:browser:1.7.0'

    // Optional: CodeLink. Add all four or none.
    implementation 'androidx.camera:camera-camera2:1.4.2'
    implementation 'androidx.camera:camera-lifecycle:1.4.2'
    implementation 'androidx.camera:camera-view:1.4.2'
    implementation 'com.google.zxing:core:3.5.3'
}
```

| Group | Required | Without it |
|---|---|---|
| Core, WebKit, WindowManager and its Java adapter | Yes | Unsupported configuration |
| Browser | No | `openBrowser` and external payment use the system browser. `onBrowserClosed` uses host lifecycle detection. |
| CameraX and ZXing | Only for CodeLink | `codeLink` reports `CAMERA_CONFIGURATION_FAILED` and closes. Checkout and browser work. |

Keep WindowManager on 1.4.x while supporting API 21. WindowManager 1.5 raises its minimum SDK to 23.

### Source module

When the `stashnative` Gradle module is included as source, Core, WebKit, and WindowManager come with it. Browser, CameraX, and ZXing are `compileOnly` in the SDK, so add them to the app module when you use those features.

### Manifest

The SDK manifest merges these entries into the app:

| Entry | Purpose |
|---|---|
| `android.permission.INTERNET` | Checkout |
| `android.permission.CAMERA`, optional `android.hardware.camera` and `android.hardware.camera.autofocus` features | CodeLink only. Requested at runtime only when the scanner opens. |
| `android.permission.FOREGROUND_SERVICE`, `android.permission.FOREGROUND_SERVICE_SHORT_SERVICE` | Optional keep-alive service |
| `<applicationId>.permission.STASH_NATIVE_INTERNAL` (signature) | Protects internal broadcasts on API 21 to 32 |
| `<queries>` for `android.support.customtabs.action.CustomTabsService` | Custom Tabs provider discovery on API 30+ |
| `StashCheckoutActivity`, `StashNativeBrowserProxyActivity` | Non-exported activities in the host process |
| `StashKeepAliveService` | Non-exported `shortService` foreground service |

Apps that never open CodeLink can remove the camera permission:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.CAMERA" tools:node="remove" />
</manifest>
```

With the permission removed, `codeLink` reports `CAMERA_PERMISSION_NOT_DECLARED`.

Do not add `android:process` to the SDK activities. The SDK manifest removes it with `tools:remove`; checkout must share the host process.

### Shrinking

The AAR includes consumer R8 rules for its public API, JavaScript interface methods, and reflection entry points. No extra keep rules are needed. Test a minified release build of the host app, with and without the optional dependency groups you ship.

### Import

```java
import com.stash.stashnative.StashNativeCard;
```
