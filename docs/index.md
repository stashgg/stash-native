---
title: Overview
nav_order: 1
description: Stash Pay checkout and Stash webshop pages in native iOS and Android apps.
---

# Stash Native

Stash Native shows Stash Pay checkout and Stash webshop pages inside iOS and Android apps, reports payment events to the app, and scans webshop QR codes for account linking.

| Feature | API | Surface |
|---|---|---|
| [Checkout Card](usage/checkout-card.md) | `openCard` | WebView in a native card, with payment callbacks |
| [In-Game Browser](usage/browser.md) | `openBrowser` | Safari View Controller or Chrome Custom Tabs |
| [QR Code Linking](usage/codelink.md) | `codeLink` | QR scanner in the native card |

## Requirements

| Platform | Minimum | Build | Distribution |
|---|---|---|---|
| iOS | iOS 15 | Xcode 27.1 | Swift Package Manager, XCFramework |
| Android | API 21 | JDK 17, compile SDK 34 | AAR |

Setup: [Package Installation](usage/installation.md).

## Quick start

Run receiver setup on the platform main thread before opening checkout:

```swift
import StashNative

StashNative.sharedInstance().delegate = self
StashNative.sharedInstance().openCard(withURL: checkoutURL, from: self, config: nil)
```

```java
StashNative.getInstance().setListener(listener);
StashNative.getInstance().openCard(activity, checkoutUrl, null);
```

Your backend creates `checkoutURL` and confirms each purchase before the game grants items.
