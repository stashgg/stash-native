---
title: JavaScript bridge
nav_order: 4
description: The window.stash_sdk API injected into checkout cards. Methods, telemetry schema, navigation rules, and the page layout contract.
---

# `window.stash_sdk` reference

Checkout cards inject `window.stash_sdk` into the page's top-level document. Pages call it to report payment state, resize the card, open links, close the card, and read device telemetry. Browser presentations (`openBrowser`) and CodeLink do not inject it.

The two implementations are kept in lockstep and are the source of truth:

| Platform | Script | Native handlers |
|---|---|---|
| iOS | `StashBridgeScript()` in [`StashNativeCardViewUtils.m`](https://github.com/stashgg/stash-native/blob/main/iOS/StashNative/Sources/StashNative/StashNativeCardViewUtils.m) | `handleMessage:body:` in [`StashNativeCardInternal.m`](https://github.com/stashgg/stash-native/blob/main/iOS/StashNative/Sources/StashNative/StashNativeCardInternal.m) |
| Android | `JS_SDK_SCRIPT` in [`StashWebViewUtils.java`](https://github.com/stashgg/stash-native/blob/main/Android/stashnative/src/main/java/com/stash/stashnative/StashWebViewUtils.java) | [`StashCheckoutJsInterface.java`](https://github.com/stashgg/stash-native/blob/main/Android/stashnative/src/main/java/com/stash/stashnative/StashCheckoutJsInterface.java) |

A manual test page that calls every method is in [`.github/test/index.html`](https://github.com/stashgg/stash-native/blob/main/.github/test/index.html). The responsive sizing fixture is [`.github/test/responsive.html`](https://github.com/stashgg/stash-native/blob/main/.github/test/responsive.html).

## Availability

| | iOS | Android |
|---|---|---|
| Injection time | Document start, before page scripts | `onPageStarted`, `onPageCommitVisible` (API 29+), and `onPageFinished` |
| Frames | Top-level document only | Top-level document only |
| Existing object | Methods are added to an existing `window.stash_sdk` object, or a new one | Same |

On Android the object can appear after early inline scripts run. Look it up at call time instead of caching it during page load:

```javascript
function stash() {
  return window.stash_sdk && typeof window.stash_sdk.onPaymentSuccess === 'function'
    ? window.stash_sdk
    : null;
}

stash()?.onPurchaseProcessing();
```

Do not define or replace `stash_sdk` methods in production pages. Call only `window.stash_sdk` and `window.close()`; the WebKit handler names and the Android `StashAndroid` object are private transport.

## Methods

| Method | Arguments | Returns | Effect |
|---|---|---|---|
| [`onPaymentSuccess(order?)`](#onpaymentsuccessorder) | Optional string or JSON-serializable value | `undefined` | Payment success callback. Closes the card when `autoClose` is on. |
| [`onPaymentFailure()`](#onpaymentfailure) | Ignored | `undefined` | Payment failure callback. Closes the card when `autoClose` is on. |
| [`onPurchaseProcessing()`](#onpurchaseprocessing-and-onprocessingcompleted) | Ignored | `undefined` | Locks user and page dismissal |
| [`onProcessingCompleted()`](#onpurchaseprocessing-and-onprocessingcompleted) | Ignored | `undefined` | Releases the lock |
| [`expand()`](#expand-and-collapse) | None | `undefined` | Selects the expanded card state |
| [`collapse()`](#expand-and-collapse) | None | `undefined` | Selects the resting card state |
| [`setContentHeight(px)`](#setcontentheightpx) | Finite number greater than 0, CSS pixels | `undefined` | Reports content height for the resting card |
| [`openExternalBrowser(url)`](#openexternalbrowserurl) | URL string | `undefined` | Hands the payment to the platform browser and closes the card |
| [`openLink(url)`](#openlinkurl) | URL string | `undefined` | Opens a URL outside the app. The card stays open. |
| [`triggerHaptic()`](#triggerhaptic) | None | `undefined` | Plays a success haptic |
| [`getTelemetry()`](#gettelemetry) | None | `Promise<Telemetry>` | Device, app, card, and page timing snapshot |
| [`window.close()`](#windowclose) | None | `undefined` | Requests card close |

Error handling differs by platform. On Android, every method except `getTelemetry` catches bridge exceptions and fails silently. On iOS, methods post directly to WebKit handlers, so a missing handler throws in the caller. `getTelemetry()` rejects on bridge errors on both platforms. Exceptions thrown by page code before the bridge call are never caught by the SDK.

### `onPaymentSuccess(order?)`

```javascript
window.stash_sdk.onPaymentSuccess({ orderId: 'abc', sku: 'gems_100' });
window.stash_sdk.onPaymentSuccess('abc');
window.stash_sdk.onPaymentSuccess();
```

| Argument | Native payload |
|---|---|
| String | The string, unchanged |
| Other value | `JSON.stringify(order)` |
| Omitted, `undefined`, `null`, or `''` | `nil` on iOS, `null` on Android |

Native callbacks: `stashNativeCardDidCompletePaymentWithOrder:` (iOS), `onPaymentSuccess(String)` (Android). Clears the processing lock. With `autoClose` (the default) the card closes after the callback and later payment signals are ignored. With `autoClose = false` the card stays open and every signal is delivered.

### `onPaymentFailure()`

Native callbacks: `stashNativeCardDidFailPayment` (iOS), `onPaymentFailure()` (Android). Arguments are ignored; neither platform forwards a failure payload. Clears the processing lock and follows the same `autoClose` rules as success.

### `onPurchaseProcessing()` and `onProcessingCompleted()`

```javascript
window.stash_sdk.onPurchaseProcessing();
try {
  const order = await submitPayment();
  window.stash_sdk.onPaymentSuccess(order);
} catch (error) {
  window.stash_sdk.onProcessingCompleted(); // Let the user edit and retry.
}
```

While processing:

- Swipe, handle or grabber drags, backdrop taps, Android Back, and VoiceOver escape are ignored.
- `window.close()` and `stash-pay/cancel` deep links are ignored.
- The drag handle or grabber is hidden and active card drags are cancelled.
- Native `dismiss()` from the host still works.

`onProcessingCompleted()` restores user dismissal if `allowDismiss` is on and shows the handle again. A payment result also clears the lock. Calling it without an active lock does nothing. There is no host callback for either method; hosts read `isPurchaseProcessing`.

### `expand()` and `collapse()`

Select the expanded or resting state. Heights follow the current window and config; see [Presentation sizing](architecture/index.md#presentation-sizing). On iOS floating sheets the call changes the sheet's preferred size. When both states resolve to the same height the call changes only the remembered selection. Calls cancel an active content drag.

### `setContentHeight(px)`

Reports the full height of the checkout content so a resting card can shrink to fit. See [Content sizing](#content-sizing) for the measurement contract and the automatic alternative.

```javascript
const content = document.querySelector('#checkout');
function report() {
  window.stash_sdk?.setContentHeight(content.getBoundingClientRect().height);
}
new ResizeObserver(report).observe(content);
window.addEventListener('load', report);
```

### `openExternalBrowser(url)`

Starts an external payment: the card closes and the URL opens in `SFSafariViewController` (iOS) or Chrome Custom Tabs (Android, system browser fallback).

1. `url` is converted with `String(url)`; `undefined` and `null` become `''`.
2. The SDK trims it and accepts only `http` and `https` URLs with a host. A missing scheme becomes `https://`. Other input is ignored.
3. The SDK adds or replaces the `theme` query parameter.
4. The host receives `stashNativeCardDidRequestExternalPaymentWithURL:` (iOS) or `onExternalPayment(url)` (Android) with the final URL.
5. The card closes without a dismissal callback, then the browser opens.
6. When the browser closes, the host receives the browser-closed callback.

### `openLink(url)`

Opens a URL outside the app for terms, help, and other non-payment links. The card stays open, no host callback fires, no `theme` parameter is added, and browser close tracking is not armed. URL validation matches `openExternalBrowser`; invalid input is ignored.

| Platform | Opens with |
|---|---|
| iOS | `UIApplication openURL:`. Safari, or the app that claims a universal link. |
| Android | Custom Tabs when `androidx.browser` is available, otherwise `ACTION_VIEW` |

### `triggerHaptic()`

Plays a short confirmation haptic. Takes no arguments, returns `undefined`, and fires no host callback. Payment callbacks do not trigger it automatically.

| Platform | Feedback |
|---|---|
| iOS | `UINotificationFeedbackGenerator`, success type |
| Android | `View.performHapticFeedback`: `CONFIRM` on API 30+, `VIRTUAL_KEY` below |

No permissions or entitlements are needed, including Android's `VIBRATE`. The call does nothing while the card is hidden, closing, or in the background, or when the device or user settings disable haptics. The return value does not say whether a haptic played.

### `getTelemetry()`

Returns a `Promise` that resolves to a snapshot of the device, host app, card, and page timing. Each call returns a new snapshot.

```javascript
try {
  const t = await window.stash_sdk.getTelemetry();
  console.log(t.hardware.model, t.timing.pageLoadTimeMs);
} catch (error) {
  // Not ready yet, document replaced, or card closing.
}
```

| | iOS | Android |
|---|---|---|
| Ready | From document start | After the top-level document commits (or finishes on older WebViews). Earlier calls reject. |
| Rejects when | Called from a subframe, the session is inactive, or an external payment handoff started | The document changed (`pagehide`), the bridge is unavailable, or no reply arrives within 10 s |
| Scope | Main frame of the session's WebView | Requests and replies carry a per-document token; a replaced document cannot read the new document's telemetry |

Example response from iOS:

```json
{
  "schemaVersion": 1,
  "platform": "ios",
  "hardware": { "manufacturer": "Apple", "model": "iPhone18,2", "memoryBytes": 8589934592 },
  "os": { "version": "26.0", "apiLevel": null },
  "app": { "id": "com.example.game", "version": "2.4.0", "build": "42", "targetSdkVersion": null },
  "runtime": { "sdkVersion": "3.0.0", "webViewEngine": "webkit", "webViewPackage": null, "webViewVersion": null },
  "presentation": {
    "state": "resting",
    "keyboardVisible": false,
    "orientationPreference": "followHost",
    "portraitApplied": false,
    "window": { "width": 402, "height": 874 },
    "card": { "width": 386, "height": 560 },
    "safeAreaInsets": { "top": 62, "right": 0, "bottom": 34, "left": 0 },
    "multiWindow": null,
    "fold": { "state": null, "orientation": null, "separating": null }
  },
  "power": { "lowPowerMode": false, "thermalState": "nominal" },
  "timing": {
    "firstCallAt": 1791540001200,
    "pageLoadStartedAt": 1791540000000,
    "pageLoadedAt": 1791540001000,
    "pageLoadTimeMs": 1000
  }
}
```

Every key is always present. Unavailable values are `null`; nested objects stay present.

| Field | Type | Meaning |
|---|---|---|
| `schemaVersion` | number | Payload version, currently `1`. Independent of the SDK version. |
| `platform` | string | `ios` or `android` |
| `hardware.manufacturer` | string or null | `Apple` on iOS. `Build.MANUFACTURER` on Android. |
| `hardware.model` | string or null | iOS machine identifier, for example `iPhone18,2`. `Build.MODEL` on Android. Identifies a model, not a device. No marketing names. |
| `hardware.memoryBytes` | number or null | Physical RAM reported by the OS. Not available memory or the app's budget. Simulators may report host RAM. |
| `os.version` | string or null | OS release version |
| `os.apiLevel` | number or null | Android API level. `null` on iOS. |
| `app.id` | string or null | Bundle identifier or package name |
| `app.version` | string or null | `CFBundleShortVersionString` or `versionName` |
| `app.build` | string or null | `CFBundleVersion`, or the Android version code as a string |
| `app.targetSdkVersion` | number or null | Android target SDK. `null` on iOS. |
| `runtime.sdkVersion` | string | Stash Native version |
| `runtime.webViewEngine` | string | `webkit` or `chromium` |
| `runtime.webViewPackage` | string or null | Android WebView provider package, API 26+. `null` on iOS. |
| `runtime.webViewVersion` | string or null | Provider version name, API 26+. `null` on iOS. |
| `presentation.state` | string or null | Selected state: `resting` or `expanded`. Keyboard expansion does not change it. |
| `presentation.keyboardVisible` | boolean or null | Whether the card detects a software keyboard |
| `presentation.orientationPreference` | string | Configured preference: `followHost` or `portrait` |
| `presentation.portraitApplied` | boolean | The SDK's portrait policy is active and the checkout is portrait. An ignored tablet or multi-window preference reports `false`. |
| `presentation.window.width`, `.height` | number or null | Checkout window size, including system bar areas |
| `presentation.card.width`, `.height` | number or null | Card bounds, including native chrome |
| `presentation.safeAreaInsets.top`, `.right`, `.bottom`, `.left` | number or null | Safe-area, system bar, and cutout insets. Keyboard excluded. |
| `presentation.multiWindow` | boolean or null | Android multi-window flag, API 24+. `null` on iOS. |
| `presentation.fold.state` | string or null | Android folding feature: `flat` or `halfOpened`. `null` on iOS or without a reported feature. |
| `presentation.fold.orientation` | string or null | `vertical` or `horizontal` |
| `presentation.fold.separating` | boolean or null | Whether the fold splits the window. Missing fold data does not mean the device cannot fold. |
| `power.lowPowerMode` | boolean or null | iOS Low Power Mode or Android Battery Saver |
| `power.thermalState` | string or null | `nominal`, `fair`, `serious`, or `critical`. Android API 29+ maps none to nominal, light and moderate to fair, severe to serious, and critical, emergency, and shutdown to critical. `null` below API 29. |
| `timing.firstCallAt` | number | Unix time in ms of the first accepted `getTelemetry()` call in this card. Fixed for the card's lifetime. |
| `timing.pageLoadStartedAt` | number or null | Unix time in ms of the latest top-level navigation start |
| `timing.pageLoadedAt` | number or null | Unix time in ms of the matching successful page finish. `null` until then. |
| `timing.pageLoadTimeMs` | number or null | Duration between those two callbacks, from a monotonic clock |

Geometry is in iOS points or Android dp, not CSS or physical pixels. Window, card, keyboard, fold, and power values are sampled on every call.

A full navigation, reload, retry, or WebView recovery resets the page timing fields. Failed loads leave the completion fields `null`. Same-document navigation, expansion, rotation, and resizing do not start a new page load. A finished page load does not mean later hydration, lazy images, or the loading fade have completed. Wall-clock changes can make `pageLoadedAt - pageLoadStartedAt` differ from `pageLoadTimeMs`.

Telemetry needs no permissions or consent prompts. It reads public platform APIs and returns the data to the calling page only; the SDK uploads nothing. It contains no advertising or device identifiers, device name, location, contacts, network identity, storage contents, or installed-app list. The page owner is responsible for any analytics it sends.

### `window.close()`

The bridge replaces `window.close` with a close request. The card closes and the host receives `stashNativeCardDidDismiss` or `onDialogDismissed`. It works with either `allowDismiss` value; that flag affects only user gestures. Purchase processing blocks it until `onProcessingCompleted()` or a payment result. On iOS, a script-initiated close of the web view (`webViewDidClose:`) is handled the same way.

## Navigation rules

The checkout WebView loads only web schemes: `http`, `https`, `about`, `blob`, `data`, `file`, and `javascript`. Every other scheme is handled natively, from the main frame and from iframes.

| Navigation | Result |
|---|---|
| Non-web URL containing `stash-pay/success` | Same as `onPaymentSuccess()` with no order |
| Non-web URL containing `stash-pay/failure` | Same as `onPaymentFailure()` |
| Non-web URL containing `stash-pay/cancel` | Same as `window.close()`, including the processing lock |
| Other non-web URL | Opened by the OS: `openURL:` on iOS, `ACTION_VIEW` with `CATEGORY_BROWSABLE` on Android. The card stays open. Missing handlers are ignored. |
| Android `intent://` URI | Launched with explicit component and selector removed and `CATEGORY_BROWSABLE` added. Falls back to `browser_fallback_url`, then the target package's Play Store listing. |
| iOS `apps.apple.com` or `itunes.apple.com` | Opened by the OS |
| iOS user-tapped top-level `http` or `https` link | Offered to an installed app that claims it as a universal link. Loads in the card when no app claims it. Initial loads and redirects always stay in the card. |
| New window: `target="_blank"` or `window.open(url)` | `http` and `https` open outside the app with `openLink` semantics. Empty and `about:blank` windows are dropped so the checkout document is never replaced. Other schemes: iOS applies the rows above, including `stash-pay` results; Android passes them to the OS with `ACTION_VIEW` and does not treat `stash-pay` paths as results. |

The result paths match anywhere in the URL, so any app scheme works: `mygame://stash-pay/success`.

On Android API 21 to 23 the WebView reports navigations without frame information. Deep links are still intercepted, but iframe web navigations cannot be distinguished from top-level ones.

On Android, when the current URL contains `klarna`, `paypal`, or `stripe`, the card shows a native Home button that reloads the initial checkout URL.

## Page environment

The SDK changes the page environment in both WebViews:

| Change | Detail |
|---|---|
| Viewport | Every top-level `meta[name=viewport]` is set to `width=device-width,initial-scale=1,minimum-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover`, and kept that way when the page edits it. Pinch, double-tap, and input focus never zoom. |
| Selection | Injected CSS turns off text selection, touch callouts, and link or image drag outside `input`, `textarea`, and editable elements. Context menus are suppressed on non-editable content. Fields keep selection, clipboard, and autofill. |
| `theme` parameter | The initial URL carries exactly one `theme=light` or `theme=dark` from the host's appearance. Pages own their colors; Android disables algorithmic darkening. |
| Storage | JavaScript, DOM storage, and cookies are enabled. Android accepts third-party cookies and disables file and content URL access. |
| Dialogs | `alert`, `confirm`, and `prompt` show native dialogs |
| Keyboard | Both SDKs scroll the focused field into view above the keyboard. iOS also repairs focus inside iframes and hides the form accessory bar. |

### Initial reveal

A native loading cover hides the WebView until the first document is ready, then fades out. Later navigations do not show it again.

- iOS reveals once the document has committed and shows visible text or controls, or once it finishes loading.
- Android reveals once the document has committed and finished loading.
- On `https://checkout.stash.gg` and `https://checkout.stashstaging.com`, both also wait until the root element's `data-color-scheme` attribute equals the single `theme` query value and no element with the class `animate-skeletonOpacityFluctuation` is visible.

The SDK reads these markers without changing page styles or storage, and checks again after the next paint. The cover is released after 15 s of foreground time regardless. Change these markers only together with the SDK.

## Page layout contract

### Safe areas

The SDK sets `viewport-fit=cover`, so pages receive real `env(safe-area-inset-*)` values and own the spacing for them. The WebView paints behind the home indicator (iOS) and the navigation bar of bottom-attached cards (Android). The SDK adds no content inset or padding.

```css
.checkout-safe-area {
  padding-bottom: env(safe-area-inset-bottom, 0px);
}
```

Apply bottom padding to scrolling content and to fixed or sticky footers so controls stay reachable. On Android, CSS safe-area values depend on the installed WebView provider; [Android documents full support from Chromium M144](https://developer.android.com/develop/ui/views/layout/webapps/understand-window-insets). Keep a plain bottom padding fallback for older providers.

Keep header controls clear of the native grabber (iOS) and the 48 dp handle area (Android) at the top of the card.

### Content sizing

Content sizing is optional. Without it, the resting card uses `preferredContentHeight` and the page scrolls. With it, a short page gets a shorter resting card. Expanded height is unaffected. Sizing applies to checkout cards only.

Automatic: mark one wrapper with `data-stash-content`, inside any outer safe-area padding.

```html
<div class="checkout-safe-area">
  <main data-stash-content>
    <!-- Checkout content, including its own padding. -->
  </main>
</div>
```

The SDK measures the first `[data-stash-content]` element: its border-box height plus vertical margins. It re-measures on resize, DOM mutation, `load`, and font loading. The element is used only while all of these hold:

| Requirement | Why |
|---|---|
| Neither the element nor any ancestor is `position: fixed`, `sticky`, or `absolute` | Positioned boxes do not reflect content height |
| The element itself has `flex-grow: 0` | A growing flex item stretches to the viewport |
| No inline style or stylesheet rule that matches the element or an ancestor sets `height`, `min-height`, `max-height`, or `block-size` with `%`, `vh`, `dvh`, `svh`, `lvh`, `vmin`, `vmax`, `cqh`, `cqb`, or `var()` | Viewport-relative heights create a resize feedback loop |
| Every stylesheet in the document is readable | Cross-origin stylesheets without CORS cannot be inspected, so the SDK cannot prove the rule above |

A common `html, body { height: 100% }` rule disqualifies the wrapper. When the wrapper becomes ineligible, the SDK drops its earlier measurement and the card returns to `preferredContentHeight`.

Explicit: call `setContentHeight(px)` with the full content height in CSS pixels at the current layout viewport width. Include the page's own padding. Exclude native chrome and outer safe-area padding. Explicit reports do not need an eligible wrapper.

Both paths follow the same rules:

- Values must be finite and greater than 0. The visual viewport scale must be 1.
- Each report is tagged with the current document and viewport width. Reports from a previous document, or for a width that no longer matches, are discarded.
- Calls made before the document commits reach a no-op stub. Report again on `load` and whenever the size changes.
- The SDK converts CSS pixels to native units with the WebView's width ratio and coalesces updates. iOS defers updates during a drag.
- `document.scrollHeight` is not an intrinsic height. It includes the viewport and causes feedback loops.
- A cross-origin payment iframe must report its height to its embedding page, which then reports the total.

## Page load signaling

Native navigation callbacks report the first page load to the host. The page sends no readiness message. Resizing does not reload the document or emit another page-loaded callback.

## Changing the bridge

A change to the bridge must land on both platforms in the same release:

1. Update `JS_SDK_SCRIPT` and `StashCheckoutJsInterface` on Android.
2. Update `StashBridgeScript()`, `StashScriptHandlerNames()`, and `handleMessage:body:` on iOS.
3. Keep the content measurement scripts equivalent (`StashContentSizeSupport.script` and `StashContentMeasurementScript`), including document and viewport validation and cleanup.
4. Update `.github/test/index.html` and this page.
5. Keep existing handler spellings, including `stashNativementSuccess` and `stashNativementFailure`.
