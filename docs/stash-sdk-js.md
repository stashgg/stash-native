---
title: JavaScript Bridge
parent: Package Architecture
nav_order: 3
description: Internal window.stash_sdk contract between the SDK and Stash web content.
---

# JavaScript Bridge

`window.stash_sdk` is the internal contract between the SDK and Stash web content in the native card. The SDK injects it into the top-level page of card web content only; system browser and module presentations do not get it. Integrators never call it. Calls from other frames are ignored.

Sources: `StashBridgeScript()` in [`StashNativeViewUtils.m`](https://github.com/stashgg/stash-native/blob/main/iOS/StashNative/Sources/StashNative/StashNativeViewUtils.m) and `JS_SDK_SCRIPT` in [`StashWebViewUtils.java`](https://github.com/stashgg/stash-native/blob/main/Android/stashnative/src/main/java/com/stash/stashnative/StashWebViewUtils.java). Android telemetry comes from [`StashTelemetrySupport.java`](https://github.com/stashgg/stash-native/blob/main/Android/stashnative/src/main/java/com/stash/stashnative/StashTelemetrySupport.java). Test page: [`.github/test/index.html`](https://github.com/stashgg/stash-native/blob/main/.github/test/index.html), served at `https://test.stashpreview.com`.

## Methods

| Method | Effect |
|---|---|
| `onPaymentSuccess(order?)` | Payment success callback. Closes the card when `autoClose` is on. |
| `onPaymentFailure()` | Payment failure callback. Closes the card when `autoClose` is on. |
| `lock()` | Blocks closing the card and hides the drag handle |
| `unlock()` | Removes the block |
| `expand()`, `collapse()` | Selects the expanded or resting card height |
| `externalBrowser(url, options?)` | External payment callback, then closes the card and opens the browser. With `{ keepOpen: true }`, the browser opens over the card, which stays open for the player's return. |
| `openLink(url)` | Opens a URL outside the app without callbacks; the card stays open |
| `triggerHaptic(type?)` | Plays a short success haptic, or a long one with `'long'` (or `1`) |
| `getTelemetry()` | Resolves to device, app, card, and timing data |
| `window.close()` | Closes the card, except while locked |

On Android, the object can appear after early inline scripts run, so look it up at call time: `window.stash_sdk?.lock()`. Failed calls are ignored on Android and throw on iOS.

## Payment

```javascript
stash_sdk.lock();
try {
  stash_sdk.onPaymentSuccess(await submitPayment());
} catch (error) {
  stash_sdk.unlock(); // the player can retry
}
```

Strings reach the game unchanged; other values arrive as JSON. With `autoClose` off, payment events can repeat and the card stays open. `externalBrowser` and `openLink` accept `http` and `https` URLs only.

## Navigation

| URL | Result |
|---|---|
| Non-web scheme with `stash-pay/success`, `stash-pay/failure`, or `stash-pay/cancel`, such as `mygame://stash-pay/success` | Same as `onPaymentSuccess()`, `onPaymentFailure()`, or `window.close()` |
| Other non-web schemes | Opened by the OS; the card stays open |
| `target="_blank"` or `window.open(url)` | Opened outside the app, like `openLink`. Android does not treat `stash-pay` URLs in new windows as results. |

## Page environment

- The URL carries `theme=light` or `theme=dark`.
- The viewport is fixed at device width, without zoom.
- On iOS, the WebView draws behind the home indicator; pad the bottom with `env(safe-area-inset-bottom)`. On Android, the SDK keeps the WebView clear of the system bars and supplies no safe-area insets, so `env(safe-area-inset-*)` is 0.
- The loading cover stays until the page paints content, for at most 15 seconds. The requested `theme` does not gate the reveal.

## Telemetry

`getTelemetry()` resolves to an object with `schemaVersion`, `platform`, `hardware`, `os`, `app`, `runtime`, `presentation`, `power`, and `timing`. Every key is present, keys arrive in the same order on iOS and Android, and values a platform cannot provide are `null`. Sizes are in points or dp; timestamps are Unix milliseconds. Telemetry needs no permissions, holds no device identifiers, and is never uploaded.
