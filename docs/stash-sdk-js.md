---
title: JavaScript bridge
parent: Usage
nav_order: 6
description: The window.stash_sdk API that checkout pages call inside the native card.
---

# JavaScript bridge

Checkout cards inject `window.stash_sdk` into the top-level page. Browser and CodeLink presentations do not.

Sources: `StashBridgeScript()` in [`StashNativeCardViewUtils.m`](https://github.com/stashgg/stash-native/blob/main/iOS/StashNative/Sources/StashNative/StashNativeCardViewUtils.m) and `JS_SDK_SCRIPT` in [`StashWebViewUtils.java`](https://github.com/stashgg/stash-native/blob/main/Android/stashnative/src/main/java/com/stash/stashnative/StashWebViewUtils.java). Test page: [`.github/test/index.html`](https://github.com/stashgg/stash-native/blob/main/.github/test/index.html).

On Android the object can appear after early inline scripts run. Look it up when you call it:

```javascript
window.stash_sdk?.onPurchaseProcessing();
```

## Methods

| Method | Effect |
|---|---|
| `onPaymentSuccess(order?)` | Sends the payment success callback. Closes the card when `autoClose` is on. |
| `onPaymentFailure()` | Sends the payment failure callback. Closes the card when `autoClose` is on. |
| `onPurchaseProcessing()` | Blocks closing by the user or the page and hides the drag handle |
| `onProcessingCompleted()` | Removes the block |
| `expand()`, `collapse()` | Selects the expanded or resting card state |
| `setContentHeight(px)` | Reports the content height so the resting card can shrink |
| `openExternalBrowser(url)` | Closes the card and opens the URL in Safari View Controller or Custom Tabs |
| `openLink(url)` | Opens the URL outside the app. The card stays open. |
| `triggerHaptic()` | Plays a success haptic |
| `getTelemetry()` | Resolves to device, app, card, and timing data |
| `window.close()` | Closes the card, except during purchase processing |

Android ignores failed bridge calls. On iOS they throw.

## Payment

```javascript
stash_sdk.onPurchaseProcessing();
try {
  const order = await submitPayment();
  stash_sdk.onPaymentSuccess(order);
} catch (error) {
  stash_sdk.onProcessingCompleted(); // the user can edit and retry
}
```

Strings reach the host unchanged; other values arrive as `JSON.stringify` output. No argument arrives as `nil` or `null`. `onPaymentFailure` ignores its arguments.

## Links

```javascript
stash_sdk.openExternalBrowser('https://pay.example.com/session/123'); // payment handoff
stash_sdk.openLink('https://stash.gg/terms');                         // terms or help
```

Both accept `http` and `https` URLs only. `openExternalBrowser` adds the `theme` parameter, sends the external payment callback, closes the card, and opens the browser. `openLink` opens Safari or the app that claims the link (iOS), or Custom Tabs (Android), and sends no callbacks.

## Telemetry

```javascript
const t = await stash_sdk.getTelemetry();
console.log(t.hardware.model, t.presentation.state, t.timing.pageLoadTimeMs);
```

```json
{
  "schemaVersion": 1,
  "platform": "ios",
  "hardware": { "manufacturer": "Apple", "model": "iPhone18,2", "memoryBytes": 8589934592 },
  "os": { "version": "26.0", "apiLevel": null },
  "app": { "id": "com.example.game", "version": "2.4.0", "build": "42", "targetSdkVersion": null },
  "runtime": { "sdkVersion": "3.0.0", "webViewEngine": "webkit", "webViewPackage": null, "webViewVersion": null },
  "presentation": {
    "state": "resting", "keyboardVisible": false,
    "orientationPreference": "followHost", "portraitApplied": false,
    "window": { "width": 402, "height": 874 }, "card": { "width": 386, "height": 560 },
    "safeAreaInsets": { "top": 62, "right": 0, "bottom": 34, "left": 0 },
    "multiWindow": null, "fold": { "state": null, "orientation": null, "separating": null }
  },
  "power": { "lowPowerMode": false, "thermalState": "nominal" },
  "timing": { "firstCallAt": 1791540001200, "pageLoadStartedAt": 1791540000000, "pageLoadedAt": 1791540001000, "pageLoadTimeMs": 1000 }
}
```

- Every key is always present. Values a platform cannot provide are `null`.
- Sizes are points (iOS) or dp (Android). Timestamps are Unix milliseconds.
- A full navigation resets the `pageLoad*` fields.
- Android rejects calls made before the page commits and times out after 10 s.
- Telemetry needs no permissions, contains no device identifiers, and is not uploaded.

## Haptics

```javascript
stash_sdk.triggerHaptic();
```

iOS plays a success notification haptic. Android plays `CONFIRM` (API 30+) or `VIRTUAL_KEY`. Nothing plays while the card is hidden or haptics are off.

## Navigation

| URL | Result |
|---|---|
| Non-web scheme containing `stash-pay/success`, `stash-pay/failure`, or `stash-pay/cancel`, for example `mygame://stash-pay/success` | Same as `onPaymentSuccess()`, `onPaymentFailure()`, or `window.close()` |
| Any other non-web scheme | Opened by the OS. The card stays open. |
| Android `intent://` | Launched as a browsable intent. Falls back to `browser_fallback_url`, then the Play Store. |
| iOS link tapped by the user | Opens in an app that claims it as a universal link. Otherwise it loads in the card. |
| `target="_blank"` or `window.open(url)` | Opened outside the app, like `openLink`. On Android, `stash-pay` paths in new windows are not treated as results. |

## Page environment

- The viewport is fixed to `width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover`.
- Text selection and context menus work only in form fields.
- The URL carries `theme=light` or `theme=dark`.
- On `checkout.stash.gg` and `checkout.stashstaging.com`, the loading cover stays until `data-color-scheme` matches `theme` and no `.animate-skeletonOpacityFluctuation` element is visible, for at most 15 s.

## Safe area

The WebView draws behind the home indicator (iOS) and the navigation bar (Android). Pad the bottom of the page:

```css
.checkout { padding-bottom: env(safe-area-inset-bottom, 0px); }
```

Android WebView supports `env()` safe areas from [Chromium M144](https://developer.android.com/develop/ui/views/layout/webapps/understand-window-insets). Keep a fixed padding for older versions.

## Content sizing

Optional. The resting card shrinks to short content when the page marks its wrapper or reports a height.

```html
<main data-stash-content><!-- checkout --></main>
```

```javascript
new ResizeObserver(() => {
  stash_sdk.setContentHeight(content.getBoundingClientRect().height);
}).observe(content);
```

The SDK measures `[data-stash-content]` only when all of these hold:

- Neither the element nor an ancestor is `position: fixed`, `sticky`, or `absolute`.
- The element does not grow as a flex item.
- No rule sets its or an ancestor's height in `%`, viewport units, or `var()`. `html, body { height: 100% }` counts.
- Every stylesheet on the page is readable. Cross-origin CSS without CORS disqualifies the wrapper.

`setContentHeight` takes CSS pixels at the current viewport width and ignores calls made before the page commits.
