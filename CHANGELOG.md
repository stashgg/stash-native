# Changelog

All notable changes to this project will be documented in this file. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project uses [Semantic Versioning](https://semver.org/).

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
