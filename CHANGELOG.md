# Changelog

All notable changes to this project will be documented in this file. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project uses [Semantic Versioning](https://semver.org/).

## [2.4.0] - 2026-08-26

### Added
- Windows and macOS desktop hosts (`Desktop/`): the same in-game webview checkout as mobile, presented as a card over the game's own window on WebView2 (Windows 10 1809+ / 11 with the Evergreen runtime) and WKWebView (macOS 11+, universal). Same `openCard` / `openModal` / `openBrowser` API, the same callbacks and config objects, and the same `window.stash_sdk` bridge as 2.3.0 mobile. Two public layers: a C ABI (`Desktop/include/StashNativeDesktop.h`) that is identical on both OSes for game engines, and typed facades for native apps (`StashNativeCard` on macOS, header-only `StashNativeCard.hpp` on Windows). Release artifacts `StashNativeDesktop-<version>-win64.zip` and `StashNativeDesktop-<version>-macos.zip`.
- Desktop samples (`Desktop/macOS/Sample`, `Desktop/Windows/Sample`) with HMAC link generation and `-stash-auto` proof modes; CI builds, tests and smoke-runs both hosts on every push and PR.

### Changed
- Version 2.4.0 on iOS and Android as well; no mobile code changes in this release.

## [2.3.0] - 2026-07-16

### Added
- iOS/Android: `window.stash_sdk.openLink(url)` opens a URL in the external browser with no callbacks and no dismissal (terms and misc links). Spec in `docs/stash-sdk-js.md`.
- iOS/Android: deeplink handling in the checkout WebViews. Main-frame navigations to custom schemes no longer dismiss the card (iOS) or show an error page (Android): URLs containing `stash-pay/success`, `stash-pay/failure`, or `stash-pay/cancel` run the standard payment success / failure / close flows; every other deeplink is handed to the OS and the checkout stays presented.

### Changed
- Internal refactor on both platforms: long files split into focused units (iOS `StashNativeCard*` modules, Android `Stash*Support` helpers). No public API or behavior changes.
- Android: default modal phone portrait width ratio 0.9 to 0.8 (parity with iOS).
- Test card reworked into a bottom-tab layout with a fixed status dock.

### Fixed
- Stability pass across both platforms (three review rounds, ~70 fixes). Highlights:
  - Callback integrity: dismiss/payment/network callbacks fire exactly once, in order, on every path (drag, back, backdrop, plugin, deeplink), including `autoClose false` flows.
  - Reentrancy: open/dismiss/rotate/drag/browser-handoff overlaps no longer strand presentation state on either platform; rejected opens no longer overwrite the live session's config.
  - Network grace: 15s absolute load deadline survives pause/background without burning paused time; connectivity-error whitelists stop spurious dismissals on aborted navigations; Android reloads the checkout once after an OS renderer kill.
  - Android: sticky 450 ms entry-animation start delay no longer defers every later card animation; keep-alive `shortService` handles the Android 14+ timeout instead of crashing the host; low-RAM devices downscale oversized host backdrops; cookies flush at page load and teardown.
  - iOS: theme query parameter no longer corrupts percent-encoded checkout parameters; NaN/invalid sizing config values are sanitized instead of crashing in CoreAnimation; non-ARC (Unreal) over-release fixed; `window.open('')` no longer blanks the checkout.
- Sample apps: deeplink outcome no longer re-fires on rotation, dialogs guard against destroyed activities, iOS sample handles `stash-pay/cancel` and pass-through deeplinks like Android.

## [2.2.4] - 2026-06-23

### Added
- iOS/Android: `window.stash_sdk.onProcessingCompleted()` reverses `onPurchaseProcessing()`. It re-enables card dismissal (swipe, backdrop / overlay tap, back button, and `window.close()`) and fades the drag handle back in. Use it when a purchase that called `onPurchaseProcessing()` finishes or is cancelled without auto-closing the card. iOS posts the JS argument as `data || {}`; Android calls `onProcessingCompleted()` with no serialized payload. No-op when no processing state is active.

## [2.2.3] - 2026-06-17

### Fixed
- iOS: programmatic `closeBrowser` and `dismissSafariViewControllerWithResult:` now fully reset presentation state. `SFSafariViewController` dismissed programmatically did not clear the internal "presented" guard (only the user-initiated Done path did), so a following `openCard`/`openPopup`/`openModal` silently did nothing — no card UI and no callback. The guard now also self-heals if left stale with no presentation on screen. iOS only; Android keeps browser and card state on separate flags.
- Android: pre-API-30 devices no longer push the card off-screen when the soft keyboard opens; a keyboard detector keeps the focused input visible above the keyboard.
- Android: `onDialogDismissed` now fires when `autoClose` is `false`.
- Android: Open Card and Open Modal now emit `onPageLoaded` via the checkout bridge (`StashNativeCardPortraitActivity` → `StashCheckoutBridge` → `StashNativeCardPlugin`). Previously only the legacy popup WebView path invoked `StashNativeCardListener.onPageLoaded()`.

## [2.2.1] - 2026-05-29

### Added
- iOS/Android: optional `autoClose` flag on card/modal configs (default `true`). When `false`, the dialog stays open after the payment callback until closed by the page, user, or host.

### Fixed
- Android: card no longer shifts off-screen when the soft keyboard opens; it now resizes to keep the focused input visible above the keyboard.

## [2.2.0] - 2026-05-26

### Changed
- Android: Chrome Custom Tabs now launch via an internal invisible proxy activity (`StashNativeBrowserProxyActivity`) that owns the `startActivityForResult` lifecycle. `onBrowserClosed()` fires reliably with no host-activity changes — Unity (`UnityPlayerActivity`) and partner apps that cannot ship `onActivityResult` forwarders now get the callback out of the box. Engagement-signal detection of floating/minimized-window dismiss is preserved.

### Removed
- Android (breaking): `StashNativeCard.onActivityResult(int, int, Intent)` and the `StashNativeCard.REQUEST_CODE_CUSTOM_TAB` constant. Hosts that previously forwarded `onActivityResult` should delete that forwarder; it is no longer needed and the symbols no longer exist.

## [2.1.4] - 2026-05-11

### Added
- Android: `StashNativeCardListener.onBrowserClosed()` after external browser handoff (`openBrowser`, external payment). `StashNativeCardListenerAdapter` provides an empty default.
- Android: Chrome Custom Tabs use `startActivityForResult` with `StashNativeCard.REQUEST_CODE_CUSTOM_TAB`; hosts must forward `StashNativeCard.onActivityResult` from the launching activity. `ACTION_VIEW` fallback still uses lifecycle-based `onBrowserClosed`.
- iOS: optional `stashNativeCardDidCloseBrowser` on `StashNativeCardDelegate` when `SFSafariViewController` is dismissed (user Done or `closeBrowser`), including `openBrowserWithURL:` and external payment paths.

## [2.1.3] - 2026-04-14

### Added
- SDK version API: `StashNativeCard.getVersion()` (Android), `StashNativeCard.sdkVersion()` (iOS).
- Unit test foundation: 12 iOS XCTests, 17 Android JUnit tests covering URL normalization, theme parameters, config defaults, and color parsing.
- CI test jobs: `test-android` and `test-ios` in lint workflow.
- `CLAUDE.md` project rules for AI-assisted development.
- `CHANGELOG.md`.

### Fixed
- iOS: `openModalWithURL:config:nil` now uses the same defaults as `StashNativeModalConfig.init` (was 0.9/0.7, now 0.80/0.50).
- iOS: `StashNativeCard.h` ModalConfig doc comments now match actual implementation defaults.
- Android: `openModal()` now clamps ModalConfig ratio values to [0.1, 1.0] (matching `openCard()` behavior).
- Android: Unified `COLOR_DARK_BG` to single canonical value in `CardConstants` (was `#1e1e1e` vs `#1C1C1E` in two files).

### Changed
- Android: ProGuard `consumer-rules.pro` tightened from blanket keep to targeted public API rules.
- Android: Broadcast receiver registration uses `ContextCompat.registerReceiver()` with `RECEIVER_NOT_EXPORTED` on all API levels.
- Android: Removed 14 dead `HONEYCOMB`/`LOLLIPOP` API level checks (minSdk is 21).
- iOS: SPM umbrella header uses `__has_include` for framework vs flat header compatibility.
- iOS: `Package.swift` includes test target.
- Sample apps: marked test fixture data, removed dead code, cleaned verbose comments.

## [2.1.2]

### Fixed
- iOS force rotation issues.
- Android WebView bug in Unreal Engine builds.
- Android keep-alive service improvements.
- Chrome Custom Tabs fallback on Android.
- Android display inset detection with fallback.
- Android same-process bug on Unity.

### Added
- Tablet sizing support.
- `openExternalBrowser` JS bridge function.
- Documentation overhaul (architecture, platform, JS bridge, wrapper guides).

## [2.1.1]

### Added
- Optional keep-alive foreground service for Android browser flows.
- External payment flow (`window.stash_sdk.openExternalBrowser`).
- Customizable sheet background color.
- Payment success order payload.

### Fixed
- Android callback delivery.
- iOS page ready event timing.
- General load time improvements.

## [2.1.0]

### Added
- Generate checkout and webshop URLs in sample apps.
- iOS WKWebView stability improvements.
- Android emulator crash fix.

### Changed
- Adjustments for Stash Pay 2 checkout flow.
- iOS minimum version adjustments.

## [2.0.0]

### Changed
- Project renamed to stash-native.
- API interface updates (breaking).
- Split iOS sample ViewController into extensions.
- Build pipeline overhaul.

## [1.2.5] and earlier

Initial releases with core card, popup, and browser presentation modes.
