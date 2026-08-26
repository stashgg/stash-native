# Stash Native SDK -- Project Rules

Checkout SDK embedding webviews in native containers (card/modal/browser) for in-app purchases. Consumed by native apps and game engine wrappers (Unity, Unreal).

## Architecture

- iOS: Objective-C singleton (`StashNativeCard`) plus focused units (Configs, Geometry, Theme, ViewUtils, Internal, ViewControllers, WebViewDelegates). Shared state is defined in `StashNativeCard.m` and extern'd via `StashNativeCardPrivate.h`. SPM + xcframework distribution.
- Android: Java singleton facade (`StashNativeCard`) -> internal plugin (`StashNativeCardPlugin`) -> portrait activity. Extracted logic lives in package-private `Stash*Support`/`StashCheckoutSizing` helpers; mutable state stays on the owning activity/plugin. AAR distribution.
- Desktop (`Desktop/`): shared pure-C++ contract (`Desktop/shared`: `window.stash_sdk` shim, URL / theme / config helpers, the `Session` state machine that holds the mobile callback contract) built into two hosts, `Desktop/macOS` (Objective-C++ `StashNativeCard` AppKit facade over WKWebView, SwiftPM package rooted at `Desktop/`) and `Desktop/Windows` (WebView2, CMake, header-only `StashNativeCard.hpp` facade). Both export the identical C ABI in `Desktop/include/StashNativeDesktop.h` for game engines. Distribution: `StashNativeDesktop.bundle` / `StashNativeDesktop.dll` from `release.yml`.
- JS bridge: `window.stash_sdk` injected into webview on every platform. Spec in `docs/stash-sdk-js.md`.

## Critical Constraints

- No breaking API changes. All changes must be backwards-compatible.
- ARC and non-ARC compatibility on iOS (Unreal Engine requirement). The delegate property uses `__has_feature(objc_arc)` guard.
- Game engine wrapper compatibility: Unity, Unreal 4, Unreal 5. The checkout activity runs in the same process as the host (no `android:process` isolate).
- No emojis in code, comments, or documentation.
- Comments should be terse and direct, like from a human programmer. No AI-style verbose explanations.

## Build Commands

```
# Android
cd Android && JAVA_HOME=/path/to/jdk17 ./gradlew :stashnative:assembleRelease
cd Android && JAVA_HOME=/path/to/jdk17 ./gradlew :sample:installDebug
cd Android && JAVA_HOME=/path/to/jdk17 ./gradlew :stashnative:testDebugUnitTest

# iOS (build library)
cd iOS/StashNative && xcodebuild -project StashNative.xcodeproj -scheme StashNative -sdk iphoneos

# iOS (run tests -- must use SPM path without .xcodeproj)
# Tests run via xcodebuild test on a copy without the .xcodeproj, or through CI
cd iOS/StashNative && xcodebuild test -scheme StashNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# iOS (sample app)
cd iOS/Sample/StashNativeSample && xcodebuild -scheme StashNativeSample -destination 'id=<device-udid>' -allowProvisioningUpdates build

# Desktop shared contract tests (any OS with cmake)
cmake -S Desktop/shared -B Desktop/shared-build && cmake --build Desktop/shared-build && ctest --test-dir Desktop/shared-build

# macOS (package, tests, bundle, sample)
cd Desktop && swift build && swift test
Desktop/macOS/build_bundle.sh          # universal bundle + export check
cd Desktop && swift run StashNativeDesktopSample [-stash-auto local|remote|secure]

# Windows (Visual Studio C++ workload, cmake fetches the WebView2 SDK)
cmake -S Desktop/Windows -B Desktop/Windows/build -A x64 && cmake --build Desktop/Windows/build --config Release
ctest --test-dir Desktop/Windows/build -C Release
Desktop\Windows\build\Sample\Release\StashNativeDesktopSample.exe -stash-auto local
```

## Code Patterns

### JS Bridge
Changes to `window.stash_sdk` MUST be mirrored on every platform and `docs/stash-sdk-js.md` updated. Source locations:
- Android: `StashWebViewUtils.JS_SDK_SCRIPT`
- iOS: `stashSDKScript` in `StashNativeCard.m`
- Desktop (both OSes): `Desktop/shared/StashSdkScript.h` (one body, a per-OS transport prelude)

### Desktop callback contract
Once-guards, the `dialogDismissed` paths, the purchase-processing lock, external-browser handoff and navigation policy live in `Desktop/shared/StashDesktopSession.cpp`, not in the OS hosts. Change the mobile behaviour and the session together; `Desktop/shared/tests` pins the session flows. Ratios are accepted and ignored on desktop (fixed card / modal size, `resolveSurfaceSize`).

### Config Ratios
All sizing ratios (card, modal, popup) must be clamped to [0.1, 1.0] on both platforms. Android clamps in `StashNativeCardPlugin.openCard/openModal`. iOS clamps implicitly through the init defaults.

### Safe Area / Insets
Card dimensions MUST respect device safe areas (notches, status bar, navigation bar):
- iOS: `getSafeAreaTopForView()` / `getSafeAreaBottomForView()`, `_cardSafeAreaTop` clamp
- Android: `StashWindowCompat.getSystemTopInsetPx()` / `getSystemBottomInsetPx()` with fallback chain

### Reflection / Missing Libraries (Android)
All reflection calls MUST catch `Throwable` and degrade gracefully. No missing dependency can crash the SDK. Follow patterns in `StashWindowCompat` and `StashUrlLauncher`.

### ProGuard
`consumer-rules.pro` keeps only the public API surface. Internal classes are obfuscated. Do not add blanket keep rules.

### Broadcast Bridge (Android)
`StashNativeCardPortraitActivity` communicates with `StashNativeCardPlugin` via package-local broadcasts in the same process. Receiver registered with `ContextCompat.registerReceiver()` and `RECEIVER_NOT_EXPORTED`.

### Custom Tabs result (Android)
Chrome Custom Tabs results are consumed internally by `StashNativeBrowserProxyActivity`; hosts do not override `onActivityResult` or forward anything. Browser-close detection combines the proxy result with the engagement-session fallback in `StashCustomTabsEngagement`.

### iOS Shared State
All shared mutable state and cross-file constants are DEFINED in `StashNativeCard.m` (single home) and DECLARED extern in `StashNativeCardPrivate.h`, which also holds the internal class interfaces (view controllers, webview delegates, `StashNativeCardInternal`). The other `.m` files import Private.h and never define shared state. Constants used by only one file stay `static` in that file. Do not duplicate definitions or re-scope state without understanding this coupling. New `.m` files must also be added to `StashNative.xcodeproj` (SPM globs automatically; the pbxproj does not).

## Version Management
Version string is hardcoded per platform and gated by `release.yml` against the first `CHANGELOG.md` header. When tagging a release, update:
- `iOS/StashNative/Sources/StashNative/StashNativeCard.m` (`+sdkVersion` return value)
- `Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCard.java` (`SDK_VERSION` constant)
- `Desktop/include/StashNativeDesktopVersion.h` (`STASH_NATIVE_DESKTOP_VERSION`, returned by both desktop hosts)

## Testing
- Android: JUnit tests in `stashnative/src/test/`. Run with `./gradlew :stashnative:testDebugUnitTest`. Uses `returnDefaultValues = true` since android.* stubs are not available in local JVM.
- iOS: XCTest in `StashNative/Tests/StashNativeTests/`. Must be run on iOS Simulator via xcodebuild (not `swift test` which targets macOS).
- Desktop: pure-C++ parity tests in `Desktop/shared/tests` (run on every OS in CI), XCTest in `Desktop/macOS/Tests` (`swift test`), `Desktop/Windows/tests` on `windows-latest`. The samples' `-stash-auto local|secure` runs are the real WKWebView / WebView2 smoke tests and run in `main.yml`.
- Most functionality depends on webviews and cannot be unit tested. Manual testing via sample apps on device is the primary QA method.

## Sample Apps
Reference implementations under `Android/sample/`, `iOS/Sample/`, `Desktop/macOS/Sample/` and `Desktop/Windows/Sample/`. Keep them clean -- they are the first thing integrators see.
