---
title: Usage
nav_order: 2
has_children: true
description: Public API of the iOS and Android SDKs.
---

# Usage

Both SDKs expose one singleton, `StashNativeCard`, declared in [`StashNativeCard.h`](https://github.com/stashgg/stash-native/blob/main/iOS/StashNative/Sources/StashNative/include/StashNativeCard.h) and [`StashNativeCard.java`](https://github.com/stashgg/stash-native/blob/main/Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCard.java).

| Operation | iOS (Swift) | Android |
|---|---|---|
| Get the singleton | `StashNativeCard.sharedInstance()` | `StashNativeCard.getInstance()` |
| Receive callbacks | `delegate` | `setListener(listener)` |
| Open checkout | `openCard(withURL:from:config:)` | `openCard(activity, url, config)` |
| Open browser | `openBrowser(withURL:from:config:)` | `openBrowser(activity, url)` |
| Open QR scanner | `codeLink(from:config:)` | `codeLink(activity, config)` |
| Close | `dismiss()` | `dismiss()` |
| Close the browser | `closeBrowser()` | Not available |
| Close the browser with a result | `dismissSafariViewController(withResult:)` | Not available |
| Close without callbacks | `resetPresentationState()` | `resetPresentationState()` |
| Read state | `isCurrentlyPresented`, `isPurchaseProcessing` | `isCurrentlyPresented()`, `isPurchaseProcessing()` |
| Portrait backdrop | Not available | `setBackdropBitmap(bitmap)`, `setBackdropBytes(bytes)` |
| Keep-alive service | Not available | `setKeepAliveEnabled(enabled)`, `setKeepAliveConfig(config)` |
| WebView inspection | `setInspectableWebViewsEnabled(_:)` | `setInspectableWebViewsEnabled(enabled)` |
| SDK version | `sdkVersion()` | `getVersion()` |

## Rules

- Pass the activity or view controller of the window that starts the presentation.
- Set the delegate or listener before opening.
- Call from any thread. The SDK switches to the main thread and calls back on it.
- One presentation runs at a time. Open calls made during one are ignored without a callback. Android's `openBrowser` is the exception.
- URLs must be `http` or `https`. A URL without a scheme gets `https://`.
- Configs are copied when you call. Later changes to the object have no effect.

## WebView inspection

```swift
StashNativeCard.setInspectableWebViewsEnabled(true)
```

```java
StashNativeCard.setInspectableWebViewsEnabled(true);
```

Makes checkout debuggable in Safari Web Inspector (iOS 16.4+) or `chrome://inspect`. Enable it in debug builds only. On Android it affects every WebView in the process.
