# Stash Native SDK -- Project Rules

Checkout SDK embedding webviews in native containers (card/modal/browser) for in-app purchases. Consumed by native apps and game engine wrappers (Unity, Unreal).

## Architecture

- iOS: Objective-C singleton (`StashNativeCard`), 3 source files sharing state via file-scope statics + extern. SPM + xcframework distribution.
- Android: Java singleton facade (`StashNativeCard`) -> internal plugin (`StashNativeCardPlugin`) -> portrait activity. AAR distribution.
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
Chrome Custom Tabs use `startActivityForResult` from the host `Activity` (`setActivity`). Integrators must override `onActivityResult` and call `StashNativeCard.getInstance().onActivityResult(...)`. `StashNativeCardPortraitActivity` forwards automatically for in-SDK launches from portrait.

### iOS File-Scope Statics
`StashNativeCard.m` has ~40 file-scope statics extern'd by `StashNativeCardViewControllers.m` and `StashNativeCardWebViewDelegates.m`. Do not refactor these without understanding the coupling. Declarations in `StashNativeCardPrivate.h`.

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
