# Android SDK checks

Read the facade, plugin, activity, both JS interface classes, WebView/popup support, sizing/IME/backdrop helpers, URL launcher, window compatibility, Custom Tabs engagement, and service together. Discover additional classes in the current snapshot.

## Ownership and lifecycle

- Trace singleton references to Activity, Context, listeners, dialogs, views, WebViews, Custom Tabs sessions, and services. Verify application context is used only where its behavior is appropriate.
- Check activity creation/destruction/recreation, saved state, process restoration, back handling, host finishing, configuration changes, and background/foreground transitions. The checkout must remain in the host process.
- Pair receiver registration/unregistration, JS interface addition/removal, handler callbacks, timers, animation listeners, backdrop bitmaps, and service start/stop across success and failure paths.
- Review WebView disposal after callbacks unwind, ownership of posted cleanup, partially created surfaces, and repeated teardown. Confirm native views are detached and queued work cannot resurrect a closed session.

## Threading, events, and browser handoff

- Trace the actual callback threads for JS bridge methods, WebView clients, broadcasts, timers, services, and public calls. JS bridge code must not assume it executes on the UI thread; verify any exception propagation claim for the actual boundary.
- Check UI dispatch, singleton field visibility, listener changes, open/dismiss races, double taps, callback reentrancy, stale broadcasts, and delayed work from a previous session.
- Verify package scoping and non-exported receiver registration; validate actions and extras before state changes. Follow event order through `StashCheckoutBridge` and plugin dispatch.
- Trace success/failure/opt-in/network/pageLoaded/dismiss events, autoClose behavior, processing lock, cancellation, and exactly-once guards under both activity and popup paths.
- Follow Custom Tabs proxy activity results and engagement fallback, missing browser/runtime classes, cancelled launches, external return, and fallback ACTION_VIEW. Hosts should not need an onActivityResult forwarding workaround.
- Inspect keep-alive service type, notification/channel/permission handling, OS restrictions, stop conditions, and host impact at the declared target/min SDK levels.

## Web content and input trust

- Review JS interface exposure, origin/frame assumptions, injection timing, source escaping, duplicate injection, message types, and cancellation of callbacks after teardown.
- Check file/content access, mixed content, universal file access, cookies/SSO needs, WebView debugging, TLS errors, local resources, permission requests, downloads, and unhandled new windows.
- Trace URL normalization and intent parsing through to launch. Check intent component/selector handling, grants/flags, browser fallback URLs, allowed schemes, malformed URLs, and installed-handler checks.
- Follow every public and bridge input: null/empty strings, malformed JSON/colors, numeric bounds/NaN/infinity, percent/Unicode encoding, locale-dependent case/format operations, and unexpected Intent extras.
- Check logs and errors for payment data, personal data, credentials, signed checkout URLs, and silent failures that strand the UI or lose an expected callback.

## Layout and performance

- Check dp/px conversion, rounding, safe insets and fallbacks, edge-to-edge behavior, cutouts, IME transitions, navigation modes, phones/tablets, landscape hosts with portrait checkout, and very small/resized windows.
- Validate ratios at runtime, card/modal/popup size calculations, gesture thresholds, animator cancellation, and layout state after interrupted transitions.
- Inspect accessibility labels, TalkBack focus, dismissal affordances, contrast/text scaling, and processing-disabled controls.
- Trace blocking I/O, expensive reflection/parsing, bitmap allocation, repeated WebView creation, retained pages, and animation allocations. Preserve the documented card-resize tradeoff unless new evidence shows a regression.

## Compatibility, tests, and distribution

- Compare min/target/compile SDK and Java settings with API guards, manifests, docs, and runtime fallback behavior.
- Runtime reflection for optional libraries must handle `Throwable`. Check use sites and class loading as well as reflective invocation; test-only reflection is not governed by this missing-library rule.
- Validate manifest merging, exported components, service declarations, resource-name collisions, transitive versus compileOnly dependencies, and raw-AAR consumer instructions.
- Check consumer ProGuard/R8 rules against public methods, JS annotations, reflection, and engine wrappers. An unminified sample build does not demonstrate a minified consumer works.
- Read JUnit/Robolectric tests and identify paths masked by `returnDefaultValues`. Check meaningful state/event assertions, lifecycle reset, looper draining, and singleton restoration between tests.
- Review repository Checkstyle and Android Lint reports for both SDK and sample. Inspect warning severity, abortOnError, and CI continue-on-error; exit zero alone is not lint-clean evidence.
- Use [verification](verification.md) for builds, tests, analysis, and optional-library/minified consumer checks.
