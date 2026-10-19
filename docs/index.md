---
title: Overview
nav_order: 1
description: Stash Pay checkout and Stash webshop pages in native iOS and Android apps.
---

# Stash Native

Stash Native shows Stash Pay checkout and webshop pages in iOS and Android games, reports payment events, and scans webshop QR codes for account linking.

For backend setup, webhooks, and Stash Studio, see the [Stash integration guides](https://docs.stash.gg/guides).

| Feature | API | Surface |
|---|---|---|
| [Checkout Card](usage/checkout-card.md) | `openCard` | Checkout in a native card |
| [In-Game Browser](usage/browser.md) | `openBrowser` | Safari View Controller or Chrome Custom Tabs |
| [QR Code Linking](usage/codelink.md) | `openScanner` | QR scanner in a native card (optional module) |

## Requirements

| Platform | Minimum | Build | Distribution |
|---|---|---|---|
| iOS | iOS 15 | Xcode 27.1 | Swift Package Manager, XCFramework |
| Android | API 21 | JDK 17, compile SDK 34 | AAR |

See [Package Installation](usage/installation.md).

## Quick start

Set the receiver on the main thread, then open checkout:

```swift
import StashNative

StashNative.sharedInstance().delegate = self
StashNative.sharedInstance().openCard(withURL: checkoutURL, from: self, config: nil)
```

```java
StashNative.getInstance().setListener(listener);
StashNative.getInstance().openCard(activity, checkoutUrl, null);
```

Your backend [creates the checkout link](https://docs.stash.gg/guides/stash-pay/integration#create-a-checkout-link) and [confirms each purchase](https://docs.stash.gg/guides/stash-pay/integration#processing-purchase) before the game grants items.
