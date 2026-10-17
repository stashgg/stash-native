---
title: Installation
parent: Usage
nav_order: 1
description: Add Stash Native with Swift Package Manager, the XCFramework, or the Android AAR.
---

# Installation

Prebuilt binaries are on [GitHub Releases](https://github.com/stashgg/stash-native/releases): `StashNative-<tag>.xcframework.zip` for iOS and `StashNative-<tag>.aar` for Android.

## iOS

Requires iOS 15 or later. Build with Xcode 27.1. To get the iPhone Duo layouts, link your app against the iOS 27.1 SDK; the SDK alone cannot opt an older app build in.

### Swift Package Manager

In Xcode, choose **File > Add Package Dependencies**, enter the repository URL, and add the `StashNative` library to your app target. In `Package.swift`:

```swift
.package(url: "https://github.com/stashgg/stash-native.git", from: "3.0.0"),
```

### XCFramework

Download and unzip `StashNative-<tag>.xcframework.zip`, add `StashNative.xcframework` to your target, and set it to **Embed & Sign**. The framework is dynamic, so the app fails to launch if it is not embedded.

### Import

```swift
import StashNative
```

```objc
#import <StashNative/StashNative.h>
```

### Info.plist

Add `NSCameraUsageDescription` if you use [CodeLink](codelink.md). iOS shows this text when the scanner asks for camera access. Checkout and the browser need no Info.plist keys.

## Android

Requires API 21 or later.

### AAR

Copy the AAR into `app/libs/` and declare its dependencies. A file-based AAR carries no dependency information, so Gradle does not add them for you.

```groovy
dependencies {
    implementation files('libs/StashNative-<tag>.aar')

    // Required
    implementation 'androidx.core:core:1.12.0'
    implementation 'androidx.webkit:webkit:1.11.0'
    implementation 'androidx.window:window:1.4.0'
    implementation 'androidx.window:window-java:1.4.0'

    // Optional: open browser checkout in Chrome Custom Tabs.
    implementation 'androidx.browser:browser:1.7.0'

    // Optional: CodeLink QR scanning. Add all four or none.
    implementation 'androidx.camera:camera-camera2:1.4.2'
    implementation 'androidx.camera:camera-lifecycle:1.4.2'
    implementation 'androidx.camera:camera-view:1.4.2'
    implementation 'com.google.zxing:core:3.5.3'
}
```

| Group | Without it |
|---|---|
| Browser | `openBrowser` opens the system browser instead of Custom Tabs, which takes the player out of your app |
| CameraX and ZXing | CodeLink closes and reports `SCANNER_UNAVAILABLE`. Checkout and the browser keep working. |

Stay on WindowManager 1.4.x while you support API 21; version 1.5 requires API 23.

### Source module

If you include the `stashnative` Gradle module as source, it brings Core, WebKit, and WindowManager. Add Browser, CameraX, and ZXing yourself when you use those features.

### Import

```java
import com.stash.stashnative.StashNative;
```

### Manifest

The SDK adds these entries to your merged manifest:

| Entry | Used for |
|---|---|
| `INTERNET` | Loading checkout |
| `CAMERA` | CodeLink only. The permission prompt appears only when the scanner opens. |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SHORT_SERVICE` | The optional [keep-alive service](browser.md#keep-alive-service-android) |
| `<your.package>.permission.STASH_NATIVE_INTERNAL` | SDK events inside your app. Granted automatically, with no prompt. |

If you never open CodeLink, remove the camera permission so app stores do not list it:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.CAMERA" tools:node="remove" />
</manifest>
```

Do not move the SDK's activities into another process with `android:process`. Checkout must run in your app's process.

### Shrinking

The AAR ships its own R8 and ProGuard rules. You do not need to add keep rules for the SDK.

## Migrating from 2.x

Update the SDK entry point and callback names in your app or engine wrapper:

| Previous name | Current name |
|---|---|
| `StashNativeCard` on both platforms | `StashNative` |
| `StashNativeCardDelegate` on iOS | `StashNativeDelegate` |
| `stashNativeCard...` callbacks on iOS | `stashNative...`, for example `stashNativeDidDismissCard()` |
| `<StashNative/StashNativeCard.h>` on iOS | `<StashNative/StashNative.h>` |
| `StashNativeCard.StashNativeCardListener` on Android | `StashNative.StashNativeListener` |
| `StashNativeCard.StashNativeCardListenerAdapter` on Android | `StashNative.StashNativeListenerAdapter` |

The old names are removed. Card configuration remains `StashNativeCardConfig` on iOS and `StashNative.CardConfig` on Android. The `StashNative` module, Android package, and `window.stash_sdk` bridge names stay the same.

Replace generic dismissal and browser-close callbacks with the three no-argument callbacks below. Keep one shared listener or delegate.

| Event | iOS | Android |
|---|---|---|
| Card dismissed | `stashNativeDidDismissCard()` | `onCardDismissed()` |
| Scan dismissed | `stashNativeDidDismissScan()` | `onScanDismissed()` |
| Browser dismissed | `stashNativeDidDismissBrowser()` | `onBrowserDismissed()` |

Browser dismissal covers both `openBrowser` and checkout's payment handoff. iOS payment success uses only `stashNativeDidCompletePayment(withOrder:)`; remove the old no-argument implementation. Safari closing sends only browser dismissed. Register, read, replace, and clear the receiver on main; opens remain callable from any thread. See [Callbacks](callbacks.md) for ownership and event order.

Replace `openModal` with `openCard`, pass the presenting activity or view controller to open calls, and replace phone/tablet sizing ratios with [card dimensions](checkout-card.md#configuration). Use `orientationPreference` instead of `forcePortrait`. See the [3.0 breaking changes](https://github.com/stashgg/stash-native/blob/main/CHANGELOG.md#300---unreleased) for the remaining removals.
