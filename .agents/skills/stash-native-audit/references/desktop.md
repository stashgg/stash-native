# Desktop SDK checks

Review the shared contract, both native hosts, both native facades, and the C ABI. Read `docs/macos.md`, `docs/windows.md`, and `docs/desktop-validation-matrix.md` from the selected desktop snapshot. These files may be absent in a mobile-only checkout; use the [source-selection procedure](scope-and-contracts.md).

## Shared C++ contract and ABI

- Map `Desktop/include/StashNativeDesktop.h` to every export in both hosts, wrapper-facing types, native facades, version declarations, and export checks. Check C linkage, Windows cdecl, symbol visibility, architecture, type width, string lifetime, UTF-8 conversion, and ownership of callback data/userData.
- Check that C++ or Objective-C exceptions cannot unexpectedly cross a C callback/export boundary. Follow null handles/strings, invalid config, encoding failures, and partial initialization to their visible result.
- Follow `StashDesktopSession` through all open/load/processing/result/dismiss/reset/shutdown states. Inspect reentrant callbacks, event ordering, autoClose false, once-guards, stale session IDs, cleanup before notification, and external-launch failure.
- Review shutdown and callback replacement as engine-domain lifetime boundaries. Queued callbacks must not invoke a released function pointer, userData, listener, or facade. Inspect prewarm/open/shutdown overlap and repeated initialization.
- Check `StashDesktopJson` parsing for complete input consumption, type handling, escapes/surrogates, embedded NUL, nesting/size limits, numeric overflow, malformed/truncated/trailing data, and consistency between config and bridge parsers.
- Verify config defaults, unknown-key handling, invalid-object fallback, finite dimensions, theme/color calculations, percent encoding, URL scheme/host classification, query/fragment preservation, and diagnostic origin redaction.
- Desktop accepts mobile ratio/portrait fields for compatibility but uses its documented fixed/custom surface sizing. Do not flag an intentionally ignored mobile layout field or missing UIKit-only API as parity drift.
- Compare both transport preludes of `StashSdkScript.h`, top-frame guards, handler names, message payloads, JS string escaping, and injection timing against the mobile scripts and spec.
- Review shared tests for actual state transitions and effect order, not merely script substrings or default construction. Shared tests exercise the contract, not host window behavior.

## macOS: AppKit, Objective-C++, and WKWebView

- Trace facade and C calls into `StashDesktopCore`, shared Session effects, the presenter, WebKit delegates, and final host notifications. Inspect main-queue marshalling and atomic state reads.
- Verify off-main callback replacement/shutdown barriers, main-thread fast paths, reentrancy, and deadlock hazards. A synchronous callback-clear guarantee needs more than an asynchronously posted cleanup block.
- Audit ARC/C++ ownership interaction, block captures, weak proxies, delegates, NSWindow/NSView retention, C callback userData, timers, notifications, autorelease lifetimes, and release while inside a WebKit callback. Apply non-ARC requirements only to interfaces/consumers that claim support; desktop is not automatically the iOS build configuration.
- Review SetHostWindow, key/main-window fallback, host close, child-window attachment, sibling z-order, focus restoration, Spaces/fullscreen, multiple displays, backing-scale changes, and host move/resize. Verify SDK surfaces cannot leave the host blocked or steal another window's events.
- Inspect backdrop/card/trust-header ownership, hit testing, Esc scoping, allowDismiss/processing locks, modal alert/confirm/prompt sheets, and completion when the host or session closes.
- Trace navigation policy at main/subframe level, document-start injection, message source, new windows, downloads, HTTP versus transport failures, retries/deadlines, cancellation, and one-reload process-crash recovery.
- Check prewarmed WKWebView reuse for inherited state, delegates and observers; inspect data-store/profile/cookie behavior and inspectability defaults.
- Verify accessibility and keyboard navigation of native controls, high-contrast/dark appearance, point/pixel sizing, and trust-header origin display during redirects or failed navigation.
- Compare SPM target/source/header membership and compiler flags with the universal bundle script. Check minimum macOS, arm64/x86_64 slices, C exports, linked frameworks, version, and shipping signing/notarization instructions. Do not equate a native-architecture SPM build with a universal distributable.

## Windows: Win32, C++, COM, and WebView2

- Trace the header-only facade and exports into the core, shared Session, hidden message window, Win32 surface, controller, and deferred host event delivery.
- Verify COM apartment/thread assumptions, message-loop ownership, cross-thread calls according to the declared API, posted-message ownership, and callback execution after WebView2 callbacks unwind. Treat atomic state reads according to their separate contract.
- Inspect asynchronous environment/controller creation against close, shutdown, prewarm, and a subsequent session. Check stale completion guards, HRESULT handling, COM reference counts, event-token removal, controller close, captured `this`, and event payload lifetime.
- Review HWND validity and process ownership, host discovery, host destruction, WM_CLOSE/WM_DESTROY paths, subclass/message-handler restoration where used, child-window z-order, clipping styles, GDI resources, timers, and repeated open/close without leaks.
- Check point/DPI/pixel conversion, multi-monitor movement, DPI/fullscreen transitions, hit testing, native trust-header rendering, keyboard focus/tab order, Esc and close controls, high contrast, and allowDismiss/processing behavior. Review attached and standalone presentations separately.
- Trace WebView2 absent/unsupported runtime, SDK/runtime interface differences, environment creation failures, user-data-folder permissions/collisions, and prewarm reuse. Verify failure clears presentation state and supplies the documented callback.
- Inspect document-created script frame scope, WebMessageReceived source validation, navigation/new-window/download permissions, local files, JS dialogs, and any settings that widen native access. Message shape alone is not origin authentication.
- Check ContentLoading versus NavigationCompleted bookkeeping, navigation IDs, HTTP status interface availability, transport errors, frame failures, retry/deadline timers, renderer/browser process failure, and cancellation after teardown.
- Review DLL loading/export names, import library/facade compilation, x64 assumptions, static CRT and cross-module allocation ownership, WebView2 loader packaging, NuGet version reproducibility and TLS verification, and sample runtime dependencies.
- A CMake configure or successful DLL compile does not prove tests were registered or a real WebView2 surface worked. Require nonzero discovered CTest tests and separate sample proof evidence.

## Desktop runtime and engine scenarios

Use [verification](verification.md) for executable commands and proof criteria. Track these scenarios for both desktop hosts:

| Scenario | Required observation |
|---|---|
| Sample `-stash-auto local` | Actual WKWebView/WebView2 loads the packaged local page with explicit file permission, emits the expected bridge sequence, closes the checkout, and reports success with exit zero. |
| Sample `-stash-auto secure` | File access without opt-in and HTTP navigation are refused, events and presentation state match the runner's contract, and both phases complete. |
| Prewarm -> immediate open -> close | One current session, one pageLoaded, no stale controller/delegate completion or retained hidden surface. |
| Shutdown/callback replacement | No callbacks into the old engine domain; repeated calls and later reuse obey the facade and ABI contract. |
| Host move/resize/close | Surface follows the correct host, DPI/backing scale is correct, child windows stay above sibling content, focus and modified host state are restored. |
| Payment UI | Processing locks, autoClose false, window.close, redirects, new windows, JS dialogs, failure recovery, and the validation-matrix iframe page work under a real host. |
| Packaged sample | Runs outside the source tree with its DLL/bundle and test pages; a compile-time source path does not hide missing assets. |
| Engine integration | Unity/Unreal player and editor, reload with checkout open, windowed/borderless/exclusive fullscreen where applicable, and callback delivery on the engine's expected loop. |

Staging payments, wallet handoffs, 3DS challenges, and protected-game/anti-cheat behavior require the actual integration environment and appropriate test inputs. A standalone sample next to a protected game does not test loading inside that game's process. Keep unavailable flows and documented platform limitations visible; neither source inspection nor offline proof runs close those checks. Record results locally unless the user separately requests external reporting.
