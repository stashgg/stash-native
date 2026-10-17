---
title: JavaScript Bridge
parent: Package Architecture
nav_order: 3
description: Internal window.stash_sdk contract between the SDK and Stash checkout pages.
---

# JavaScript Bridge

`window.stash_sdk` is the internal contract between the SDK and Stash checkout pages. The checkout card injects it into the top-level page; the in-game browser and QR scanner do not. Integrators never call it. Calls from other frames are ignored.

Sources: `StashBridgeScript()` in [`StashNativeViewUtils.m`](https://github.com/stashgg/stash-native/blob/main/iOS/StashNative/Sources/StashNative/StashNativeViewUtils.m) and `JS_SDK_SCRIPT` in [`StashWebViewUtils.java`](https://github.com/stashgg/stash-native/blob/main/Android/stashnative/src/main/java/com/stash/stashnative/StashWebViewUtils.java). Test page: [`.github/test/index.html`](https://github.com/stashgg/stash-native/blob/main/.github/test/index.html).

## Methods

| Method | Effect |
|---|---|
| `onPaymentSuccess(order?)` | Payment success callback. Closes the card when `autoClose` is on. |
| `onPaymentFailure()` | Payment failure callback. Closes the card when `autoClose` is on. |
| `onPurchaseProcessing()` | Blocks closing the card and hides the drag handle |
| `onProcessingCompleted()` | Removes the block |
| `expand()`, `collapse()` | Selects the expanded or resting card height |
| `setContentHeight(px)` | Reports the content height in CSS pixels, so the resting card can shrink |
| `openExternalBrowser(url)` | External payment callback, then closes the card and opens the in-game browser |
| `openLink(url)` | Opens a URL outside the app without callbacks; the card stays open |
| `triggerHaptic()` | Plays a success haptic |
| `getTelemetry()` | Resolves to device, app, card, and timing data |
| `window.close()` | Closes the card, except during processing |

On Android, the object can appear after early inline scripts run, so look it up at call time: `window.stash_sdk?.onPurchaseProcessing()`. Failed calls are ignored on Android and throw on iOS.

## Payment

```javascript
stash_sdk.onPurchaseProcessing();
try {
  stash_sdk.onPaymentSuccess(await submitPayment());
} catch (error) {
  stash_sdk.onProcessingCompleted(); // the player can retry
}
```

Strings reach the game unchanged; other values arrive as JSON. With `autoClose` off, payment events can repeat and the card stays open. `openExternalBrowser` and `openLink` accept `http` and `https` URLs only.

## Navigation

| URL | Result |
|---|---|
| Non-web scheme with `stash-pay/success`, `stash-pay/failure`, or `stash-pay/cancel`, such as `mygame://stash-pay/success` | Same as `onPaymentSuccess()`, `onPaymentFailure()`, or `window.close()` |
| Other non-web schemes | Opened by the OS; the card stays open |
| `target="_blank"` or `window.open(url)` | Opened outside the app, like `openLink`. Android does not treat `stash-pay` URLs in new windows as results. |

## Page environment

- The URL carries `theme=light` or `theme=dark`.
- The viewport is fixed at device width, without zoom.
- The WebView draws behind the home indicator and navigation bar; pad the bottom with `env(safe-area-inset-bottom)`.
- On Stash checkout hosts, the loading cover stays until the page's `data-color-scheme` matches `theme` and no loading skeleton is visible, for at most 15 seconds.

## Telemetry

`getTelemetry()` resolves to an object with `schemaVersion`, `platform`, `hardware`, `os`, `app`, `runtime`, `presentation`, `power`, and `timing`. Every key is present, and values a platform cannot provide are `null`. Sizes are in points or dp; timestamps are Unix milliseconds. Telemetry needs no permissions, holds no device identifiers, and is never uploaded.

## Content sizing

The resting card can shrink to short content. Mark the content wrapper with `data-stash-content`, or report its height with `setContentHeight(px)`. The SDK measures the wrapper only when its height does not depend on the viewport: no fixed, sticky, or absolute positioning, no flex growth, no `%`, viewport-unit, or `var()` heights on it or its ancestors, and only readable stylesheets.
