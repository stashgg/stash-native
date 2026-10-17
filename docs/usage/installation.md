---
title: Package Installation
parent: Usage
nav_order: 1
description: Download Stash Native and add it to an iOS or Android app.
---

# Package Installation

Prebuilt packages are on [GitHub Releases](https://github.com/stashgg/stash-native/releases): `StashNative-<tag>.xcframework.zip` for iOS and `StashNative-<tag>.aar` for Android. iOS apps can also use Swift Package Manager.

## iOS

Requires iOS 15 or later and Xcode 27.1.

### Swift Package Manager

In Xcode, choose **File > Add Package Dependencies**, enter `https://github.com/stashgg/stash-native.git`, and add the `StashNative` library to your app target. In `Package.swift`:

```swift
.package(url: "https://github.com/stashgg/stash-native.git", from: "3.0.0"),
```

### XCFramework

Unzip `StashNative-<tag>.xcframework.zip`, add `StashNative.xcframework` to your app target, and set it to **Embed & Sign**.

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

    // Optional: QR Code Linking, all four
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

### Camera permission

The AAR declares the `CAMERA` permission for QR Code Linking. If your game does not use QR Code Linking, remove it:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.CAMERA" tools:node="remove" />
</manifest>
```
