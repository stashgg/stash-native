---
title: Usage
nav_order: 2
has_children: true
description: Add Stash Pay checkout, the in-game browser, and QR code linking to an iOS or Android game.
---

# Usage

1. [Install the package](installation.md).
2. [Set a callback receiver](callbacks.md#set-the-receiver).
3. Open an `https://` checkout link from your backend in the [Checkout Card](checkout-card.md) or the [In-Game Browser](browser.md).
4. Grant items after your backend confirms the purchase.

Unity and Unreal Engine games use [stash-unity](https://github.com/stashgg/stash-unity) and [stash-unreal](https://github.com/stashgg/stash-unreal). For other engines, see [Engine Wrappers](../architecture/engine-wrappers.md).

## Features

| Feature | For | Results |
|---|---|---|
| [Checkout Card](checkout-card.md) | Stash Pay checkout over the game | Callbacks |
| [In-Game Browser](browser.md) | Webshop links and browser checkout | Deep link |
| [QR Code Linking](codelink.md) | Linking a webshop account | Callback with the scanned content |

## API

`StashNative` is a singleton on both platforms. Open calls work from any thread.

| Task | iOS (Swift) | Android (Java) |
|---|---|---|
| Get the SDK | `StashNative.sharedInstance()` | `StashNative.getInstance()` |
| Set the callback receiver | `delegate = self` | `setListener(listener)` |
| Open the checkout card | `openCard(withURL:from:config:)` | `openCard(activity, url, config)` |
| Open the in-game browser | `openBrowser(withURL:from:config:)` | `openBrowser(activity, url)` |
| Open the QR scanner | `openScanner(from:config:)` | `openScanner(activity, config)` |
| Close the card or scanner | `dismiss()` | `dismiss()` |
| Close the browser | `closeBrowser()` | `closeBrowser()`, no effect |
| Reset without callbacks, for example on logout | `resetPresentationState()` | `resetPresentationState()` |
| Check what is open | `isCurrentlyPresented`, `isPurchaseProcessing` | `isCurrentlyPresented()`, `isPurchaseProcessing()` |
| Get the SDK version | `StashNative.sdkVersion()` | `StashNative.getVersion()` |

Include the SDK version when you contact [developers@stash.gg](mailto:developers@stash.gg).
