---
title: Overview
nav_order: 1
description: Install the Stash Native SDK and its optional modules on iOS and Android.
---

# Stash Native

## Package Installation

The SDK is a core package plus optional modules. Prebuilt packages are on [GitHub Releases](https://github.com/stashgg/stash-native/releases). Unity and Unreal Engine games use [stash-unity](https://github.com/stashgg/stash-unity) or [stash-unreal](https://github.com/stashgg/stash-unreal) instead; for other engines, see [Engine Wrappers](architecture/engine-wrappers.md).

| Package | Adds | Install |
|---|---|---|
| `StashNative` (core) | Checkout Card, In-Game Browser, callbacks | Always |
| `StashNativeCodeLink` (module) | QR scanner | Only for [QR Code Linking](usage/codelink.md) |

### iOS

Requires iOS 15 or later and Xcode 27.1. In Xcode, choose **File > Add Package Dependencies**, enter `https://github.com/stashgg/stash-native.git`, and add the `StashNative` library. In `Package.swift`:

```swift
.package(url: "https://github.com/stashgg/stash-native.git", from: "3.0.0"),
// Target dependencies:
.product(name: "StashNative", package: "stash-native"),
```

Without Swift Package Manager, add `StashNative.xcframework` from `StashNative-<tag>.xcframework.zip` and set it to **Embed & Sign**.

```swift
import StashNative
```

### Android

Requires API 21 or later. Copy the AAR into `app/libs/` and add it with its dependencies. The AAR includes its manifest entries and R8 rules.

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

```java
import com.stash.stashnative.StashNative;
```

### QR Code Linking module

| Platform | Add |
|---|---|
| iOS | The `StashNativeCodeLink` library or `StashNativeCodeLink.xcframework` (**Embed & Sign**), and `NSCameraUsageDescription` in Info.plist |
| Android | `StashNativeCodeLink-<tag>.aar`, CameraX, and ZXing, as in the Gradle block above. Its manifest adds the camera permission. Source-module builds use `:stashnative-codelink`. |

No import is needed. Games without the module need no camera permission or usage description. Custom iOS builds that link static archives directly must pass `-ObjC` to keep the scanner.

CameraX 1.4.2 needs Android Gradle Plugin 8.x. On AGP 7.x, such as Unity 2022.3 LTS, use CameraX **1.3.4** for the three `androidx.camera` libraries instead; AGP 7.4's dexer fails on 1.4.x. The module uses no CameraX API newer than 1.3.0, so 1.3.4 works.

### SDK version

Check the installed version with `StashNative.sdkVersion()` (iOS) or `StashNative.getVersion()` (Android). Include it when you contact [developers@stash.gg](mailto:developers@stash.gg).
