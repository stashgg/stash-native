---
title: Usage
nav_order: 2
has_children: true
description: Integrate Stash Pay checkout, browser checkout, and CodeLink into an iOS or Android app.
---

# Usage

An integration has four steps:

1. Your backend creates a Stash Pay checkout link, or a pre-authenticated webshop link.
2. The game opens it in a [checkout card](checkout-card.md) or the [browser](browser.md).
3. The SDK reports the result through [callbacks](callbacks.md) (card) or a deep link (browser).
4. Your backend confirms the purchase, and only then does the game grant items. Client callbacks drive the UI; they are not proof of payment.

## Choose a presentation

| Presentation | Use it when | Result reaches the game through |
|---|---|---|
| [Checkout card](checkout-card.md) | Players buy inside the game and you want direct success and failure events | Delegate or listener callbacks |
| [Browser](browser.md) | You open a webshop, or prefer browser checkout that still stays in the app | Your app's deep link |
| [CodeLink](codelink.md) | Players link their webshop account by scanning its QR code | Callback with the QR payload |

## API at a glance

Both SDKs expose one singleton, `StashNativeCard`.

| Task | iOS (Swift) | Android (Java) |
|---|---|---|
| Get the singleton | `StashNativeCard.sharedInstance()` | `StashNativeCard.getInstance()` |
| Receive events | `delegate = self` | `setListener(listener)` |
| Open checkout | `openCard(withURL:from:config:)` | `openCard(activity, url, config)` |
| Open the browser | `openBrowser(withURL:from:config:)` | `openBrowser(activity, url)` |
| Open the QR scanner | `codeLink(from:config:)` | `codeLink(activity, config)` |
| Close the card | `dismiss()` | `dismiss()` |
| Close the browser | `closeBrowser()` | Not available |
| Check what is open | `isCurrentlyPresented`, `isPurchaseProcessing` | `isCurrentlyPresented()`, `isPurchaseProcessing()` |

Android also has the [portrait backdrop](checkout-card.md#android-portrait-backdrop) and the [keep-alive service](browser.md#keep-alive-service-android). iOS also has [portrait Safari](browser.md#portrait-safari-ios).

## Integration rules

- Pass the activity or view controller that shows your game when the player starts checkout. The SDK presents on that window, so checkout appears where the player is, also in split screen and multi-window.
- Set the delegate or listener before opening anything, so no event is missed.
- Call the SDK from any thread, including engine threads. Callbacks always arrive on the main thread.
- Only one presentation can be open. Calls made while one is open are ignored, so check `isCurrentlyPresented` if the game needs to know.
- Use `https://` links. The SDK ignores links that are not web URLs.

## WebView debugging

During development, make checkout inspectable before opening it:

```swift
StashNativeCard.setInspectableWebViewsEnabled(true)
```

```java
StashNativeCard.setInspectableWebViewsEnabled(true);
```

Then inspect it with Safari Web Inspector (iOS 16.4+) or `chrome://inspect` (Android). Leave it off in release builds.

## SDK version

```swift
let version = StashNativeCard.sdkVersion()
```

```java
String version = StashNativeCard.getVersion();
```

Include the version when you contact [developers@stash.gg](mailto:developers@stash.gg).
