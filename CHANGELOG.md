# Changelog

All notable changes to this project will be documented in this file. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project uses [Semantic Versioning](https://semver.org/).

## [3.0.0] - Unreleased

Initial iOS loading now uses one 10-second stall retry within a 15-second foreground response budget, matching Android's cadence. Successful main-frame responses cancel the deadline.

### Breaking changes

- Replace phone/tablet and orientation ratios with preferred content dimensions, a height cap, and edge margins.
- Require the presenting activity or view controller for card and browser calls.
- Remove `openModal` and modal configuration on iOS and Android. Embedded checkout uses `openCard`; browser checkout uses `openBrowser`.
- Remove configurable background colors from both SDKs and samples. Native page-background matching remains automatic.
- Replace forced portrait with a best-effort orientation preference. Remove orientation hooks, popup sizing APIs, and screenshot-backdrop workarounds.
- Raise the iOS minimum to 15. Android API 21 remains supported; fold information uses WindowManager 1.4.0.

### Presentation

- Use card defaults of 400 × 560 points/dp with a 720-point/dp expansion cap on iOS and Android. Explicit zero still removes the height cap.
- Fade from a native initial loading cover into rendered iOS checkout content, with bounded foreground readiness and Reduced Motion support.

- Keep checkout state and the WebView through window, inset, keyboard, and fold changes.
- Expand cards temporarily for keyboard entry and restore the selected state when the keyboard closes.
- Restore iOS keyboard accessory-toolbar removal and keep focused fields visible after the final rotation layout.
- Use one native UIKit card sheet implementation across iPhone, Duo, and iPad. Regular width and height use centered form-sheet sizing with one system large detent and semantic preferred-size changes. Compact layouts use custom detents on iOS 16+ and system detents on iOS 15.
- Add optional card content sizing through `setContentHeight(...)` and an intrinsic `[data-stash-content]` wrapper.
- Keep checkout at native scale through pinch, double-tap, input focus, and viewport changes. Suppress browser menus on noneditable content while preserving field selection, clipboard actions, and autofill.
- Keep resting iOS cards below active status occlusions. Resolve expanded detents independently for dragging, `expand()`, and keyboard entry, keeping checkout controls beside the status region. Place content within a usable fold pane.
- Let checkout own its page colors and match the iOS sheet background to the page instead of injecting dark-mode overrides.
- Fill the iOS card's usable surface with the WebView beneath UIKit's grabber, and request centered placement before opening.
- Keep the WebView full-height behind floating and split iPad keyboards while bringing focused fields into view.
- Prevent blank space below checkout when WebKit adds keyboard padding after the native viewport already ends above the docked keyboard.
- Cancel Android sheet drags when a second finger touches or payment processing begins.
- Add responsive test content and an Android host fixture targeting API 36 and 37.

See [the migration guide](docs/migration-3.0.md). Engine wrapper migrations and desktop changes are separate releases.

## [2.3.1] - 2026-09-03

### Added
- iOS/Android: `StashNativeCard.setInspectableWebViewsEnabled(...)` opt-in flag that makes the checkout WebViews inspectable (Safari Web Inspector / `chrome://inspect`) for QA/debug builds and automated UI tests. Off by default; enabled in both sample apps.

### Changed
- iOS/Android: new-window navigations (anchor `target="_blank"` or `window.open`, main frame or iframe) now open in the external browser instead of being dropped — http/https via the system browser (`openLink` semantics), other schemes via the existing deeplink handling. The checkout stays presented.
- iOS/Android: deeplink interception extended to sub-frames, not just the main frame. Android parses `intent://` URIs with component/selector stripping and `browser_fallback_url` / Play Store fallback; iOS offers user-tapped https links to a claiming app as universal links; both degrade gracefully when no app is installed.

### Removed
- Android: Google Pay WebView redirect handling (`checkGooglePayRedirect` / `openGooglePayInBrowser`, the `googlePayRedirectHandled` guard, and the `GOOGLE_PAY_*` constants). No public API change.

### Fixed
- Android: checkout WebView content is never darkened. Force-dark / algorithmic darkening is now disabled unconditionally instead of keyed to the host theme, fixing near-invisible third-party (Adyen secured-field) input text in device dark mode. The checkout self-themes via the `theme=` URL parameter, so paint-time darkening only ever hurt.
- Android/iOS: expanded card height is clamped to the real content box, fixing the scroll bug and a keyboard-triggered expand that shrank the card below its collapsed height. Covers phone and tablet, including rotation, and drag-release snap-back.
- Android: phone sheet height ceilings subtract bottom insets and intersect with the root-layout content box, closing a race where `expand()` ran before the first `onApplyWindowInsets` dispatch; `expand()` is capped so the card can never grow past 100%.
- Android: `clampRatio` is guarded against NaN/Infinity (parity with iOS `stashClampRatio`), and scheme / provider-detection string matching uses `Locale.ROOT` to avoid Turkish-locale mismatches.
- Sample apps: both samples bundle a deeplink test harness; iOS sample fixes device-build compilation and the iOS 18 tab bar layout.

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
