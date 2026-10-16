---
title: Usage reference
nav_order: 3
has_children: true
description: Public API of the iOS and Android SDKs, with call rules shared by every presentation.
---

# Usage reference

Both SDKs expose one singleton facade, `StashNativeCard`. iOS declares it in [`StashNativeCard.h`](https://github.com/stashgg/stash-native/blob/main/iOS/StashNative/Sources/StashNative/include/StashNativeCard.h); Android in [`StashNativeCard.java`](https://github.com/stashgg/stash-native/blob/main/Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCard.java).

| Page | Covers |
|---|---|
| [Installation](installation.md) | Swift Package Manager, XCFramework, AAR, Gradle dependencies, manifest and Info.plist entries |
| [Checkout card](checkout-card.md) | `openCard`, `CardConfig`, sizing, orientation, Android backdrop |
| [Browser](browser.md) | `openBrowser`, `closeBrowser`, browser orientation, Android keep-alive |
| [CodeLink](codelink.md) | `codeLink`, scanner text, permissions, errors |
| [Callbacks and lifecycle](callbacks.md) | Every callback, delivery order, state queries, dismissal and reset |

## API map

| Operation | iOS (Swift) | iOS (Objective-C) | Android (Java) |
|---|---|---|---|
| Get the facade | `StashNativeCard.sharedInstance()` | `[StashNativeCard sharedInstance]` | `StashNativeCard.getInstance()` |
| Set callbacks | `.delegate = self` | `.delegate = self` | `setListener(listener)` |
| Open checkout card | `openCard(withURL:from:config:)` | `openCardWithURL:fromViewController:config:` | `openCard(activity, url, config)` |
| Open browser | `openBrowser(withURL:from:)` | `openBrowserWithURL:fromViewController:` | `openBrowser(activity, url)` |
| Open browser with orientation | `openBrowser(withURL:from:config:)` | `openBrowserWithURL:fromViewController:config:` | Not available |
| Open QR scanner | `codeLink(from:config:)`, `codeLink(from:)` | `codeLinkFromViewController:config:` | `codeLink(activity, config)`, `codeLink(activity)` |
| Close the presentation | `dismiss()` | `dismiss` | `dismiss()` |
| Close the browser | `closeBrowser()` | `closeBrowser` | `closeBrowser()` (no effect) |
| Close the browser with a result | `dismissSafariViewController(withResult:)` | `dismissSafariViewControllerWithResult:` | Not available |
| Tear down without callbacks | `resetPresentationState()` | `resetPresentationState` | `resetPresentationState()` |
| Query presentation | `isCurrentlyPresented` | `isCurrentlyPresented` | `isCurrentlyPresented()` |
| Query processing lock | `isPurchaseProcessing` | `isPurchaseProcessing` | `isPurchaseProcessing()` |
| Portrait backdrop | Not available | Not available | `setBackdropBitmap(bitmap)`, `setBackdropBytes(bytes)` |
| Keep-alive service | Not available | Not available | `setKeepAliveEnabled(enabled)`, `setKeepAliveConfig(config)` |
| WebView inspection | `StashNativeCard.setInspectableWebViewsEnabled(_:)` | `+setInspectableWebViewsEnabled:` | `StashNativeCard.setInspectableWebViewsEnabled(enabled)` |
| SDK version | `StashNativeCard.sdkVersion()` | `+sdkVersion` | `StashNativeCard.getVersion()` |

## Types

| Purpose | iOS | Android |
|---|---|---|
| Card configuration | `StashNativeCardConfig` | `StashNativeCard.CardConfig` |
| Browser configuration | `StashNativeBrowserConfig` | None |
| Scanner text | `StashNativeCodeLinkConfig` | `StashNativeCard.CodeLinkConfig` |
| Keep-alive notification | None | `StashNativeCard.KeepAliveConfig` |
| Orientation | `StashNativeOrientationPreference` (`.followHost`, `.portrait`) | `CardConfig.ORIENTATION_FOLLOW_HOST`, `CardConfig.ORIENTATION_PORTRAIT` |
| Callbacks | `StashNativeCardDelegate` (all methods optional) | `StashNativeCardListener`, `StashNativeCardListenerAdapter` |
| Scanner errors | `NSError` in `StashNativeCodeLinkErrorDomain` with `StashNativeCodeLinkError` codes | `StashNativeCard.CodeLinkError` |

## Call rules

- Pass the view controller or activity that belongs to the window starting the presentation. The SDK never searches for a foreground scene or a current activity.
- iOS presents from the topmost controller in the presenter's `presentedViewController` chain. The presenter must be in a window and not being dismissed.
- Set the delegate or listener on the main thread before opening.
- Methods can be called from any thread. Open calls capture the URL and config on the calling thread and continue on the main thread.
- Callbacks arrive on the main thread.
- The URL must be `http` or `https` with a host. A missing scheme becomes `https://`. Other schemes and malformed URLs are ignored.
- An open call is ignored without a callback when another presentation is active. On iOS this includes a Safari presentation. On Android, `openBrowser` is not blocked by an open card.
- Configs are copied when the call is made. Changing the config object afterward does not affect the open presentation.

## WebView inspection

```swift
StashNativeCard.setInspectableWebViewsEnabled(true)   // iOS, Safari Web Inspector, iOS 16.4+
```

```java
StashNativeCard.setInspectableWebViewsEnabled(true);  // Android, chrome://inspect
```

Call it before opening a card. It is off by default. Enable it in debug and QA builds only. On Android it calls `WebView.setWebContentsDebuggingEnabled`, which applies to every WebView in the process.

## Version

| Platform | Call | Declared in |
|---|---|---|
| iOS | `StashNativeCard.sdkVersion()` | `StashNativeCard.m` |
| Android | `StashNativeCard.getVersion()` | `SDK_VERSION` in `StashNativeCard.java` |

Both return `"3.0.0"` on `main`. The SDK follows [Semantic Versioning](https://semver.org/). Release history is in the [changelog](https://github.com/stashgg/stash-native/blob/main/CHANGELOG.md).
