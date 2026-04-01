# Architecture Overview

## What The Library Does

Stash Native is a mobile checkout SDK that embeds checkout web content in native UI and exposes a native-JavaScript bridge for payment events and UI actions.

Primary responsibilities:

- Render checkout content in native containers (`WebView` on Android, `WKWebView` on iOS).
- Inject `window.stash_sdk` bridge functions into the checkout page.
- Forward checkout events to host application callbacks/delegates.
- Support card, modal, and browser-based flows.
- Support controlled handoff to external browser with URL normalization and theme propagation.

## High-Level Platform Architecture

```mermaid
flowchart LR
    HostApp[Host App]
    AndroidFacade[Android StashNativeCard]
    AndroidRuntime[Android Plugin and Activity]
    AndroidWeb[Android WebView and JS Bridge]
    AndroidCallbacks[Android StashNativeCardListener]
    IOSFacade[iOS StashNativeCard]
    IOSRuntime[iOS Internal Controller and ViewControllers]
    IOSWeb[iOS WKWebView and Message Handlers]
    IOSCallbacks[iOS StashNativeCardDelegate]

    HostApp --> AndroidFacade
    AndroidFacade --> AndroidRuntime
    AndroidRuntime --> AndroidWeb
    AndroidWeb --> AndroidRuntime
    AndroidRuntime --> AndroidCallbacks

    HostApp --> IOSFacade
    IOSFacade --> IOSRuntime
    IOSRuntime --> IOSWeb
    IOSWeb --> IOSRuntime
    IOSRuntime --> IOSCallbacks
```

## Injection Model Per Platform

### Android

- Bridge script source: `StashWebViewUtils.JS_SDK_SCRIPT`.
- Native JS interface object name: `StashAndroid` (`JS_INTERFACE_NAME`).
- Injected namespace: `window.stash_sdk`.
- Bridge target methods are implemented in `@JavascriptInterface` classes:
  - `StashNativeCardPlugin.StashJavaScriptInterface`
  - `StashNativeCardPortraitActivity.JSInterface`

### iOS

- Bridge script is built in `StashNativeCard.m` and injected via `WKUserScript`.
- JS-to-native communication uses `window.webkit.messageHandlers.<handler>.postMessage(...)`.
- Message handlers are processed in `userContentController:didReceiveScriptMessage:`.
- Injected namespace: `window.stash_sdk`.

## Shared Feature Surface

- Payment result callbacks.
- Purchase processing signal.
- Opt-in/payment channel signal.
- Presentation controls (`expand`, `collapse`, `window.close` override).
- External browser launch (`openExternalBrowser(url)`).
- Theme-aware URL propagation (`theme=dark|light`).

## Runtime Event Flow

```mermaid
sequenceDiagram
    participant Page as CheckoutPage
    participant Bridge as window.stash_sdk
    participant Native as PlatformBridge
    participant SDK as SDKRuntime
    participant App as HostAppCallbacks

    Page->>Bridge: onPaymentSuccess(order)
    Bridge->>Native: post bridge payload
    Native->>SDK: normalize and route event
    SDK->>App: success callback or delegate
```

## External Browser Infrastructure

```mermaid
sequenceDiagram
    participant Page as CheckoutPage
    participant SDK as SDKRuntime
    participant URL as URLNormalization
    participant Browser as ExternalBrowser
    participant App as HostAppCallbacks

    Page->>SDK: openExternalBrowser(url)
    SDK->>URL: validate and normalize
    URL-->>SDK: normalized themed URL
    SDK->>App: external payment requested callback
    SDK->>Browser: open CustomTabs or Safari or system browser
```

## Platform Deep Dives

- Android details: [Android Implementation](./android.md)
- iOS details: [iOS Implementation](./ios.md)
- Build, lint, release, and QA practices: [Maintenance and Testing](./maintenance-and-testing.md)
