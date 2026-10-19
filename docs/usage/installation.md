---
title: Package Installation
parent: Usage
nav_order: 1
description: Download Stash Native and add it to an iOS or Android app.
---

# Package Installation

| Package | Adds | Install |
|---|---|---|
| `StashNative` | Checkout Card, In-Game Browser, callbacks | Always |
| `StashNativeCodeLink` | QR scanner | Only for [QR Code Linking](codelink.md) |

Download prebuilt packages from [GitHub Releases](https://github.com/stashgg/stash-native/releases), or add the iOS packages with Swift Package Manager. The core package has no camera code, so games without QR Code Linking need no camera permission or Info.plist entry.

## iOS

Requires iOS 15 or later and Xcode 27.1.

### Swift Package Manager

In Xcode, choose **File > Add Package Dependencies**, enter `https://github.com/stashgg/stash-native.git`, and add the `StashNative` library to your app target. In `Package.swift`:

```swift
.package(url: "https://github.com/stashgg/stash-native.git", from: "3.0.0"),
// In your target's dependencies:
.product(name: "StashNative", package: "stash-native"),
```

### XCFramework

Unzip `StashNative-<tag>.xcframework.zip`, add `StashNative.xcframework` to your app target, and set it to **Embed & Sign**.

### Import

```swift
import StashNative
```

## Android

Requires API 21 or later. Copy the AAR into `app/libs/` and add it with its dependencies:

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

    // Optional: QR Code Linking
    implementation files('libs/StashNativeCodeLink-<tag>.aar')
    implementation 'androidx.camera:camera-camera2:1.4.2'
    implementation 'androidx.camera:camera-lifecycle:1.4.2'
    implementation 'androidx.camera:camera-view:1.4.2'
    implementation 'com.google.zxing:core:3.5.3'
}
```

The AAR brings its own manifest entries and R8 rules.

```java
import com.stash.stashnative.StashNative;
```

## QR Code Linking

Add `StashNativeCodeLink` next to the core package. The SDK finds it at runtime, so no extra import is needed.

| Platform | Add |
|---|---|
| iOS | The `StashNativeCodeLink` library, or `StashNativeCodeLink.xcframework` set to **Embed & Sign**, and `NSCameraUsageDescription` in Info.plist |
| Android | `StashNativeCodeLink-<tag>.aar` with CameraX and ZXing, as in the Gradle block above. Its manifest adds the camera permission. Source-module builds depend on `:stashnative-codelink`. |

Custom iOS builds that link the SDK as plain static archives must pass `-ObjC`, so the linker keeps the scanner.
