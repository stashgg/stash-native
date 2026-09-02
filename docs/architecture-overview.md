# Architecture Overview

## What The Library Does

Stash Native is a checkout SDK for Android, iOS, Windows and macOS that embeds checkout web content in native UI and exposes a native-JavaScript bridge for payment events and UI actions.

Primary responsibilities:

- Render checkout content in native containers (`WebView` on Android, `WKWebView` on iOS and macOS, WebView2 on Windows).
- Inject `window.stash_sdk` bridge functions into the checkout page.
- Forward checkout events to host application callbacks/delegates.
- Support card, modal, and browser-based flows.
- Support controlled handoff to external browser with URL normalization and theme propagation.

## Repository Map (Where To Read Code)

| Area | Path |
|------|------|
| Android public API | [`Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCard.java`](../Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCard.java) |
| Android host runtime | [`Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCardPlugin.java`](../Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCardPlugin.java) |
| Android checkout activity (host process) | [`Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCardPortraitActivity.java`](../Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCardPortraitActivity.java) |
| Android JS injection and WebView helpers | [`Android/stashnative/src/main/java/com/stash/stashnative/StashWebViewUtils.java`](../Android/stashnative/src/main/java/com/stash/stashnative/StashWebViewUtils.java) |
| Android process bridge | [`Android/stashnative/src/main/java/com/stash/stashnative/StashCheckoutBridge.java`](../Android/stashnative/src/main/java/com/stash/stashnative/StashCheckoutBridge.java) |
| Android manifest (host-process activities, services) | [`Android/stashnative/src/main/AndroidManifest.xml`](../Android/stashnative/src/main/AndroidManifest.xml) |
| iOS public API | [`iOS/StashNative/Sources/StashNative/include/StashNativeCard.h`](../iOS/StashNative/Sources/StashNative/include/StashNativeCard.h) |
| iOS core implementation | [`iOS/StashNative/Sources/StashNative/StashNativeCard.m`](../iOS/StashNative/Sources/StashNative/StashNativeCard.m) |
| iOS navigation and load errors | [`iOS/StashNative/Sources/StashNative/StashNativeCardWebViewDelegates.m`](../iOS/StashNative/Sources/StashNative/StashNativeCardWebViewDelegates.m) |
| iOS presentation controllers | [`iOS/StashNative/Sources/StashNative/StashNativeCardViewControllers.m`](../iOS/StashNative/Sources/StashNative/StashNativeCardViewControllers.m) |
| iOS SPM package | [`iOS/StashNative/Package.swift`](../iOS/StashNative/Package.swift) |
| Desktop C ABI (both OSes) | [`Desktop/include/StashNativeDesktop.h`](../Desktop/include/StashNativeDesktop.h) |
| Desktop shared contract (script, URL, theme, config, `Session`) | [`Desktop/shared/`](../Desktop/shared/) |
| macOS host (AppKit facade, WKWebView) | [`Desktop/macOS/Sources/StashNativeDesktop/`](../Desktop/macOS/Sources/StashNativeDesktop/) |
| Windows host (WebView2, C++ facade) | [`Desktop/Windows/`](../Desktop/Windows/) |
| Desktop SPM package | [`Desktop/Package.swift`](../Desktop/Package.swift) |
| Root integration notes | [`README.md`](../README.md) |

## High-Level Runtime (All Platforms)

One mental model applies to Android, iOS, Windows and macOS: the host app drives the SDK; the SDK owns the embedded web surface and forwards page events back to the app. On desktop the surface is a card over the game's own window and the host may be a game engine bound to the C ABI instead of a native app.

```mermaid
flowchart TB
    Host[HostApp]
    Sdk[StashNativeSDK]
    Web[CheckoutWebPage]

    Host --> Sdk
    Sdk --> Web
    Web -->|window.stash_sdk| Sdk
    Sdk -->|listener or delegate| Host
```

Android implements `Sdk` as [`StashNativeCard`](../Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCard.java) plus [`StashNativeCardPlugin`](../Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCardPlugin.java) and, for the default card path, [`StashNativeCardPortraitActivity`](../Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCardPortraitActivity.java). iOS implements it in [`StashNativeCard`](../iOS/StashNative/Sources/StashNative/StashNativeCard.m) (Objective-C singleton) with presentation split into [`StashNativeCardViewControllers.m`](../iOS/StashNative/Sources/StashNative/StashNativeCardViewControllers.m). Desktop implements it as one shared [`Session`](../Desktop/shared/StashDesktopSession.cpp) (the callback contract) driven by a per-OS core: [`StashDesktopCore.mm`](../Desktop/macOS/Sources/StashNativeDesktop/StashDesktopCore.mm) on macOS, [`StashNativeCard.cpp`](../Desktop/Windows/src/StashNativeCard.cpp) on Windows, both exporting the C ABI in [`StashNativeDesktop.h`](../Desktop/include/StashNativeDesktop.h).

## Injection Model Per Platform

### Android

- Bridge script: constant `JS_SDK_SCRIPT` in [`StashWebViewUtils.java`](../Android/stashnative/src/main/java/com/stash/stashnative/StashWebViewUtils.java).
- JS object exposed to the page: `StashAndroid` via `JS_INTERFACE_NAME` in the same file.
- Injected namespace: `window.stash_sdk`.
- `@JavascriptInterface` implementations:
  - Inner class in [`StashNativeCardPlugin.java`](../Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCardPlugin.java) (`StashJavaScriptInterface`).
  - Inner class in [`StashNativeCardPortraitActivity.java`](../Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCardPortraitActivity.java) (`JSInterface`).
- Injection call sites: search `evaluateJavascript` / `JS_SDK_SCRIPT` / `injectStashSDK` in the plugin and portrait activity.

### iOS

- Bridge script: built as an `NSString` in [`StashNativeCard.m`](../iOS/StashNative/Sources/StashNative/StashNativeCard.m) and installed with `WKUserScript` at document start.
- Native side: `userContentController:didReceiveScriptMessage:` in the same file registers and handles named handlers (for example `stashExternalPayment`).
- Injected namespace: `window.stash_sdk`.
- Handler name constants (for example `kMessageHandlerExternalPayment`) are defined near the top of [`StashNativeCard.m`](../iOS/StashNative/Sources/StashNative/StashNativeCard.m).

### Desktop (Windows and macOS)

- Bridge script: [`Desktop/shared/StashSdkScript.h`](../Desktop/shared/StashSdkScript.h), one body with a per-OS transport prelude: `window.webkit.messageHandlers[name].postMessage` (WKWebView, `WKUserScript` at document start, main frame only) or `window.chrome.webview.postMessage({type, data})` (WebView2, `AddScriptToExecuteOnDocumentCreated`, the script returns outside the top document).
- Native side: `Session::handleMessage` in [`StashDesktopSession.cpp`](../Desktop/shared/StashDesktopSession.cpp), reached through the macOS message proxy or the Windows `WebMessageReceived` handler.
- Injected namespace: `window.stash_sdk`.
- Message names: `STASH_SDK_MSG_*` in [`StashSdkScript.h`](../Desktop/shared/StashSdkScript.h).

## Shared Feature Surface

- Payment result callbacks.
- Purchase processing signal.
- Opt-in or payment channel signal (`setPaymentChannel`).
- Presentation controls (`expand`, `collapse`, `window.close` override).
- External browser launch (`openExternalBrowser(url)`).
- Theme-aware URL propagation (`theme=dark|light`); see `appendThemeQueryParameter` on each platform ([`StashWebViewUtils`](../Android/stashnative/src/main/java/com/stash/stashnative/StashWebViewUtils.java), [`StashNativeCard.m`](../iOS/StashNative/Sources/StashNative/StashNativeCard.m), [`StashDesktopUrl.cpp`](../Desktop/shared/StashDesktopUrl.cpp)).

Authoritative reference for page-side calls: [JavaScript `stash_sdk` API](./stash-sdk-js.md).

## Payment Event Flow (Simplified)

```mermaid
sequenceDiagram
    participant Page as CheckoutPage
    participant Sdk as StashNative
    participant App as HostApp

    Page->>Sdk: stash_sdk.onPaymentSuccess
    Sdk->>App: success callback
```

On Android, portrait checkout uses [`StashCheckoutBridge`](../Android/stashnative/src/main/java/com/stash/stashnative/StashCheckoutBridge.java) package-local broadcasts from [`StashNativeCardPortraitActivity`](../Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCardPortraitActivity.java) to the plugin (same app process by default). See [Android Implementation](./android.md) and [iOS Implementation](./ios.md).

## External Browser (Simplified)

```mermaid
sequenceDiagram
    participant Page as Page
    participant Sdk as SDK
    participant Ext as ExternalBrowser

    Page->>Sdk: openExternalBrowser url
    Sdk->>Ext: open normalized URL
```

Listener or delegate notification and dismissal ordering are specified in [`StashNativeCard.java`](../Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCard.java) (listener contract) and [`StashNativeCard.h`](../iOS/StashNative/Sources/StashNative/include/StashNativeCard.h) (`stashNativeCardDidRequestExternalPaymentWithURL:`).

## Platform Deep Dives

- [JavaScript `stash_sdk` API](./stash-sdk-js.md) — checkout page contract (`onPaymentSuccess`, `openExternalBrowser`, and so on).
- [Android Implementation](./android.md) — file-by-file map, process model, bridge tables.
- [iOS Implementation](./ios.md) — handlers, presentation entry points, load delegate.
- [Windows Implementation](./windows.md) — C ABI, WebView2 layer, Win32 surface.
- [macOS Implementation](./macos.md) — AppKit facade, WKWebView delegates, bundle.
- [Maintenance and Testing](./maintenance-and-testing.md) — CI, local commands, QA harnesses.
