# Stash Native SDK -- Project Rules

Checkout SDK embedding webviews in native containers (card/modal/browser) for in-app purchases. Consumed by native apps and game engine wrappers (Unity, Unreal).

## Architecture

- iOS: Objective-C singleton (`StashNativeCard`) plus focused units (Configs, Geometry, Theme, ViewUtils, Internal, ViewControllers, WebViewDelegates). Shared state is defined in `StashNativeCard.m` and extern'd via `StashNativeCardPrivate.h`. SPM + xcframework distribution.
- Android: Java singleton facade (`StashNativeCard`) -> internal plugin (`StashNativeCardPlugin`) -> portrait activity. Extracted logic lives in package-private `Stash*Support`/`StashCheckoutSizing` helpers; mutable state stays on the owning activity/plugin. AAR distribution.
- JS bridge: `window.stash_sdk` injected into webview on both platforms. Spec in `docs/stash-sdk-js.md`.

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
```

## Code Patterns

### JS Bridge
Changes to `window.stash_sdk` MUST be mirrored on both platforms and `docs/stash-sdk-js.md` updated. Source locations:
- Android: `StashWebViewUtils.JS_SDK_SCRIPT`
- iOS: `stashSDKScript` in `StashNativeCard.m`

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
Version string is hardcoded in both platforms. When tagging a release, update:
- `iOS/StashNative/Sources/StashNative/StashNativeCard.m` (`+sdkVersion` return value)
- `Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCard.java` (`SDK_VERSION` constant)

## Testing
- Android: JUnit tests in `stashnative/src/test/`. Run with `./gradlew :stashnative:testDebugUnitTest`. Uses `returnDefaultValues = true` since android.* stubs are not available in local JVM.
- iOS: XCTest in `StashNative/Tests/StashNativeTests/`. Must be run on iOS Simulator via xcodebuild (not `swift test` which targets macOS).
- Most functionality depends on webviews and cannot be unit tested. Manual testing via sample apps on device is the primary QA method.

## Sample Apps
Reference implementations under `Android/sample/` and `iOS/Sample/`. Keep them clean -- they are the first thing integrators see.
