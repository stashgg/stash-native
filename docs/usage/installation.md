---
title: Package Installation
parent: Usage
nav_order: 1
description: Download Stash Native and add it to an iOS or Android app.
---

# Package Installation

Prebuilt packages are on [GitHub Releases](https://github.com/stashgg/stash-native/releases): `StashNative-<tag>.xcframework.zip` for iOS and `StashNative-<tag>.aar` for Android. The QR scanner ships separately as `StashNativeCodeLink-<tag>.xcframework.zip` and `StashNativeCodeLink-<tag>.aar`; add it only if your game uses [QR Code Linking](codelink.md). iOS apps can also use Swift Package Manager.

## iOS

Requires iOS 15 or later and Xcode 27.1.

### Swift Package Manager

In Xcode, choose **File > Add Package Dependencies**, enter `https://github.com/stashgg/stash-native.git`, and add the `StashNative` library to your app target. Add the `StashNativeCodeLink` library as well only if you use QR Code Linking. In `Package.swift`:

```swift
.package(url: "https://github.com/stashgg/stash-native.git", from: "3.0.0"),
```

### XCFramework

Unzip `StashNative-<tag>.xcframework.zip`, add `StashNative.xcframework` to your app target, and set it to **Embed & Sign**. For QR Code Linking, do the same with `StashNativeCodeLink.xcframework`.

### QR Code Linking (opt in)

`StashNative` contains no camera code and no AVFoundation references, so apps that do not scan need no camera purpose string. Apps that link `StashNativeCodeLink` add `NSCameraUsageDescription` to their Info.plist; no Swift import is needed, the core finds the module at runtime. Calling `openScanner` without the module reports `StashNativeScannerError.scannerUnavailable` and presents nothing. Xcode's package integration and the XCFramework keep the scanner class automatically; a custom pipeline that links the SDK as plain static archives must pass `-ObjC` so the linker keeps it.

### Import

```swift
import StashNative
```

## Android

Requires API 21 or later. Copy the AAR into `app/libs/` and declare it with its dependencies:

```groovy
dependencies {
    implementation files('libs/StashNative-<tag>.aar')

    // Required
    implementation 'androidx.core:core:1.12.0'
    implementation 'androidx.webkit:webkit:1.11.0'
    implementation 'androidx.window:window:1.4.0'
    implementation 'androidx.window:window-java:1.4.0'

    // Optional: In-Game Browser in Chrome Custom Tabs
    implementation 'androidx.browser:browser:1.7.0'

    // Optional: QR Code Linking, the scanner module and its four libraries
    implementation files('libs/StashNativeCodeLink-<tag>.aar')
    implementation 'androidx.camera:camera-camera2:1.4.2'
    implementation 'androidx.camera:camera-lifecycle:1.4.2'
    implementation 'androidx.camera:camera-view:1.4.2'
    implementation 'com.google.zxing:core:3.5.3'
}
```

The AAR brings its own manifest entries and R8 rules.

### Import

```java
import com.stash.stashnative.StashNative;
```

### QR Code Linking (opt in)

`StashNative` declares no camera permission and contains no camera code. If your game uses [QR Code Linking](codelink.md), add `StashNativeCodeLink` and its four libraries as shown above; its manifest declares `android.permission.CAMERA` and the optional camera features for you. Source-module integrations depend on `:stashnative-codelink` instead of the AAR.

Without the module, `openScanner` reports `ScannerError.SCANNER_UNAVAILABLE` and closes; if a host removes the permission with `tools:node="remove"`, the scanner stays open with `CAMERA_PERMISSION_NOT_DECLARED`. Games that do not use QR Code Linking add nothing.
