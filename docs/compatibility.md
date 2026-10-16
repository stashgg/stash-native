---
title: Compatibility
nav_order: 5
description: Supported OS versions, toolchains, dependencies, permissions, OS-version-specific behavior, and verification limits.
---

# Compatibility

## Requirements

| Target | Minimum runtime | Build toolchain | Distribution |
|---|---|---|---|
| iOS SDK | iOS 15 | Xcode 27.1 with the iOS 27.1 SDK for releases. Swift tools 5.5 for the package manifest. | Swift Package Manager, XCFramework |
| Android SDK | API 21 | JDK 17, Gradle 8.5, Android Gradle Plugin 8.1.1, compile SDK 34, Java 8 source compatibility | AAR |
| iOS sample | iOS 15 | Xcode 27.1 | Source |
| Android sample | API 21 | Same as the SDK; target SDK 34 | Source |
| Modern Android host fixture | API 21 | JDK 17, Android Gradle Plugin 9.1.1, Gradle 9.3.1, compile SDK 37, targets 36 and 37 | Consumes the release AAR |

## iOS

- Xcode 27.1 rejects deployment targets below iOS 15.
- The SDK compiles against the newest SDK and gates newer APIs with availability checks, so the iOS 15 code path stays in the binary. Compiling with a newer SDK does not verify behavior on iOS 15; test on that runtime.
- iPhone Duo display adaptation requires the host app to be linked against the iOS 27.1 SDK. Updating only the framework does not opt an older host build into the new display behavior. Host apps should adopt the scene lifecycle and allow the window resizing modes they intend to support.
- Hosted CI builds with Xcode 26.6 to exercise the compile guards. Release packaging requires Xcode 27.1 and SDK 27.1. Stable hosted CI does not count as Duo validation.
- The public header supports ARC and manual reference counting consumers. CI builds the library both ways.
- Mac Catalyst is not a supported target.

### Behavior by iOS version

| iOS | Behavior |
|---|---|
| 15 | Compact cards use the system `medium` and `large` detents, or `large` only in compact height. Page scrolling expands the sheet natively. Portrait rotation uses the `UIDevice` orientation fallback. |
| 16 | Compact cards use custom resting and expanded detents. Upward content drags expand resting cards. Portrait rotation uses `UIWindowScene.requestGeometryUpdate`. |
| 16.4 | `setInspectableWebViewsEnabled` makes checkout WebViews inspectable |
| 17 | Sheets set `prefersPageSizing = NO`; the keyboard layout guide ignores the bottom safe area |
| 18 | A `UIUpdateLink` refreshes keyboard occlusion and scroll repairs once per frame. Earlier versions rely on keyboard notifications and layout passes. |
| 26 | Initial loading shows the native sheet material behind a transparent WebView. Compact iPhone card entrances get the horizontal animation correction. |
| 26.1 | Floating sheets use the system material effect on detents while loading |
| 27 | Sheets request centered placement. Portrait presentation also hooks the scene delegate's orientation method. |
| 27.1 | Active reserved regions (occlusion and division kinds, as on iPhone Duo) are excluded from the card's available bounds |

## Android

- Checkout runs in the host app process. Do not add an `android:process` attribute to the SDK activities; the SDK manifest removes it.
- Orientation preferences are requests. Foldable postures, multi-window, and newer target SDK policies can ignore them; the card then lays out in the actual window.
- Inspect the merged manifest to learn the host's real target SDK. The SDK library declares target SDK 34, but the host's value decides platform behavior.

### Behavior by API level

| API | Behavior |
|---|---|
| 21 to 22 | The WebView uses a hardware layer so rounded card corners clip correctly. Reveal readiness uses a delayed recheck instead of the visual state callback. |
| 21 to 23 | Only the legacy `shouldOverrideUrlLoading(WebView, String)` runs; subframe web navigations cannot be distinguished. Deep links are still intercepted. |
| 21 to 32 | Internal broadcasts are protected by the `<applicationId>.permission.STASH_NATIVE_INTERNAL` signature permission |
| 24 | Telemetry reports `presentation.multiWindow`; portrait preference is released in multi-window mode |
| 26 | Renderer loss is reported through `onRenderProcessGone`: one rebuild after an OS kill, network error otherwise. Telemetry reports the WebView provider package and version. |
| 29 | `onPageCommitVisible` marks the main-frame commit; earlier versions use load progress. Telemetry reports thermal status. |
| 30 | `triggerHaptic()` uses `CONFIRM`; earlier versions use `VIRTUAL_KEY` |
| 33 | The broadcast receiver is registered as not exported. Back uses `OnBackInvokedCallback`. |
| 34 | The keep-alive service starts with the `shortService` foreground type and stops on timeout |

CSS `env(safe-area-inset-*)` support depends on the WebView provider, not the API level. [Android documents full support from Chromium M144](https://developer.android.com/develop/ui/views/layout/webapps/understand-window-insets).

## Dependencies

### iOS

System frameworks only: UIKit, WebKit, SafariServices, AVFoundation, QuartzCore. No third-party code.

### Android

| Dependency | Version | Required | Notes |
|---|---|---|---|
| `androidx.core:core` | 1.12.0 | Yes | `api` dependency. Compatibility helpers still tolerate the older Core versions that some engine builds resolve. |
| `androidx.webkit:webkit` | 1.11.0 | Yes | `api` dependency |
| `androidx.window:window`, `window-java` | 1.4.0 | Yes | Brings Kotlin stdlib, coroutines, `window-core`, collections, and annotations. Version 1.5 requires API 23. |
| `androidx.browser:browser` | 1.7.0 | No | Custom Tabs. Without it, the system browser via `ACTION_VIEW`. |
| `androidx.camera:camera-camera2`, `camera-lifecycle`, `camera-view` | 1.4.2 | CodeLink only | 1.4.2 keeps the API 21 and compile SDK 34 baseline |
| `com.google.zxing:core` | 3.5.3 | CodeLink only | Local QR decoding |

The SDK does not use AppCompat, Material Components, or Jetpack Compose.

A plain AAR carries no transitive dependency metadata. Declare the base group and every optional group you use; see [Installation](usage/installation.md#android). Check the resolved dependency graph after changing versions, and test a minified host with and without the optional groups.

## Permissions and manifest entries

| Platform | Entry | Needed for |
|---|---|---|
| iOS | `NSCameraUsageDescription` (host Info.plist) | CodeLink |
| Android | `INTERNET` | Checkout |
| Android | `CAMERA`, optional camera features | CodeLink. Removable with `tools:node="remove"` when CodeLink is unused. |
| Android | `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SHORT_SERVICE` | Keep-alive service |
| Android | `<applicationId>.permission.STASH_NATIVE_INTERNAL` (signature) | Internal broadcasts, API 21 to 32 |
| Android | `<queries>` for `CustomTabsService` | Custom Tabs discovery, API 30+ |

The SDK requests camera access only when CodeLink opens. Checkout and browser presentations never request it.

## Runtime techniques

Listed for security and app review teams.

| Platform | Technique | When |
|---|---|---|
| iOS | Adds or replaces `application:supportedInterfaceOrientationsForWindow:` on the app delegate class, and on iOS 27+ `supportedInterfaceOrientationsForWindowScene:` on the scene delegate class. Other windows forward to the original implementation. | First portrait card or browser on iPhone |
| iOS | Sets `UIDevice` `orientation` through key-value coding | Portrait on iOS 15 only |
| iOS | Creates a runtime subclass of each WebKit content view class to return no input accessory view | Checkout WebViews only. WebKit's shared classes and host views are untouched. |
| iOS | Adds an equal and opposite Core Animation counter-animation to a recognized UIKit horizontal scale-compensation spring. UIKit's own animation stays in place. | First entrance of a compact iPhone card on iOS 26+, except with Reduce Motion |
| Android | Reflection into `androidx.browser` Custom Tabs classes, catching `Throwable` | Browser launches |
| Android | Reflective loading of the CodeLink implementation | CodeLink |
| Android | `addJavascriptInterface` object `StashAndroid` | Checkout WebViews |

## Engine wrappers

| Wrapper | Repository | Native SDK bound today |
|---|---|---|
| Unity | [stash-unity](https://github.com/stashgg/stash-unity) | 2.3.1 |
| Unreal Engine | [stash-unreal](https://github.com/stashgg/stash-unreal) | 2.3.0 |

3.0 is not a drop-in binary replacement. Wrappers stay on 2.x until their bindings are migrated. See [Building wrappers](building-wrappers.md) and [Migrating to 3.0](migration-3.0.md).

## Behavior limits

- Hardware keyboards, floating keyboards, asymmetric safe areas, and separating hinges need runtime tests in addition to the pure geometry tests.
- A process killed by the OS cannot keep a live payment page. Recovery must not replay a payment request or report success without a payment result.
- A checkout website can require a newer WebView engine than the SDK's API 21 minimum. Test the oldest WebView provider you support.

## Verification limits

A supported minimum is a deployment contract. It is not a claim that every OS version, WebView provider, payment provider, or game engine has been tested. Record the exact OS, SDK, and WebView version for each verification run. Results from new simulators do not establish behavior on iOS 15 or API 21.

The repository contains native samples and test fixtures. Wrapper migration, physical-device payment-provider checks, and desktop host validation are tracked separately.

On Apple Silicon Android emulators, verify that the chosen GPU backend can render a real WebView. Some configurations boot slowly or fail WebView GPU initialization. An emulator boot screenshot is not a sample-app pass.
