# iOS implementation

The SDK exposes `StashNativeCard` and `StashNativeCardConfig` through `StashNativeCard.h`. The singleton owns one active `StashCheckoutSession`. All presentations receive the initiating view controller explicitly; the SDK does not select an arbitrary connected scene.

## Ownership

`StashNativeCard.m` dispatches public operations and creates the session. `StashNativeCardPrivate.h` declares internal interfaces. `StashNativeCardInternal.m` implements the session's WebView, callbacks, processing state, loading deadline, dismissal, and document-height handling.

Configuration is normalized and copied by `StashNativeCardConfigs.m`. Geometry calculations live in `StashNativeCardGeometry.m`. Presentation controllers live in `StashNativeCardViewControllers.m`; URL and view helpers and injected scripts live in `StashNativeCardViewUtils.m`. Navigation delegates are implemented in `StashNativeCardWebViewDelegates.m`, with shared color/theme helpers in `StashNativeCardTheme.m`.

Keep retained state on its session/controller owner. Teardown must invalidate timers, unregister message handlers, detach delegates, and make queued callbacks harmless. A callback that opens a new session must not let an older session tear it down.

Initial loading allows one retry after 10 seconds without a usable main-frame response, within a 15-second foreground-time budget. Background time does not consume that budget. A usable response cancels these timers; slow subresources must not trigger a replay of checkout. This replaces the shorter repeated retry cadence in 2.x.

## Presentation

Cards default to a 400-point preferred width, 560-point resting ceiling and 720-point expansion cap. Explicit zero removes that cap. Available space always limits these sizes.

All iOS cards use `UISheetPresentationController`. UIKit owns the sheet surface, grabber, touch feedback, and interactive transitions on iPhone, Duo, and iPad. Window geometry, safe areas, keyboard overlap, and reserved regions determine layout within that shared presentation.

When both host size classes are regular, the same controller uses native form-sheet sizing with one system large detent. The selected resting or expanded state sets its preferred content size. Public `expand()` and `collapse()` resize that floating card; its native grabber retains UIKit spring and dismissal behavior with one physical stop.

Compact layouts use custom resting and expanded detents on iOS 16+. Compact layouts on iOS 15 use native medium and large detents, or large alone in compact height; exact configured attached-sheet heights require iOS 16+. The selected semantic state survives adaptation between these native sizing policies.

On iOS 27 and later, the SDK requests centered sheet placement before opening and during layout updates. UIKit owns the presentation animation. Floating form sheets use `preferredContentSize` for width and selected content height. Compact sheets use detents for height and leave the preferred height unset.

Use the actual container and scene, independent safe-area edges, keyboard overlap, and available reserved-region information. A width/height change must preserve the WebView, document, input, scroll position, and selected semantic card state. UIKit controls floating-card placement and its presentation animation. Native sheet chrome remains UIKit-owned, and the content width constraint is not an exact outer-sheet width promise.

`orientationPreference = .portrait` presents the existing native card in a separate UIKit window on iPhone, including landscape-only games. The SDK scopes AppDelegate orientation overrides to its own window and, on iOS 27+, temporarily adds its requested orientation to the owning scene's policy. It never changes the game controller's orientation mask or autorotation method. iPad ignores the flag.

The card opens after portrait geometry settles. On dismissal, the SDK restores the previous permitted orientation before returning key-window status to the game. External-payment handoff presents Safari as a native sheet in the same portrait window until the browser closes. iOS 16+ uses scene geometry requests; iOS 15 retains the legacy device-orientation fallback and UIKit autorotation. System windowing restrictions may prevent rotation, in which case the card uses the available host geometry.

The owning scene reports the checkout orientation while that window is active, even when the landscape game window retains its dimensions. Engines that react directly to scene notifications need integration testing. Default Follow Host and standalone OpenBrowser do not install portrait hosting.

Native compact resting detents keep the entire surface below top status occlusions. Expanded native sheets can extend their background behind those regions; the WebView uses an unobstructed content pane. Resolve the two detents independently of the selected state, preserve UIKit's selection during a drag, and update the content pane as the surface moves. The interaction script maintains the mobile viewport when pages replace metadata or the document head, while preserving field editing. Observe WebKit's public `underPageBackgroundColor` for native surface colors; do not rewrite checkout's background CSS.

Extend only the WebView's bottom paint area through the home-indicator region, preserving its safe top, horizontal bounds, and keyboard clipping. Keep native `contentInset` zero so it does not shrink the web viewport after keyboard transitions; inset only the scroll indicators. With `viewport-fit=cover`, pages own `env(safe-area-inset-bottom)` padding for scrolling content and fixed or sticky control wrappers. CSS safe-area values must follow the current window geometry. This hosting policy does not add page padding or make arbitrary controls safe automatically.

Observe late WebKit root-scroll changes and normalize offsets after interaction settles. When the owned docked keyboard exactly meets the already-resized WebView's bottom edge, exclude duplicate automatic keyboard padding from the legal scroll range. Preserve explicit insets, valid page scrolling, and nested DOM scroll positions.

Place `[data-stash-content]` inside outer safe-area padding, and exclude that padding from explicit height reports. See [responsive presentation](responsive-presentation.md) for the page contract.

## Web contract and navigation

`StashBridgeScript()` injects `window.stash_sdk` into the main document. Keep the established message-handler spellings, including `stashNativementSuccess` and `stashNativementFailure`. The card installs a document-scoped content script separately.

The bridge forwards payment results, processing locks, opt-in, expansion/collapse, close, and external navigation. Refer to [the JS contract](stash-sdk-js.md) for payloads and callback ordering. External-payment handoff closes embedded checkout without a normal dismissal event; ordinary external links leave it open.

Checkout fields hide WebKit's previous/next/Done accessory toolbar to preserve editing space. Keyboard predictions and payment autofill remain available. Accessory suppression applies only to the checkout's WebView responders; it does not change WebKit's shared implementation or the host app's fields.

Validate http/https URLs before Safari presentation. Handle payment deep-link results and unsupported app links without navigating WebKit to an unsupported scheme. Blank popup placeholders are ignored; actual new-window destinations follow the external-link policy. Do not disable TLS verification to make test pages load.

## SDK and packaging

The minimum runtime is iOS 15. Use Xcode 27.1 for Duo development and release validation; availability and compile guards isolate newer reserved-region APIs. The host application must also be linked against SDK 27.1 for full Duo layout adoption.

SPM discovers source files automatically. Add new implementation files to `StashNative.xcodeproj` too. Keep framework metadata, `sdkVersion`, and changelog aligned. Preserve the public delegate property's ARC/non-ARC guard and compile both consumer modes.

## Verification

Build and analyze the framework, run SPM XCTest on an iOS Simulator, and build/lint the sample. Copy the package without the adjacent Xcode project before testing so XCTest selects the SPM test target.

Test native card geometry, min/max validation, document identity and width checks, callback reentrancy, and processing locks. Runtime coverage must include keyboard, orientation, multiple host scenes, Duo poses, and resizable iPad windows. Newer simulator results do not prove the iOS 15 runtime path.

In the tested iOS 27.1 Simulator, moving from Duo's outer display to its inner display dismisses the software keyboard in both checkout and a standalone `WKWebView`. The document, entered value, focused element, and caret survive; tapping the field resumes keyboard entry. A native `UITextField` retains its keyboard through the same transition. Record this WebKit behavior separately from layout checks, and capture both the immediate fold result and editing after the field is tapped again.
