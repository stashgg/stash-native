# Android implementation

`StashNativeCard` is the public Java facade. Every open operation receives an `Activity`; callers no longer register an ambient activity. `StashNativeCardPlugin` serializes work onto the main thread, owns presentation identity/listeners, launches checkout, and manages browser lifecycle.

## Presentation and state

Checkout runs in a non-exported activity in the host app process. It owns the WebView and a `StashPresentationController`. `StashPresentationOptions` snapshots and normalizes configuration before asynchronous dispatch. `StashPresentationState` separates the selected card state from temporary keyboard accommodation. `StashCheckoutSizing` resolves logical constraints, available bounds, and separating fold regions; `StashSheetLayout` draws the surface.

The presentation controller owns motion. It observes actual root layout and insets, retargets geometry after changes, and coordinates web scrolling with card dragging. It must not leave multiple width/height animators writing obsolete targets during window resizing. Per-frame WebView layout during sheet height animation is deliberate; replacing it requires measured evidence that viewport/scroll correctness is preserved.

Cards adapt between attached and floating placement. See [responsive presentation](responsive-presentation.md).

WindowManager supplies fold layout information. Handle viewport-related configuration changes in place to retain the same WebView and its form state. Genuine process death ends the live session; do not replay navigation or payments as restoration. Keep mutable state scoped to its activity/plugin owner and invalidate late callbacks on teardown.

## Bridge and navigation

`StashWebViewUtils.JS_SDK_SCRIPT` defines the public page API. `StashCheckoutJsInterface` routes native calls on the UI thread. `StashCheckoutWebViewSupport` handles WebView setup, navigation, loading errors, and external-link decisions. `StashContentSizeSupport` installs the optional card-only document reporter after navigation and rejects stale document/viewport measurements.

`StashWebInteractionSupport` keeps checkout at native scale and suppresses browser menus on noneditable content. It installs at document start when the WebView provider supports that feature, with navigation callbacks as a fallback. Form fields retain native selection, clipboard actions, and autofill, including embedded payment fields. Sheet gestures cancel when another finger touches or processing starts.

`StashCheckoutBridge` delivers session-tagged events within the host process. Receivers are non-exported on API 33+, with a host-specific signature permission on API 21–32. Do not add an `android:process` isolate.

`StashNativeBrowserProxyActivity` owns Custom Tabs results. `StashCustomTabsEngagement` supplies the browser-close fallback; hosts do not forward activity results. `StashUrlLauncher` degrades to the system browser when optional Browser classes are absent. Optional runtime reflection catches `Throwable`.

The opt-in keep-alive service uses a short foreground notification during external payment. It does not guarantee process survival. Existing foreground-service declarations are merged into the host; integrators enabling it must configure their app's service declarations and notification behaviour appropriately.

## Dependencies

The SDK builds with JDK 17, Java 8 source compatibility, compile SDK 34, and minimum API 21. Required libraries are Core 1.12.0, WebKit 1.11.0, WindowManager 1.4.0 and `window-java:1.4.0`, CameraX camera-camera2/camera-lifecycle/camera-view 1.4.2, and ZXing core 3.5.3. These CameraX versions preserve the SDK's API 21 and compile SDK 34 baseline. The WindowManager graph includes Kotlin stdlib, coroutines, window-core, collections, and annotations. Browser 1.7.0 remains optional. Sample UI dependencies are not SDK runtime dependencies.

Standalone AAR consumers must declare these dependencies themselves. Inspect the resolved graph when changing versions; WindowManager 1.5.x requires API 23. Preserve narrow consumer shrinking rules and test packaged AAR consumers, including absent/older optional Browser versions.

## CodeLink

CodeLink uses the same activity, sheet layout, sizing, and presentation controller as checkout. It always follows the host orientation, including landscape-only games. `StashCodeLinkSupport` owns a camera lifecycle and binds only its own CameraX preview and analysis use cases; it never calls `unbindAll`. `PreviewView` uses its texture implementation so the camera obeys the card's clipping and transformations. Preview and analysis share a viewport, and scan coordinates are remapped after rotation or resizing. Late frames from earlier geometry are discarded.

Only the scan frame is decoded, using the Y plane on a serial executor. Reconstructed QR corners must fit inside that region. QR decoding is local and has no Play Services or model-download requirement. The library declares optional camera hardware and `CAMERA`; only CodeLink requests permission. Camera errors leave the card open and report `onCodeLinkError` once per session. Denied permission offers Settings and resumes scanning after access is granted.

The first nonempty QR payload stops capture and shows the white checkmark and Connected confirmation. `onQrCodeScanned` runs after dismissal and cleanup; no payment or dismissal callback accompanies a successful scan. Explicit dismissal cancels a pending scan callback, and reset stays silent. The confirmation pauses while the activity is backgrounded and respects disabled animations and accessibility reading time. Both the error and result events retain the existing session-tagged callback transport.

## Validation

Run JUnit/Robolectric, SDK release and sample debug/release builds, Android Lint, Checkstyle, and minified consumer builds. Pure geometry tests cover dimensions and density; Robolectric exercises lifecycle and callback seams. Neither replaces real WebView checks.

The independent `Android/modern-host` fixture consumes the built AAR with target-36/37 variants. It exercises newer host policies without changing the shipping SDK's compile baseline. See its README for isolated toolchain and output commands.

Use the responsive test page and test checkout links on actual emulator/device WebViews. Check rotation, continuous resizing, fold/unfold, keyboard, browser return, processing locks, and state preservation. Inspect merged manifests to establish the host's actual target SDK. Record unavailable API 21 device checks separately from newer runtime results.
