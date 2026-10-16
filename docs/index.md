---
title: Overview
nav_order: 1
description: Stash Pay checkout and Stash webshop pages in native iOS and Android apps.
---

# Stash Native

Stash Native shows Stash Pay checkout and Stash webshop pages inside iOS and Android apps, reports payment events to the app, and scans webshop QR codes for account linking.

| Feature | API | Surface |
|---|---|---|
| [Checkout card](usage/checkout-card.md) | `openCard` | WebView in a native card, with payment callbacks |
| [Browser](usage/browser.md) | `openBrowser` | Safari View Controller or Chrome Custom Tabs |
| [CodeLink](usage/codelink.md) | `codeLink` | QR scanner in the native card |

## Requirements

| Platform | Minimum | Build | Distribution |
|---|---|---|---|
| iOS | iOS 15 | Xcode 27.1 | Swift Package Manager, XCFramework |
| Android | API 21 | JDK 17, compile SDK 34 | AAR |

Setup: [Installation](usage/installation.md).

## Quick start

```swift
import StashNative

StashNativeCard.sharedInstance().delegate = self
StashNativeCard.sharedInstance().openCard(withURL: checkoutURL, from: self, config: nil)
```

```java
StashNativeCard.getInstance().setListener(listener);
StashNativeCard.getInstance().openCard(activity, checkoutUrl, null);
```

Your backend creates `checkoutURL` and confirms each purchase before the game grants items.
