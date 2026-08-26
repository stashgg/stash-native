# Stash for Android / iOS / Windows / macOS [![Lint](https://github.com/stashgg/stash-native/actions/workflows/lint.yml/badge.svg)](https://github.com/stashgg/stash-native/actions/workflows/lint.yml) [![Build & Deploy](https://github.com/stashgg/stash-native/actions/workflows/main.yml/badge.svg)](https://github.com/stashgg/stash-native/actions/workflows/main.yml)


<p align="left">
  <img src="https://github.com/stashgg/stash-native/raw/main/.github/assets/stash_native.png" width="128" height="128" alt="Stash Native Logo"/>
</p>


The stash-native package makes it simple to add Stash in-app purchases (IAPs) and webshops to your game or app. It delivers seamless, native-like payment flows and selection dialogs, which appear as system dialogs on Android and iOS and as a card over the game window on Windows and macOS, through lightweight embedded webviews, while providing direct callbacks to your application. Library is delivered as AAR for Android, xcframework for iOS, a DLL for Windows and a bundle for macOS.

---

## Table of contents

**Overview**

- [Game engine wrappers](#wrappers)
- [Downloads](#downloads)
- [Sample apps](#sample-apps)

**Setup**

- [Installation](#installation)
  - [Android](#android)
  - [iOS](#ios)
  - [Windows](#windows)
  - [macOS](#macos)

**API**

- [Presentation modes](#presentation-modes)
  - [openCard](#opencard)
    - [Config](#config)
    - [Callbacks](#callbacks)
  - [openModal](#openmodal)
    - [Config](#config-1)
    - [Callbacks](#callbacks-1)
  - [openBrowser](#openbrowser)
- [Webview inspection (debug / testing)](#webview-inspection-debug--testing)

**Reference**

- [Compatibility, platform API & store review](COMPATIBILITY.md)
- [Versioning](#versioning)
- [Support](#support)

---

## Game Engine Wrappers

If you're using one of the game engines listed below, we offer dedicated wrappers for this library. These wrappers provide ready-to-use interfaces for integrating Stash features into your project.

|                                                                                             | Engine        | Repository                                              | Compatibility                                    |
| ------------------------------------------------------------------------------------------- | ------------- | ------------------------------------------------------- | ------------------------------------------------ |
| <img src=".github/assets/stash_unity.png" alt="Unity Icon" width="64" height="64">          | Unity         | [stash-unity](https://github.com/stashgg/stash-unity)   | Unity 2019.4+ (LTS recommended)                  |
| <img src=".github/assets/stash_unreal.png" alt="Unreal Engine Icon" width="64" height="64"> | Unreal Engine | [stash-unreal](https://github.com/stashgg/stash-unreal) | Unreal Engine 4.27+ (4.x/5.x branches available)  |

For building your own wrappers, see [docs/building-wrappers.md](./docs/building-wrappers.md) for integration patterns and a integration checklist.

---

## Downloads

Latest pre-built binaries are always available on [Releases Page](https://github.com/stashgg/stash-native/releases):

- **Android**: `stashnative-release.aar` (or `StashNative-<tag>.aar` from releases)
- **iOS**: `StashNative.xcframework.zip`
- **Windows**: `StashNativeDesktop-<tag>-win64.zip` (`StashNativeDesktop.dll`, import library, headers)
- **macOS**: `StashNativeDesktop-<tag>-macos.zip` (`StashNativeDesktop.bundle`, universal arm64 + x86_64, headers)

---

## Sample apps & Testing

All platforms include sample apps: `./Android/sample/`, `./iOS/Sample/` (open `StashNativeSample.xcodeproj` in Xcode), `./Desktop/macOS/Sample/` (`cd Desktop && swift run StashNativeDesktopSample`) and `./Desktop/Windows/Sample/` (built by the Windows CMake project). Run the Android sample with `./gradlew :sample:installDebug` from the `Android/` directory. The desktop samples generate checkout links, exercise every presentation mode against the offline test pages, and run hands-free proofs with `-stash-auto local|remote|secure`.

> **Note: Android emulator (Apple Silicon):** On arm64-v8a AVDs, the default GPU mode (`auto`) can yield an empty `GL_VERSION` and crash the WebView GPU thread. Use **`swangle`** (`-gpu swangle` or `hw.gpu.mode=swangle` in `~/.android/avd/<your-avd>.avd/config.ini`).

Stash also host a test card on https://test.stashpreview.com/ that can be used with all presentation methods below to test callbacks and exceptions without real Stash URLs.

---

## Installation

### Android

1. Download `StashNative-<tag>.aar` from [GitHub Releases](https://github.com/stashgg/stash-native/releases) and add it to your project (e.g. `libs/`).
2. In your app's `build.gradle`:

```groovy
dependencies {
    implementation files('libs/StashNative-<tag>.aar')
    implementation 'androidx.appcompat:appcompat:1.6.1'
    // Also include androidx.browser for Chrome Custom Tabs on external checkout flows.
    // implementation 'androidx.browser:browser:1.7.0'
}
```

To build the AAR locally: `cd Android && ./gradlew :stashnative:assembleRelease` (output in `stashnative/build/outputs/aar/`).

### iOS

**XCFramework (recommended):** Download `StashNative.xcframework.zip` from [GitHub Releases](https://github.com/stashgg/stash-native/releases), unzip it, add `StashNative.xcframework` to your Xcode project, and under **Frameworks, Libraries, and Embedded Content** set it to **Embed & Sign**.

**Swift Package Manager:** In Xcode choose File → Add Packages... and add `https://github.com/stashgg/stash-native.git`, then select the StashNative package for your target.

### Windows

Download `StashNativeDesktop-<tag>-win64.zip` from [GitHub Releases](https://github.com/stashgg/stash-native/releases). Ship `StashNativeDesktop.dll` next to your executable and either link `StashNativeDesktop.lib` with the header-only C++ facade `StashNativeCard.hpp`, or load the DLL at run time and bind the `StashNativeDesktop_*` exports from `StashNativeDesktop.h` (what the game-engine wrappers do). Requires the WebView2 Evergreen runtime on the player's machine (preinstalled on Windows 11 and updated Windows 10; otherwise bundle the [Evergreen bootstrapper](https://developer.microsoft.com/microsoft-edge/webview2/)). Call every API from the thread that owns your window's message loop.

To build locally: `cmake -S Desktop/Windows -B Desktop/Windows/build -A x64 && cmake --build Desktop/Windows/build --config Release` (Visual Studio C++ workload; the WebView2 SDK is fetched from NuGet).

### macOS

Download `StashNativeDesktop-<tag>-macos.zip` from [GitHub Releases](https://github.com/stashgg/stash-native/releases). Put `StashNativeDesktop.bundle` inside your app bundle (for example `Contents/PlugIns`), load it with `dlopen` and bind the `StashNativeDesktop_*` exports, or use the Objective-C `StashNativeCard` facade from `StashNativeCard.h`. Native apps can also add the Swift package rooted at `Desktop/` in this repository (`StashNativeDesktop` product). macOS 11+, universal.

To build locally: `Desktop/macOS/build_bundle.sh` (plain clang, no Xcode project).

---

## Presentation modes

The library exposes three ways to open Stash URLs (Stash Pay & Stash Webshop): **openCard** (in-app sheet / drawer; on desktop a card over the game window), **openModal** (in-app centered popup), and **openBrowser** (Chrome Custom Tabs on Android, SFSafariViewController on iOS, the system browser on Windows and macOS).

<p align="center">
  <img src="https://raw.githubusercontent.com/stashgg/stash-native/refs/heads/main/.github/assets/presentations.png" alt="Presentation Modes" width="840" />
</p>


---

## openCard

Drawer-style card: slides up from the bottom on phones and shows centered on tablets (Mimics native Apple Pay, Google Pay experience). Suited for Stash Pay payment links or pre-authenticated webshop links.

**Android**

```java
StashNativeCard.CardConfig config = new StashNativeCard.CardConfig();  // or null for defaults
StashNativeCard.getInstance().openCard("https://test.stashpreview.com", config);
```

**iOS (Swift)**

```swift
let config = StashNativeCardConfig()  // or nil for defaults
StashNativeCard.sharedInstance().openCard(withURL: "https://test.stashpreview.com", config: config)
```

**iOS (Objective-C)**

```objc
StashNativeCardConfig *config = [[StashNativeCardConfig alloc] init];  // or nil for defaults
[[StashNativeCard sharedInstance] openCardWithURL:@"https://test.stashpreview.com" config:config];
```

**Windows (C++)**

```cpp
stash::StashNativeCardConfig config;  // or omit for defaults
stash::StashNativeCard::getInstance().openCard("https://test.stashpreview.com", &config);
```

**macOS (Swift)**

```swift
let config = StashNativeCardConfig()  // or nil for defaults
StashNativeCard.sharedInstance().openCard(withURL: "https://test.stashpreview.com", config: config)
```

On desktop the card is a fixed 480 x 720 pt surface centred over the game window (clamped to the window, never below 400 x 500 pt) with a native trust header showing the checkout host; the ratio fields below are accepted and ignored, `forcePortrait` has no effect.

### Config

Pass a `CardConfig` (or `nil`/`null` for defaults) to configure presentation.


| Aspect              | Description                                                                                                                                                    |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **forcePortrait**   | Forces the card to display in portrait mode, even if the host app or game is locked to landscape orientation. Read section below first ! |
| **Phone Dimensions** | `cardHeightRatioPortrait`, `cardWidthRatioLandscape`, and `cardHeightRatioLandscape` (values from 0.1 to 1.0). All dimensions are within the device's safe area.
| **Tablet Dimensions**          | `tabletWidthRatioPortrait`, `tabletHeightRatioPortrait`, `tabletWidthRatioLandscape`, `tabletHeightRatioLandscape` (0.1–1.0). All dimensions are within the device's safe area.                                  |
| **autoClose**       | Default `true`. When `false`, the card stays open after the page reports payment success or failure -- callbacks still fire immediately. Call `dismiss()` (or have the page call `window.close()`) when you're ready to close. Useful if your checkout page shows its own confirmation UI. |
| **backgroundColor** | Color hex string (e.g. `#RRGGBB`). When set, the sheet background follows that color instead of system light/dark. Only for custom UIs, leave unchanged by default.            |


**Android**

```java
StashNativeCard.CardConfig config = new StashNativeCard.CardConfig();
config.forcePortrait = false;
config.cardHeightRatioPortrait = 0.68f;
// ... tabletWidthRatioPortrait, tabletHeightRatioPortrait, etc. (see table above)
stashNative.openCard(url, config);
```

**iOS (Swift)**

```swift
let config = StashNativeCardConfig()
config.forcePortrait = false
config.cardHeightRatioPortrait = 0.68
// ... tabletWidthRatioPortrait, tabletHeightRatioPortrait, etc. (see table above)
stashNative.openCard(withURL: url, config: config)
```

### Forcing Portrait Orientation

> **Warning:** Forcing portrait from landscape mode may cause brief visual artifacts on some devices. For landscape-locked games, size the card to fill the screen for best results.

Use `forcePortrait` when the host game or app is **landscape** but you want the Stash card displayed in portrait.

**Android:** If `forcePortrait` is `true`, checkout opens in a dedicated portrait-locked activity that runs in your app's process and auto-rotates as needed.

**iOS:** If `forcePortrait` is `true`, the SDK unlocks portrait for its own windows at runtime, even in landscape-locked games. No AppDelegate or Info.plist changes required; only the card/browser window can rotate.

**Opting out (iOS, advanced):** If you manage orientation unlocking yourself on iOS, disable the automatic hook and call the SDK bridge method manually:

```objc
// Before first openCard call:
StashNativeCard.sharedInstance().disableAutoOrientationUnlock = YES;

// In your AppDelegate:
- (UIInterfaceOrientationMask)application:(UIApplication *)app
    supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    UIInterfaceOrientationMask stash = [StashNativeCard supportedInterfaceOrientationsForWindow:window];
    if (stash) return stash;
    return UIInterfaceOrientationMaskLandscape; // your game default
}
```

> **Known edge case (iOS 16+):** If your project explicitly sets `UISceneSupportedInterfaceOrientations` to landscape-only inside the scene configuration in `Info.plist`, iOS enforces that at the scene level and the automatic hook cannot override it. Remove that key or add `UIInterfaceOrientationPortrait` to it.

### Landscape Backdrop (Android, Optional)

When `forcePortrait` is `true` and the host app is in landscape, Android rotates the activity to portrait. During this transition the underlying app surface may appear black or distorted. To mask this, you can optionally pass a screenshot of the current screen to the SDK **before** calling `openCard`. The SDK will display it as a full-screen backdrop behind the dim overlay, creating a seamless visual transition.

This is **completely optional** — if no backdrop is set, the card opens normally with the standard dim overlay.

**Android (native)**

```java
// Capture however you prefer — e.g. PixelCopy, View.drawingCache, or your own render target
Bitmap screenshot = captureCurrentScreen();

StashNativeCard.setBackdropBitmap(screenshot);  // static, call before openCard
StashNativeCard.getInstance().openCard(url, config);
```

**Unity (C#)**

```csharp
// Capture at end of frame
yield return new WaitForEndOfFrame();
Texture2D tex = new Texture2D(Screen.width, Screen.height, TextureFormat.RGB24, false);
tex.ReadPixels(new Rect(0, 0, Screen.width, Screen.height), 0, 0);
tex.Apply();
byte[] png = tex.EncodeToPNG();
Destroy(tex);

// Pass to the SDK via JNI
using (var cls = new AndroidJavaClass("com.stash.stashnative.StashNativeCard")) {
    cls.CallStatic("setBackdropBytes", (object)png);
}

// Then open the card as usual
stashNative.Call("openCard", url, config);
```

- The bitmap is consumed and recycled automatically by the SDK after use — no cleanup needed.
- `setBackdropBitmap(Bitmap)` accepts a pre-built Bitmap; `setBackdropBytes(byte[])` accepts PNG/JPEG bytes (convenient from JNI/Unity).
- The backdrop is rotated 90° and center-cropped to fill the portrait screen, matching the original scene as closely as possible.
- When dismissed, the dim overlay fades out; the backdrop stays visible while the checkout activity returns to landscape, then the activity finishes (with a timeout fallback if landscape is not reported).

### Callbacks


| Event            | Description                                                                                                                                   |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Payment Success  | Called when the payment completes successfully. Includes detail about order in the callback payload.                                          |
| Purchase Processing / Processing Completed | Desktop only (C ABI and `StashNativeCardListener`): the page reported that a purchase is processing / finished processing. On mobile this state is exposed through `isPurchaseProcessing`. |
| Payment Failure  | Called when the payment fails.                                                                                                                |
| Dialog Dismissed | Called when the user dismisses the dialog.                                                                                                    |
| External payment | Called when external payment browser has started (CCT / Safari view controller). |
| Browser Closed   | Called when external payment browser was closed (CCT / Safari view controller). Not available on desktop (the system browser reports no close). |
| Opt-In Response  | Called when a channel selection response is received.                                                                                         |
| Page Loaded      | Called when the page finishes loading (with load time in ms).                                                                                 |
| Network Error    | Called when the page load fails (no connection, HTTP error, timeout).                                                                         |


Set a listener (Android) or delegate (iOS) before calling `openCard` or `openModal`. Same callback interface is used for both.

**Android** — implement `StashNativeCardListener` (or extend `StashNativeCardListenerAdapter` to override only the callbacks you need):

```java
StashNativeCard.getInstance().setActivity(this);
StashNativeCard.getInstance().setListener(new StashNativeCard.StashNativeCardListener() {
    @Override
    public void onPaymentSuccess(String order) {
        // Handle successful payment
    }

    @Override
    public void onPaymentFailure() {
        // Handle failed payment
    }

    ....
});
```

On Android, `onBrowserClosed` works out of the box with no host-activity changes — the SDK owns the Chrome Custom Tabs result lifecycle via an internal proxy activity. The system-browser (`ACTION_VIEW`) fallback continues to use lifecycle-based detection.

**iOS (Swift)** — set the delegate and implement `StashNativeCardDelegate` (all methods are optional):

```swift
StashNativeCard.sharedInstance().delegate = self
// In your class (e.g. ViewController):
extension YourViewController: StashNativeCardDelegate {
    func stashNativeCardDidCompletePayment(withOrder order: String?) {
        // Handle successful payment
    }
    func stashNativeCardDidFailPayment() {
        // Handle failed payment
    }
    ....
}
```

**iOS (Objective-C)** — set the delegate and implement the optional protocol methods:

```objc
[StashNativeCard sharedInstance].delegate = self;

// In your class:
- (void)stashNativeCardDidCompletePaymentWithOrder:(NSString *)order {
    // Handle successful payment
}
- (void)stashNativeCardDidFailPayment {
    // Handle failed payment
}
....
```

**Windows (C++)** — implement `StashNativeCardListener` (every method has an empty default):

```cpp
class Listener : public stash::StashNativeCardListener {
    void onPaymentSuccess(const std::string &order) override { /* Handle successful payment */ }
    void onPaymentFailure() override { /* Handle failed payment */ }
    // ...
};
Listener listener;
stash::StashNativeCard::getInstance().setListener(&listener);
```

**macOS** — the same `StashNativeCardDelegate` as iOS (minus the browser-closed method); set `StashNativeCard.sharedInstance().delegate`. Game engines get every callback through the single C event callback of `StashNativeDesktop.h` instead.

---

## openModal

Centered modal on all devices. Same layout on phone and tablet; allows dynamic resize and screen rotation. Suited for channel selection or an alternative checkout style.

**Android**

```java
StashNativeCard.ModalConfig config = new StashNativeCard.ModalConfig();  // or null for defaults
StashNativeCard.getInstance().openModal("https://test.stashpreview.com", config);
```

**iOS (Swift)**

```swift
let config = StashNativeModalConfig()  // or nil for defaults
StashNativeCard.sharedInstance().openModal(withURL: "https://test.stashpreview.com", config: config)
```

**iOS (Objective-C)**

```objc
StashNativeModalConfig *config = [[StashNativeModalConfig alloc] init];  // or nil for defaults
[[StashNativeCard sharedInstance] openModalWithURL:@"https://test.stashpreview.com" config:config];
```

**Windows (C++)**

```cpp
stash::StashNativeModalConfig config;
stash::StashNativeCard::getInstance().openModal("https://test.stashpreview.com", &config);
```

**macOS (Swift)**

```swift
StashNativeCard.sharedInstance().openModal(withURL: "https://test.stashpreview.com", config: StashNativeModalConfig())
```

On desktop the modal is a fixed 480 x 600 pt surface over the game window; `allowDismiss = false` removes the close button and ignores backdrop clicks and Esc (`window.close()` from the page still closes it). Ratios are ignored.

### Config

Pass a `ModalConfig` (or `nil`/`null`) to control dismiss behavior and sizing. Pass `nil`/`null` for defaults. 


| Aspect              | Description                                                                                                                   |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| **Behavior**        | `allowDismiss` (default `true`).                                                                                              |
| **Phone**           | `phoneWidthRatioPortrait`, `phoneHeightRatioPortrait`, `phoneWidthRatioLandscape`, `phoneHeightRatioLandscape` (0.1–1.0).     |
| **Tablet**          | `tabletWidthRatioPortrait`, `tabletHeightRatioPortrait`, `tabletWidthRatioLandscape`, `tabletHeightRatioLandscape` (0.1–1.0). |
| **autoClose**       | Default `true`. When `false`, the modal stays open after the page reports payment success or failure -- callbacks still fire immediately. Call `dismiss()` (or have the page call `window.close()`) when you're ready to close. |
| **backgroundColor** | Same optional HTML hex as on `CardConfig` / `StashNativeCardConfig`. Omit for SDK defaults.                                   |


**Android**

```java
StashNativeCard.ModalConfig config = new StashNativeCard.ModalConfig();
config.allowDismiss = true;
// ... phoneWidthRatioPortrait, phoneHeightRatioPortrait, tablet ratios, etc. (see table above)
stashNative.openModal(url, config);
```

**iOS (Swift)**

```swift
let config = StashNativeModalConfig()
config.allowDismiss = true
// ... phoneWidthRatioPortrait, phoneHeightRatioPortrait, tablet ratios, etc. (see table above)
stashNative.openModal(withURL: url, config: config)
```

### Callbacks

Same as **openCard**: same events and the same listener/delegate. Set it once as shown in the [Callbacks](#callbacks) section under openCard; it receives events for both card and modal calls.

---

## openBrowser

Opens the URL in the platform browser: on Android, Chrome Custom Tabs when `androidx.browser` is on the classpath, otherwise the system browser (`ACTION_VIEW`); on iOS, `SFSafariViewController`. No in-app UI. `onBrowserClosed` fires when the browser is dismissed (Android: via an internal proxy activity, no host-activity changes needed; system-browser fallback uses lifecycle detection). On iOS, `stashNativeCardDidCloseBrowser` fires when Safari is dismissed. Use when you only need a simple browser view. openBrowser can also be used as a fallback method for openCard and openModal.

**Android**

```java
StashNativeCard.getInstance().openBrowser("https://test.stashpreview.com");
```

**iOS (Swift)**

```swift
StashNativeCard.sharedInstance().openBrowser(withURL: "https://test.stashpreview.com")
// Optionally dismiss when handling a deeplink:
StashNativeCard.sharedInstance().closeBrowser()
```

**iOS (Objective-C)**

```objc
[[StashNativeCard sharedInstance] openBrowserWithURL:@"https://test.stashpreview.com"];
// Optionally dismiss when handling a deeplink:
[[StashNativeCard sharedInstance] closeBrowser];
```

On iOS, **closeBrowser()** dismisses the Safari view. On Android, **closeBrowser()** is a no-op (Chrome Custom Tabs cannot be closed by the app).

**Windows / macOS**

```cpp
stash::StashNativeCard::getInstance().openBrowser("https://test.stashpreview.com");   // Windows
```

```swift
StashNativeCard.sharedInstance().openBrowser(withURL: "https://test.stashpreview.com")   // macOS
```

Desktop opens the system browser and has no browser-closed callback and no `closeBrowser`.

### **Android Keep-alive service (Optional)**

When the user leaves your app for Chrome Custom Tabs or the system browser, Android may kill your app on memory pressure. You can opt in to a short **foreground service** that shows a low-priority notification and improves survival on budget / Android Go–class devices:

```java
StashNativeCard.getInstance().setKeepAliveEnabled(true);
StashNativeCard.KeepAliveConfig cfg = new StashNativeCard.KeepAliveConfig();
cfg.notificationTitle = "Payment in progress";
cfg.notificationText = "Tap to return to the app";
cfg.notificationIconResId = R.drawable.ic_notification; // optional; use 0 for library default
StashNativeCard.getInstance().setKeepAliveConfig(cfg);
```

- **Default:** keep-alive is **off**.
- **Manifest:** required `foregroundService` entries are auto-merged; no manual changes needed. On Android 14+, service auto-stops after ~3 minutes or when your app resumes.
- **Opt out:** remove `com.stash.stashnative.StashKeepAliveService` via `tools:node="remove"` in your manifest.
- **Notifications:** no `POST_NOTIFICATIONS` permission is added; on Android 13+ notifications may be hidden unless requested, but the service still works.

- **Permissions & Google Play:** With keep-alive, your manifest adds `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_SHORT_SERVICE`. In Google Play Console, declare foreground service usage and the shortService type, and describe its use (e.g., keeping application alive after browser launch).

## Webview inspection (debug / testing)

The SDK can make its checkout webviews inspectable so you can debug the checkout page with Safari Web Inspector / `chrome://inspect`, or drive it from automated UI tests (e.g. Appium). It is **off by default** and the flag name is identical on both platforms. Set it once, before opening any checkout.

**Android**

```java
StashNativeCard.setInspectableWebViewsEnabled(true);
```

Enabling calls `WebView.setWebContentsDebuggingEnabled(true)` (process-global) as each checkout webview is configured.

**iOS (Swift)**

```swift
StashNativeCard.setInspectableWebViewsEnabled(true)
```

On iOS 16.4+ the SDK's `WKWebView`s are created with `inspectable = true`.

**Windows / macOS**

```cpp
stash::StashNativeCard::setInspectableWebViewsEnabled(true);   // Windows: Edge DevTools on the checkout webview
```

```swift
StashNativeCard.setInspectableWebViewsEnabled(true)   // macOS 13.3+: Safari Web Inspector
```

Game engines use `StashNativeDesktop_SetInspectableWebViewsEnabled(1)`.

> **Do not enable this in production.** It exposes the checkout webview contents to remote inspection. Gate it behind a debug/QA build flag; the sample apps enable it only for local testing.

---

Requirements, OS matrices, testing environments, known limitations, and platform API / store compliance notes are documented in **[COMPATIBILITY.md](COMPATIBILITY.md)**.

---

## Versioning

This package follows [Semantic Versioning](https://semver.org/) (major.minor.patch):

- **Major**: Breaking changes
- **Minor**: New features (backward compatible)
- **Patch**: Bug fixes

Query the SDK version at runtime:

```java
// Android
String version = StashNativeCard.getVersion();
```

```swift
// iOS (Swift)
let version = StashNativeCard.sdkVersion()
```

```objc
// iOS (Objective-C)
NSString *version = [StashNativeCard sdkVersion];
```

```cpp
// Windows (C++), or StashNativeDesktop_GetVersion() from the C ABI on either desktop OS
const char *version = stash::StashNativeCard::getVersion();
```

```swift
// macOS (Swift)
let version = StashNativeCard.sdkVersion()
```

---

## Support

- Documentation: [https://docs.stash.gg](https://docs.stash.gg)
- Email: [developers@stash.gg](mailto:developers@stash.gg)

