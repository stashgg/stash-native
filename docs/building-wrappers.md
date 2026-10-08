# Building wrappers for Stash Native 3.0

Wrappers bind the native SDK to an engine's types, callbacks, and lifecycle. Unity and Unreal live in separate repositories; their existing releases must remain pinned to 2.x until their bindings are migrated. Native 3.0 is not a drop-in binary replacement.

## Binding changes

Pass the initiating host with every UI-open call:

- Android: `openCard(Activity, String, CardConfig)` and `openBrowser(Activity, String)`.
- iOS: `openCardWithURL:fromViewController:config:` and `openBrowserWithURL:fromViewController:`.

Use the current engine activity or the controller attached to its window. Do not find an arbitrary foreground scene or retain a destroyed activity. Marshal calls to the platform UI thread.

Map the responsive config fields directly: preferred content width/height, maximum content height, edge margin, dismissibility, and auto-close. Dimensions are points/dp. Cards also expose the follow-host/portrait preference. Remove modal bindings, background-color configuration, old device ratios, popup multipliers, `setActivity`, and wrapper-owned orientation/backdrop integrations. See [migration](migration-3.0.md).

## Callbacks and lifetime

Set `StashNativeCardListener` or `StashNativeCardDelegate` before opening checkout. Preserve the native callback ordering and payloads when enqueueing engine events. Keep the delegate/listener alive for the session, and stop forwarding into an engine module after teardown.

The SDK permits one active presentation. A window resize or fold transition updates that presentation; wrappers must not dismiss and reopen it. Engine pause/resume must not be interpreted as payment success or cancellation. Android Custom Tabs results are handled internally; no host `onActivityResult` forwarding is required.

The Objective-C delegate property supports both ARC and non-ARC consumers. Validate the wrapper's actual memory-management mode, not only the SDK's ARC build.

## Binary dependencies

Distribute the versioned AAR and all dependencies in the [README](../README.md#android), including WindowManager 1.4.0 and its Java adapter. Do not add sample UI dependencies to the SDK runtime graph. Test the engine's resolved dependency tree and a minified build.

On iOS embed the XCFramework or use SPM. Build the host executable with SDK 27.1 for full Duo behaviour; the framework alone cannot opt an older host into that layout. iOS 15 is the minimum runtime. On iPhone, the SDK hosts portrait checkout in its own UIKit window and manages orientation overrides and restoration, including landscape-only plists. iPad ignores the portrait flag. Validate engine reactions to scene geometry notifications, keyboard entry, browser handoff, cancellation, and return to the game. System windowing restrictions still apply.

## Checkout contract

Forward native calls; do not redefine `window.stash_sdk` in production. Optional content hints affect cards. Payment fulfilment remains backend-verified.

## Engine validation

Exercise opening from the engine's real render hierarchy, processing locks, external browser return, host teardown, repeated opens, and reloads. Rotate, resize, and fold with the same checkout active, including while a payment field has keyboard focus. Check form/scroll preservation and exactly-once terminal callbacks.

Editor simulations are useful for game logic but do not validate WKWebView, Android WebView, payment-provider redirects, or device orientation policy.
