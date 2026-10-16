---
title: Overview
nav_order: 1
description: Stash Native presents Stash Pay checkout and Stash webshop pages in native iOS and Android apps.
---

# Stash Native

Stash Native presents Stash Pay checkout and Stash webshop pages inside native iOS and Android apps and games. It hosts the page in a native card or the platform browser, reports payment and lifecycle events to the app, and scans webshop QR codes for account linking.

These pages document the `main` branch, version 3.0.0, which is not released yet. The latest release is [2.3.1](https://github.com/stashgg/stash-native/releases/tag/2.3.1). For web pages and web apps, use [stash-web](https://github.com/stashgg/stash-web) instead.

## Presentations

| Presentation | API | Native surface | Host callbacks |
|---|---|---|---|
| Checkout card | `openCard` | iOS: `WKWebView` in a `UISheetPresentationController` sheet. Android: `WebView` in a same-process activity. | Payment result, dismissal, page loaded, network error, external payment |
| Browser | `openBrowser` | iOS: `SFSafariViewController`. Android: Chrome Custom Tabs, or the system browser when `androidx.browser` is absent. | Browser closed |
| CodeLink | `codeLink` | Camera QR scanner in the checkout card | QR payload, scanner error, dismissal |

Only the checkout card injects the [`window.stash_sdk` bridge](stash-sdk-js.md). Browser presentations cannot send payment callbacks, so browser checkouts return results through deep links.

## Platforms

| Platform | Language | Minimum runtime | Distribution |
|---|---|---|---|
| iOS | Objective-C, callable from Swift | iOS 15 | Swift Package Manager, XCFramework |
| Android | Java | API 21 | AAR |

Engine wrappers live in separate repositories: [stash-unity](https://github.com/stashgg/stash-unity) and [stash-unreal](https://github.com/stashgg/stash-unreal). Both currently bind the 2.x SDK.

## Quick start

iOS (Swift):

```swift
import StashNative

StashNativeCard.sharedInstance().delegate = self
StashNativeCard.sharedInstance().openCard(withURL: checkoutURL, from: self, config: nil)
```

Android (Java):

```java
StashNativeCard.getInstance().setListener(listener);
StashNativeCard.getInstance().openCard(activity, checkoutUrl, null);
```

`checkoutURL` is a Stash Pay checkout link created by your backend. Payment callbacks are UI signals: confirm each purchase on your backend before granting items.

## Documentation map

| Section | Contents |
|---|---|
| [Architecture](architecture/index.md) | Components, session lifecycle, sizing model, iOS and Android internals |
| [Usage reference](usage/index.md) | Installation, public API, configuration, callbacks |
| [JavaScript bridge](stash-sdk-js.md) | `window.stash_sdk`, telemetry, navigation rules, page layout contract |
| [Compatibility](compatibility.md) | OS and toolchain requirements, dependencies, permissions, version-specific behavior |
| [Building wrappers](building-wrappers.md) | Binding the SDK to Unity, Unreal, or another engine |
| [Migrating to 3.0](migration-3.0.md) | Breaking changes from 2.x |
| [Development](development.md) | Building, testing, CI, and releases |
