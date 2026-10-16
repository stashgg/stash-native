---
title: Migrating to 3.0
nav_order: 7
description: Breaking changes from Stash Native 2.x to 3.0 and how to update native callers, checkout pages, and Android dependencies.
---

# Migrating from 2.x to 3.0

3.0 replaces device-ratio sizing with logical dimensions and requires the caller to pass its view controller or activity. Removed APIs have no compatibility aliases. Update native callers before replacing the 2.x binary. Unity and Unreal wrappers stay on their tested 2.x native version until they are migrated; see [Building wrappers](building-wrappers.md#migrating-a-2x-binding).

## Minimum versions

| | 2.x | 3.0 |
|---|---|---|
| iOS runtime | iOS 13 | iOS 15. Xcode 27.1 cannot target iOS 13 or 14. |
| Android runtime | API 21 | API 21 |
| Android build | | JDK 17, compile SDK 34 |
| iOS host build | | iOS 27.1 SDK for full iPhone Duo display adaptation |

## API changes

| 2.x | 3.0 |
|---|---|
| iOS `openCardWithURL:config:` | `openCardWithURL:fromViewController:config:`, Swift `openCard(withURL:from:config:)` |
| iOS `openBrowserWithURL:` | `openBrowserWithURL:fromViewController:`, or `openBrowserWithURL:fromViewController:config:` |
| Android `setActivity(activity)`, then `openCard(url, config)` | `openCard(activity, url, config)` |
| Android `openBrowser(url)` | `openBrowser(activity, url)` |
| `openModal`, `ModalConfig`, `StashNativeModalConfig` | `openCard` for embedded checkout, `openBrowser` for browser checkout |
| `openPopup`, `PopupSizeConfig`, `StashNativePopupSizeConfig` | Removed |
| `cardHeightRatioPortrait`, `cardWidthRatioLandscape`, `cardHeightRatioLandscape`, `tabletWidthRatioPortrait`, `tabletHeightRatioPortrait`, `tabletWidthRatioLandscape`, `tabletHeightRatioLandscape` | `preferredContentWidth`, `preferredContentHeight`, `maximumContentHeight`, `edgeMargin` |
| `forcePortrait` | `orientationPreference` |
| `backgroundColor` | Removed. Native backgrounds match the page automatically. |
| iOS `disableAutoOrientationUnlock`, `+supportedInterfaceOrientationsForWindow:` | Removed. The SDK scopes its orientation hooks to its own window. |
| iOS screenshot backdrop workarounds | Removed. Android keeps `setBackdropBitmap` and `setBackdropBytes`. |
| `onOptInResponse`, `stashNativeCardDidReceiveOptIn:` | Removed |
| Page `stash_sdk.setPaymentChannel(...)` | Removed |
| None | `codeLink`, `StashNativeCodeLinkConfig` / `CodeLinkConfig`, `onQrCodeScanned`, `onCodeLinkError` |
| None | iOS `StashNativeBrowserConfig` for portrait Safari |

## Pass the presenting host

Swift:

```swift
let stash = StashNativeCard.sharedInstance()
stash.openCard(withURL: checkoutURL, from: self, config: nil)
stash.openBrowser(withURL: checkoutURL, from: self)
```

Java:

```java
StashNativeCard stash = StashNativeCard.getInstance();
stash.openCard(activity, checkoutUrl, null);
stash.openBrowser(activity, checkoutUrl);
```

Pass the view controller or activity of the window that starts the presentation. Calls from engine threads are accepted; the SDK continues on the main thread.

## Replace sizing ratios

Remove every phone, tablet, portrait, and landscape ratio and start with the defaults. No ratio-to-dimension conversion reproduces every 2.x layout. Test the window sizes your app supports.

| Property | Default (points or dp) | Meaning |
|---|---|---|
| `preferredContentWidth` | 400 | Card width in regions at least 600 wide |
| `preferredContentHeight` | 560 | Resting height ceiling and fallback |
| `maximumContentHeight` | 720 | Expanded height cap. `0` allows all available height. |
| `edgeMargin` | 16 | Margin around the card |

Overrides, when needed:

Swift:

```swift
let card = StashNativeCardConfig()
card.preferredContentHeight = 520
card.maximumContentHeight = 0
stash.openCard(withURL: checkoutURL, from: self, config: card)
```

Java:

```java
StashNativeCard.CardConfig card = new StashNativeCard.CardConfig();
card.preferredContentHeight = 520;
card.maximumContentHeight = 0;
stash.openCard(activity, checkoutUrl, card);
```

See [Checkout card](usage/checkout-card.md#configuration) for every property.

## Orientation

Replace `forcePortrait = true` with `orientationPreference = .portrait` (iOS) or `ORIENTATION_PORTRAIT` (Android). The default follows the host.

- iPhone: the SDK presents portrait checkout in its own `UIWindow`, also for landscape-only games, and restores orientation on close. Remove wrapper or app orientation unlock code and screenshot backdrops.
- iPad ignores the preference.
- Android requests portrait only in compact fullscreen windows. `setBackdropBitmap` and `setBackdropBytes` still cover the host rotation; see [Android portrait backdrop](usage/checkout-card.md#android-portrait-backdrop).

Engines that react directly to scene geometry notifications still need device testing.

## Dismissal semantics

`allowDismiss` now controls user dismissal only: swipe or handle drag, backdrop tap, and Android Back. The page's `window.close()`, payment callbacks with `autoClose`, and native `dismiss()` work with either value. Purchase processing still blocks user and page dismissal.

## Checkout pages

- Payment, processing, external link, and close messages keep their 2.x meaning.
- Delete calls to `stash_sdk.setPaymentChannel(...)`.
- `expand()` and `collapse()` select card states at every window size.
- Optional `setContentHeight(px)` and `[data-stash-content]` let a short page get a shorter resting card. Pages render without them.
- The iOS WebView now paints through the bottom safe area, and both SDKs set `viewport-fit=cover`. Pages own `env(safe-area-inset-bottom)` padding for scrolling content and fixed or sticky footers. Put `[data-stash-content]` inside outer safe-area padding and leave that padding out of explicit height reports.

See the [page layout contract](stash-sdk-js.md#page-layout-contract).

## Android dependencies

AAR consumers must declare the base dependencies, which now include WindowManager 1.4.0 and its Java adapter. Do not use WindowManager 1.5 while supporting API 21; it requires API 23. CameraX and ZXing are needed only for CodeLink, including in source-module integrations. Browser stays optional. See [Installation](usage/installation.md#android).

## Checks after migrating

- Rotate, resize, fold, type, and return from an external browser with the same checkout open. Form state, scroll position, processing locks, and exactly-once results must hold.
- Test the minimum OS versions, not only current simulators.
- Keep backend payment verification. UI callbacks are not proof of purchase.
