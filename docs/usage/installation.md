---
title: Installation
parent: Usage
nav_order: 1
description: Add Stash Native with Swift Package Manager, the XCFramework, or the Android AAR.
---

# Installation

Prebuilt binaries are on [GitHub Releases](https://github.com/stashgg/stash-native/releases): `StashNative-<tag>.xcframework.zip` and `StashNative-<tag>.aar`.

## iOS

Requires iOS 15. Build with Xcode 27.1. iPhone Duo layouts need the app linked against the iOS 27.1 SDK.

### Swift Package Manager

```swift
.package(url: "https://github.com/stashgg/stash-native.git", from: "3.0.0"),
```

Add the `StashNative` product to your target, then `import StashNative`.

### XCFramework

Unzip the release, add `StashNative.xcframework` to your target, and set it to **Embed & Sign**.

### Info.plist

CodeLink needs `NSCameraUsageDescription`. Checkout and the browser need no keys.

## Android

Requires API 21.

### AAR

Copy the AAR to `app/libs/` and declare its dependencies. A file-based AAR brings none with it.

```groovy
dependencies {
    implementation files('libs/StashNative-<tag>.aar')

    implementation 'androidx.core:core:1.12.0'
    implementation 'androidx.webkit:webkit:1.11.0'
    implementation 'androidx.window:window:1.4.0'
    implementation 'androidx.window:window-java:1.4.0'

    // Optional: Chrome Custom Tabs. Without it, the system browser opens.
    implementation 'androidx.browser:browser:1.7.0'

    // Optional: CodeLink. Add all four or none.
    implementation 'androidx.camera:camera-camera2:1.4.2'
    implementation 'androidx.camera:camera-lifecycle:1.4.2'
    implementation 'androidx.camera:camera-view:1.4.2'
    implementation 'com.google.zxing:core:3.5.3'
}
```

Stay on WindowManager 1.4.x. Version 1.5 requires API 23.

### Source module

The `stashnative` module includes Core, WebKit, and WindowManager. Add Browser, CameraX, and ZXing yourself if you use them.

### Manifest

The SDK merges `INTERNET`, `CAMERA`, the keep-alive foreground service, a signature permission for internal broadcasts, and two non-exported activities. Without CodeLink you can remove `CAMERA`:

```xml
<uses-permission android:name="android.permission.CAMERA" tools:node="remove" />
```

Do not add `android:process` to the SDK activities. Checkout must run in the app process.

### R8

The AAR ships its own keep rules. Add none.
