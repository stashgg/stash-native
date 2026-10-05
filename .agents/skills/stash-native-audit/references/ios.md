# iOS SDK checks

Read the public header, shared-state declarations, facade, and extracted implementation units together. Use the source map and shared contract matrix from [scope](scope-and-contracts.md).

## Ownership and lifecycle

- Trace ownership of windows, root/presented controllers, WKWebViews, delegates, script-message handlers, proxy objects, associated objects, and blocks. Check retain cycles and early-return cleanup, not only the normal dismissal path.
- Pair observer/KVO registration with removal; invalidate timers, delayed selectors, display links, animations, and retry blocks. Inspect captures that outlive the current checkout.
- Check handler removal, stopLoading, delegate detachment, native hierarchy removal, and release ordering during navigation or JS callbacks. Verify repeated dismiss/reset and failed presentation are safe.
- Inspect all non-ARC guards and memory-management paths relevant to Unreal, including public header consumption. A weak property compiled under ARC does not prove a non-ARC build is usable. Do not replace a documented assign/weak distinction without its consumer context.

## Threading and session state

- Trace public calls from background threads, WebKit delegates, JS handlers, notification callbacks, and delayed work. UI ownership and state mutation need a consistent main-queue contract.
- Review shared globals in `StashNativeCard.m` and their extern users for initialization/reset omissions, synchronization, and stale references. Check that flags and visible presentation agree after every failure.
- Exercise callback reentrancy, delegate replacement/deallocation, rapid open/dismiss/open, double payment signals, failure then success with autoClose disabled, and dismissal while processing.
- Inspect once-guards, cancellation tokens/session identities, retry versus teardown, and reset behavior. Verify the state an integrator sees from inside a delegate callback.

## WebKit and browser boundaries

- Read user-script timing/frame scope, native handler names, message type validation, escaping of native values into JavaScript, and repeated injection behavior.
- Check navigation policies for checkout/deeplink/custom schemes, redirects, subframes, window.open/target=_blank, external browser requests, and rejected URLs. Ensure decision handlers and JS dialog completions run exactly once on all paths.
- Review TLS/ATS assumptions, local resource access, cookies/data-store isolation, third-party payment/SSO requirements, DevTools defaults, credential-bearing URLs, and production diagnostics.
- Trace navigation failures before/after initial load, timeouts, cancelled loads, stalled pages, and WebKit process termination. Check load state and callback order after retry or terminal failure.
- Review Safari/browser return and cancellation, presentation ownership, listener notifications, URL theming, and absence of an available presenter.

## Presentation and geometry

- Inspect multi-scene/window selection, controller ancestry, presentation during transitions, host dismissal, and restoration of key-window/orientation state.
- Check forcePortrait hooks/swizzling for chaining, method signatures, repeated installation, supported orientations, and effects on other host windows. Preserve game-engine constraints.
- Check card/modal/tablet/landscape paths, safe areas, keyboard/IME changes, rotation during gestures/animations, Split View, backing scale, rounding, and zero/invalid dimensions.
- Verify card/modal ratio normalization at the runtime boundary and popup positive-finite fallback behavior. Popup values above one are valid.
- Check focus, VoiceOver, accessible dismissal, text sizing, contrast, reduced motion, and interaction while purchase processing locks dismissal.

## Quality, performance, and packaging

- Trace main-thread I/O/parsing, repeated allocations, image/backdrop sizes, unnecessary layout, and retained web content. Require measurement or an explicit expensive path for performance claims.
- Review Objective-C naming, nullability, property attributes, NSString copy semantics, initializer behavior, include hygiene, private interfaces, and public doc accuracy against local conventions and Apple guidance.
- Compare SPM and Xcode source membership, public headers/modules, deployment targets, linked frameworks, architecture slices, version metadata, privacy resources where applicable, and XCFramework packaging.
- Map XCTest protection to actual risks: pure sizing/URL/config logic, state transitions, callback order, and ownership. Distinguish source assertions and no-crash smoke tests from real WebKit execution.
- Consult [verification](verification.md) for simulator builds, Clang analysis, the SPM test-copy workaround, and device-only checks.
