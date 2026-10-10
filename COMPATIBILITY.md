# Compatibility

## Build and runtime requirements

| Target | Runtime minimum | Build |
|---|---|---|
| iOS SDK and sample | iOS 15 | Xcode 27.1 for Duo APIs and full validation; SPM or XCFramework |
| Android SDK and sample | API 21 | JDK 17, compile SDK 34, Gradle 8.5 |
| Modern Android host fixture | API 21 | JDK 17, compile SDK 37, target 36/37 variants |

Xcode 27.1 rejects deployment targets below iOS 15. SDK compilation and runtime minimum are distinct: availability guards retain the iOS 15 path while newer systems use native sheet detents and reserved-region information. The host executable must also link against SDK 27.1 for full Duo layout adoption.

Android checkout runs in the host app process. It must not acquire an `android:process` isolate. Orientation preferences do not guarantee rotation: foldable, multi-window, and newer target-SDK policies may ignore them.

## Dependencies and packaging

Android's required runtime dependencies are Core 1.12.0, WebKit 1.11.0, WindowManager 1.4.0 and its Java adapter, CameraX 1.4.2 (camera2, lifecycle, and view), and ZXing Core 3.5.3. CodeLink uses CameraX and ZXing. Their resolved graph includes Kotlin and coroutines. The SDK does not require AppCompat, Material, or Compose. Browser 1.7.0 is optional for Custom Tabs; absent browser support falls back to `ACTION_VIEW`.

Plain AAR files do not carry transitive dependency metadata. Include the dependencies from the [README](README.md#android). Keep consumer shrinking rules and test a minified host; an unminified SDK AAR does not mean internal classes will escape the host shrinker.

The iOS public header supports ARC and non-ARC consumers. New implementation files must belong to both the Xcode project and SPM source tree.

## Presentation behaviour

- All iOS cards use one native sheet controller. Regular width and height use a form sheet with one system large detent; compact layouts use custom detents on iOS 16+ and system detents on iOS 15.
- Card sizing uses current window geometry rather than a device category.
- On iPhone, the portrait preference uses an SDK-owned window and scoped app/scene delegate orientation hooks (method swizzling). Calls for game windows retain the host's orientation policy. iOS 16+ uses scene geometry requests; iOS 15 uses a device-orientation KVC fallback. The SDK restores orientation before handing the key window back to the game. Rotation remains best effort. iPad ignores the preference, and CodeLink follows the host orientation.
- Hardware keyboards, floating keyboards, asymmetric safe areas, and separating hinges require runtime tests alongside pure geometry tests.
- A process killed by the OS cannot preserve a live payment page. Recovery must not replay a payment request or report success without a payment result.

## Verification limits

A supported minimum is a deployment contract, not a claim that every OS, vendor WebView, payment provider, or game engine has been tested. Record the exact runtime and SDK for each verification run. New simulator tests do not establish iOS 15 or Android 21 runtime behaviour.

The repository contains native samples and test fixtures. Unity/Unreal wrapper migration, physical-device payment-provider checks, and desktop host validation are separate work. macOS Catalyst is not an established supported target for the iOS library.

For Apple Silicon emulators, validate the chosen GPU backend with a real WebView. Some configurations boot slowly or fail WebView GPU initialization; an emulator boot screenshot is not a sample-app pass.
