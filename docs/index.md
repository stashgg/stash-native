---
title: Overview
nav_order: 1
description: Stash Native SDK features, modules, engine bindings, and installation for iOS and Android.
---

# Stash Native SDK

Stash Native SDK integrates Stash Pay checkout and Stash webshop features into iOS and Android games and apps. It provides a native checkout card, an in-game browser for checkout and webshop access, and QR code scanning for account linking.

The SDK handles client-side presentation and callbacks for these direct-to-consumer (D2C) flows. Server-to-server communication, including checkout link generation, belongs on your backend.

## Modules

The SDK separates optional features from the core package to reduce its impact on your app's size and dependencies. Install the core and add only the modules your integration needs. In the future, all features will ship as modules.

| Package | Features |
|---|---|
| `StashNative` | Checkout Card, In-Game Browser, and shared callbacks |
| `StashNativeCodeLink` | QR code scanner for account linking |

## Game Engine Bindings

Stash Native fits any app architecture, with SDK updates automatically carried through to its engine bindings. Download the Unity or Unreal bindings from the repositories below.

| | Engine | Support | Package |
|---|---|---|---|
| <img src="{{ '/assets/images/stash_unity_rounded.png' | relative_url }}" alt="" width="32" height="32"> | Unity | 2022.3 and up | [stash-unity](https://github.com/stashgg/stash-unity) |
| <img src="{{ '/assets/images/stash_unreal_rounded.png' | relative_url }}" alt="" width="32" height="32"> | Unreal Engine | 5.0 and up | [stash-unreal](https://github.com/stashgg/stash-unreal) |
{: .engine-bindings }

If you use a custom engine, follow the [Engine Wrappers](architecture/engine-wrappers.md) guide to create your own binding.

## Package Installation

Install the native packages as described below. Prebuilt XCFrameworks and AARs are available on [GitHub Releases](https://github.com/stashgg/stash-native/releases). Replace `<tag>` in the filenames with the release tag you downloaded.

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

    implementation 'androidx.core:core:1.12.0'
    implementation 'androidx.webkit:webkit:1.11.0'
    implementation 'androidx.window:window:1.4.0'
    implementation 'androidx.window:window-java:1.4.0'
}
```

For the In-Game Browser on Android, we strongly recommend using Chrome Custom Tabs. Add this optional dependency to the same block:

```groovy
implementation 'androidx.browser:browser:1.7.0'
```

```java
import com.stash.stashnative.StashNative;
```

### Test Call

To check that the package is correctly included, call `StashNative.getVersion()` in your app's code on either platform. If you get the package version back, you're ready to use Stash Native in your app.

## Feature Guides

| Guide | Use it to |
|---|---|
| [Checkout Card](usage/checkout-card.md) | Show Stash Pay checkout in a native card with `openCard`. |
| [In-Game Browser](usage/browser.md) | Open checkout or webshop links with `openBrowser`. |
| [QR Code Linking](usage/codelink.md) | Scan a webshop QR code for account linking with `openScanner`. |
| [Setting Callbacks](usage/callbacks.md) | Handle payment results, dismissal, scanner results, and errors. |

See [Sample Apps](usage/sample-apps.md) for working iOS and Android integrations.
