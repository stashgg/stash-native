# Stash for Android / iOS [![Lint](https://github.com/stashgg/stash-native/actions/workflows/lint.yml/badge.svg)](https://github.com/stashgg/stash-native/actions/workflows/lint.yml) [![Build & Deploy](https://github.com/stashgg/stash-native/actions/workflows/main.yml/badge.svg)](https://github.com/stashgg/stash-native/actions/workflows/main.yml)


<p align="left">
  <img src="https://github.com/stashgg/stash-native/raw/main/.github/assets/stash_native.png" width="128" height="128" alt="Stash Native Logo"/>
</p>


The stash-native package makes it simple to add Stash in-app purchases (IAPs) and webshops to your game or app. It delivers seamless, native-like payment flows and selection dialogs, which appear as system dialogs on Android and iOS through lightweight embedded webviews, while providing direct callbacks to your application.

## Table of contents

**Overview**

- [Platforms](#platforms)
- [Game engine wrappers](#wrappers)
- [Downloads](#downloads)
- [Sample apps](#sample-apps)

**Setup**

- [Installation](#installation)
  - [Android](#android)
  - [iOS](#ios)

**API**

- [Presentation modes](#presentation-modes)
  - [openCard](#opencard)
    - [Config](#config)
    - [Callbacks](#callbacks)
  - [openModal](#openmodal)
    - [Config](#config-1)
    - [Callbacks](#callbacks-1)
  - [openBrowser](#openbrowser)

**Reference**

- [Compatibility](#compatibility)
  - [Android](#android-1)
  - [iOS](#ios-1)
  - [Internal testing](#testing)
  - [Known limitations](#known-limitations)
- [Versioning](#versioning)
- [Support](#support)

## Platforms

| Platform | Description                  |
| -------- | ---------------------------- |
| Android  | Android library (AAR).       |
| iOS      | iOS framework (XCFramework). |

## Game Engine Wrappers

If you're using one of the game engines listed below, we offer dedicated wrappers for this library. These wrappers provide ready-to-use interfaces for integrating Stash features into your project, along with added development tools such as full flow testing directly in the Engine Editor.

|                                                                                             | Engine        | Repository                                              | Compatibility                   |
| ------------------------------------------------------------------------------------------- | ------------- | ------------------------------------------------------- | ------------------------------- |
| <img src=".github/assets/stash_unity.png" alt="Unity Icon" width="64" height="64">          | Unity         | [stash-unity](https://github.com/stashgg/stash-unity)   | Unity 2019.4+ (LTS recommended) |
| <img src=".github/assets/stash_unreal.png" alt="Unreal Engine Icon" width="64" height="64"> | Unreal Engine 5 | [stash-unreal (main)](https://github.com/stashgg/stash-unreal)                 | Unreal Engine 5.0+                |
| <img src=".github/assets/stash_unreal.png" alt="Unreal Engine Icon" width="64" height="64"> | Unreal Engine 4 | [stash-unreal (4.27-plus)](https://github.com/stashgg/stash-unreal/tree/4.27-plus) | Unreal Engine 4.27-plus           |

For custom engines or third-party frameworks, see [docs/building-wrappers.md](./docs/building-wrappers.md) for integration patterns and a new-wrapper checklist.

## Downloads

Latest pre-built binaries are always available on [Releases Page](https://github.com/stashgg/stash-native/releases):

- **Android**: `stashnative-release.aar` (or `StashNative-<tag>.aar` from releases)
- **iOS**: `StashNative.xcframework.zip`

## Sample apps

Both platforms include sample apps under `./Android/sample/` and `./iOS/Sample/` (open `StashNativeSample.xcodeproj` in Xcode). Run the Android sample with `./gradlew :sample:installDebug` from the `Android/` directory.

> **Note: Android emulator (Apple Silicon):** On arm64-v8a AVDs, the default GPU mode (`auto`) can yield an empty `GL_VERSION` and crash the WebView GPU thread. Use **`swangle`** (`-gpu swangle` or `hw.gpu.mode=swangle` in `~/.android/avd/<your-avd>.avd/config.ini`).

---

## Installation

### Android

1. Download `StashNative-<tag>.aar` from [GitHub Releases](https://github.com/stashgg/stash-native/releases) and add it to your project (e.g. `libs/`).
2. In your app's `build.gradle`:

```groovy
dependencies {
    implementation files('libs/StashNative-<tag>.aar')
    implementation 'androidx.appcompat:appcompat:1.6.1'
    // Optional: add androidx.browser for Chrome Custom Tabs on external URLs; without it the SDK uses ACTION_VIEW.
    // implementation 'androidx.browser:browser:1.7.0'
}
```

To build the AAR locally: `cd Android && ./gradlew :stashnative:assembleRelease` (output in `stashnative/build/outputs/aar/`).

### iOS

**XCFramework (recommended):** Download `StashNative.xcframework.zip` from [GitHub Releases](https://github.com/stashgg/stash-native/releases), unzip it, add `StashNative.xcframework` to your Xcode project, and under **Frameworks, Libraries, and Embedded Content** set it to **Embed & Sign**.

**Swift Package Manager:** In Xcode choose File → Add Packages... and add `https://github.com/stashgg/stash-native.git`, then select the StashNative package for your target.

**Manual integration:** Copy all files from `StashNative/Sources/StashNative/` into your project, add them to your target, and link **SafariServices.framework** and **WebKit.framework**.

---

## Presentation modes

The library exposes three ways to open Stash URLs (Stash Pay & Stash Webshop): **openCard** (sheet / drawer), **openModal** (centered popup), and **openBrowser** (Custom Tabs or system browser on Android when `androidx.browser` is absent; SFSafariViewController on iOS). Use **openCard** or **openModal** for full in-app experience; use **openBrowser** for a standard browser-based flows.

<p align="center">
  <img src="https://raw.githubusercontent.com/stashgg/stash-native/refs/heads/main/.github/assets/presentations.png" alt="Presentation Modes" width="840" />
</p>




### openCard

Drawer-style card: slides up from the bottom on phones, centered on tablets (Mimics native Apple Pay, Google Pay experience). Suited for Stash Pay payment links or channel selection. [Integrating Stash Pay](https://docs.stash.gg/guides/stash-pay/integration)

**Android**

```java
StashNativeCard.CardConfig config = new StashNativeCard.CardConfig();  // or null for defaults
StashNativeCard.getInstance().openCard("https://testcard.stashpreview.com", config);
```

**iOS (Swift)**

```swift
let config = StashNativeCardConfig()  // or nil for defaults
StashNativeCard.sharedInstance().openCard(withURL: "https://testcard.stashpreview.com", config: config)
```

**iOS (Objective-C)**

```objc
StashNativeCardConfig *config = [[StashNativeCardConfig alloc] init];  // or nil for defaults
[[StashNativeCard sharedInstance] openCardWithURL:@"https://testcard.stashpreview.com" config:config];
```

#### Config

Pass a `CardConfig` (or `nil`/`null`) to configure presentation. Pass `nil`/`null` for defaults.


| Aspect              | Description                                                                                                                                                    |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **forcePortrait**   | `true`: card opens portrait-locked (separate activity on Android, portrait-only on iOS). `false` (default): card appears in current orientation as an overlay. |
| **Phone**           | `cardHeightRatioPortrait`, `cardWidthRatioLandscape`, `cardHeightRatioLandscape` (0.1–1.0).                                                                    |
| **Tablet**          | `tabletWidthRatioPortrait`, `tabletHeightRatioPortrait`, `tabletWidthRatioLandscape`, `tabletHeightRatioLandscape` (0.1–1.0).                                  |
| **backgroundColor** | Color hex string (e.g. `#RRGGBB`). When set, the sheet background follows that color instead of system light/dark. Keep unset for best experience.             |


> **Background color:** Use `backgroundColor` only when you need the native shell to match **Stash Pay with a custom theme**. For the **default Stash theme**, leave it unset so the standard light/dark experience stays aligned with the system.

#### Portrait orientation on iOS (landscape-locked games)

When `forcePortrait = true` on iOS, the SDK automatically unlocks portrait orientation for its card and browser windows at runtime — including in landscape-locked Unity, Unreal, and custom game engine builds. **No AppDelegate changes or Info.plist edits are required.**

The SDK installs a one-time hook on `application:supportedInterfaceOrientationsForWindow:` that returns all orientations for the SDK's own windows while passing through the original result for every other window. The game remains landscape-locked; only the card/browser window can rotate to portrait.

**Opting out** (advanced): If you manage orientation unlocking yourself, disable the automatic hook and call the SDK bridge method manually:

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

> **Known edge case (iOS 16+):** If your project explicitly sets `UISceneSupportedInterfaceOrientations` to landscape-only inside the scene configuration in `Info.plist`, iOS enforces that at the scene level and the automatic hook cannot override it. Remove that key or add `UIInterfaceOrientationPortrait` to it. This key is **not** set by default in Unity or Unreal projects.

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

#### Callbacks


| Event            | Description                                                                                                                                   |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Payment Success  | Called when the payment completes successfully. Includes detail about order in the callback payload.                                          |
| Payment Failure  | Called when the payment fails.                                                                                                                |
| Dialog Dismissed | Called when the user dismisses the dialog.                                                                                                    |
| External payment | Some payment methods requires transacting outside the app (Klarna, Bitcoin etc.). This callback fires when external payment flow has started. |
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

    @Override
    public void onDialogDismissed() {
        // User closed the card/modal
    }

    @Override
    public void onOptInResponse(String optinType) {
        // Channel selection response (e.g. "stash_pay", "native_iap")
    }

    @Override
    public void onPageLoaded(long loadTimeMs) {
        // Page finished loading
    }

    @Override
    public void onNetworkError() {
        // Load failed (no connection, HTTP error, or timeout)
    }

    @Override
    public void onExternalPayment(String url) {
        // Checkout opened an external URL (Such as Gpay, Klarna, Crypto.)
        // This means that the payment will be finalized in browser or other app and user will be redirected back using deeplinks.
    }
});
```

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
    func stashNativeCardDidDismiss() {
        // User closed the card/modal
    }
    func stashNativeCardDidReceiveOpt(in optinType: String) {
        // Channel selection response
    }
    func stashNativeCardDidLoadPage(_ loadTimeMs: Double) {}
    func stashNativeCardDidEncounterNetworkError() {
        // Load failed (no connection, HTTP error, or timeout)
    }
    func stashNativeCardDidRequestExternalPayment(with url: String) {
        // Checkout opened an external URL (Such as Gpay, Klarna, Crypto.)
        // This means that the payment will be finalized in browser or other app and user will be redirected back using deeplinks.
    }
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
- (void)stashNativeCardDidDismiss {
    // User closed the card/modal
}
- (void)stashNativeCardDidReceiveOptIn:(NSString *)optinType {
    // Channel selection response
}
- (void)stashNativeCardDidLoadPage:(double)loadTimeMs {}
- (void)stashNativeCardDidEncounterNetworkError {
    // Load failed
}
- (void)stashNativeCardDidRequestExternalPaymentWithURL:(NSString *)url {
    // Checkout opened an external URL (Such as Gpay, Klarna, Crypto.)
   // This means that the payment will be finalized in browser or other app and user will be redirected back using deeplinks.
}
```

---

### openModal

Centered modal on all devices. Same layout on phone and tablet; resizes on rotation. Suited for channel selection or an alternative checkout style. [Stash Pay Opt-In](https://docs.stash.gg/guides/stash-pay/opt-in)

**Android**

```java
StashNativeCard.ModalConfig config = new StashNativeCard.ModalConfig();  // or null for defaults
StashNativeCard.getInstance().openModal("https://testcard.stashpreview.com", config);
```

**iOS (Swift)**

```swift
let config = StashNativeModalConfig()  // or nil for defaults
StashNativeCard.sharedInstance().openModal(withURL: "https://testcard.stashpreview.com", config: config)
```

**iOS (Objective-C)**

```objc
StashNativeModalConfig *config = [[StashNativeModalConfig alloc] init];  // or nil for defaults
[[StashNativeCard sharedInstance] openModalWithURL:@"https://testcard.stashpreview.com" config:config];
```

#### Config

Pass a `ModalConfig` (or `nil`/`null`) to control dismiss behavior and sizing. Pass `nil`/`null` for defaults. 


| Aspect              | Description                                                                                                                   |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| **Behavior**        | `allowDismiss` (default `true`).                                                                                              |
| **Phone**           | `phoneWidthRatioPortrait`, `phoneHeightRatioPortrait`, `phoneWidthRatioLandscape`, `phoneHeightRatioLandscape` (0.1–1.0).     |
| **Tablet**          | `tabletWidthRatioPortrait`, `tabletHeightRatioPortrait`, `tabletWidthRatioLandscape`, `tabletHeightRatioLandscape` (0.1–1.0). |
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

#### Callbacks

Same as **openCard**: same events and the same listener/delegate. Set it once as shown in the [Callbacks](#callbacks) section under openCard; it receives events for both card and modal calls.

---

### openBrowser

Opens the URL in the platform browser: on Android, Chrome Custom Tabs when `androidx.browser` is on the classpath, otherwise the system browser (`ACTION_VIEW`); on iOS, `SFSafariViewController`. No in-app UI, no callbacks. Use when you only need a simple browser view. openBrowser can also be used as a fallback method for openCard and openModal.

**Android**

```java
StashNativeCard.getInstance().openBrowser("https://testcard.stashpreview.com");
```

**Optional: Keep-alive service (low-memory Android / Android Go devices)**

When the user leaves your app for Chrome Custom Tabs or the system browser, Android may kill your app on memory pressure. You can opt in to a short **foreground service** that shows a low-priority notification and improves survival on budget / Android Go–class devices:

```java
StashNativeCard.getInstance().setKeepAliveEnabled(true);
StashNativeCard.KeepAliveConfig cfg = new StashNativeCard.KeepAliveConfig();
cfg.notificationTitle = "Payment in progress";
cfg.notificationText = "Tap to return to the app";
cfg.notificationIconResId = R.drawable.ic_notification; // optional; use 0 for library default
StashNativeCard.getInstance().setKeepAliveConfig(cfg);
```

- **Default:** keep-alive is **off**; no behavior change for existing apps.
- **Manifest:** the library merges `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SHORT_SERVICE`, and a non-exported `StashKeepAliveService` with `foregroundServiceType="shortService"`. You do not need to add these by hand. On Android 14+, `shortService` has a system-enforced time limit (about three minutes); the service is stopped when the user returns to your app (`Activity` resume).
- **Opt out of the merged service** (e.g. policy reasons): in your app manifest, remove the library component, for example: `tools:node="remove"` on `com.stash.stashnative.StashKeepAliveService` (with `xmlns:tools` on the manifest root).
- **Notifications:** the library does not add `POST_NOTIFICATIONS`; on Android 13+ the notification may be hidden until your app requests that permission, but the foreground service can still run.

**iOS (Swift)**

```swift
StashNativeCard.sharedInstance().openBrowser(withURL: "https://testcard.stashpreview.com")
// Optionally dismiss when handling a deeplink:
StashNativeCard.sharedInstance().closeBrowser()
```

**iOS (Objective-C)**

```objc
[[StashNativeCard sharedInstance] openBrowserWithURL:@"https://testcard.stashpreview.com"];
// Optionally dismiss when handling a deeplink:
[[StashNativeCard sharedInstance] closeBrowser];
```

On iOS, **closeBrowser()** dismisses the Safari view. On Android, **closeBrowser()** is a no-op (Chrome Custom Tabs cannot be closed by the app).

---

## Compatibility

Requirements, OS coverage, vendor notes, and edge cases for each platform are below.

### Android


| Attribute    | Requirement                              |
| ------------ | ---------------------------------------- |
| Minimum SDK  | API 21 (Android 5.0 Lollipop)            |
| Target SDK   | API 34 (Android 14)                      |
| Compile SDK  | 34                                       |
| Java Version | Java 8 (source/target), JDK 17 for build |
| Architecture | armeabi-v7a, arm64-v8a, x86, x86_64      |


**Game engines (Unity, Unreal, and similar):** `openCard` and `openModal` present checkout in `StashNativeCardPortraitActivity` in the **same app process** as the host (no `android:process` isolate). That keeps a single OS process so engines such as Unity are not killed when checkout takes the foreground. Use the [Unity / Unreal wrappers](#wrappers) for integrated builds.

#### Android version support


| Android Version               | API Level | Status        | Compatibility Notes                                           |
| ----------------------------- | --------- | ------------- | ------------------------------------------------------------- |
| Android 14 (Upside Down Cake) | 34        | Full          | Target SDK                                                    |
| Android 13 (Tiramisu)         | 33        | Full          |                                                               |
| Android 12/12L                | 31-32     | Full          |                                                               |
| Android 11                    | 30        | Full          | Enhanced window insets (For phones with notch/camera cut-out) |
| Android 10                    | 29        | Full          | Added automatic dark mode support                             |
| Android 9 (Pie)               | 28        | Full          |                                                               |
| Android 8/8.1 (Oreo)          | 26-27     | Full          |                                                               |
| Android 7/7.1 (Nougat)        | 24-25     | Full          |                                                               |
| Android 6 (Marshmallow)       | 23        | Full          |                                                               |
| Android 5/5.1 (Lollipop)      | 21-22     | Full          | Minimum SDK                                                   |
| Android 4.4 and below         | <=20      | Not Supported |                                                               |


#### Vendor-specific support


| Vendor / Skin                  | Compatibility | WebView Source                      | Notes                                                                                   |
| ------------------------------ | ------------- | ----------------------------------- | --------------------------------------------------------------------------------------- |
| Google Pixel / Stock Android   | Full          | Google WebView (Play Store updates) | Reference implementation                                                                |
| Samsung (One UI / TouchWiz)    | Full          | Samsung Internet / Chrome WebView   | No known issues                                                                         |
| Xiaomi (MIUI)                  | Full          | Chrome WebView                      | Some MIUI versions show "battery optimization" warnings, during browser flows.          |
| OnePlus (OxygenOS)             | Full          | Chrome WebView                      | Stock-like behavior                                                                     |
| Oppo (ColorOS)                 | Full          | Chrome WebView                      |                                                                                         |
| Vivo (Funtouch OS)             | Full          | Chrome WebView                      |                                                                                         |
| Realme (Realme UI)             | Full          | Chrome WebView                      |                                                                                         |
| Huawei (EMUI, pre-2019)        | Full          | Google WebView                      | Huawei devices with Google Mobile Services                                              |
| Huawei (HarmonyOS/EMUI, 2019+) | **Partial**   | Huawei WebView                      | No Google Mobile Services; Chrome Custom Tabs unavailable; in-app WebView works         |
| Honor (post-Huawei)            | Full          | Chrome WebView                      | Devices with GMS                                                                        |
| Nokia (Android One)            | Full          | Google WebView                      | Stock Android, **use keep-alive service** recommended.                                  |
| Motorola                       | Full          | Chrome WebView                      | Near-stock Android                                                                      |
| LG                             | Full          | Chrome WebView                      | Legacy devices supported, **use keep-alive service** recommended.                       |
| Sony Xperia                    | Full          | Chrome WebView                      |                                                                                         |
| ASUS (ZenUI)                   | Full          | Chrome WebView                      |                                                                                         |
| Android Go Edition             | Supported     | Chrome WebView                      | Limited memory; may experience slower load times, **use keep-alive service**.           |
| Amazon Fire OS                 | **Partial**   | Amazon WebView                      | Non-standard WebView; openCard/openModal work; openBrowser falls back to system browser |


#### Dependencies


| Dependency                   | Version | Required | Purpose                                                                   |
| ---------------------------- | ------- | -------- | ------------------------------------------------------------------------- |
| androidx.appcompat:appcompat | 1.6.1+  | Yes      | Activity/Fragment support                                                 |
| androidx.browser:browser     | 1.7.0+  | No       | Chrome Custom Tabs when present; otherwise system browser (`ACTION_VIEW`) |


#### Feature restrictions by API level

Core functionality (slide-up card, modal, WebView, animations, payment callbacks) works identically across all supported Android versions (API 21+). The following features have graceful fallbacks on older Android versions:

**API 21-28 (Android 5.0-9.0)**

- Dark mode: Not automatically detected. Light mode used as fallback.
- Window insets: Uses legacy status bar handling, there might be slight overlaps with menu/status bar on some devices or
visual artefacts.

### iOS


| Attribute     | Requirement                                 |
| ------------- | ------------------------------------------- |
| Minimum iOS   | iOS 13.0                                    |
| Swift Version | 5.5+                                        |
| Xcode         | 13.0+                                       |
| Architecture  | arm64, arm64e (devices), x86_64 (simulator) |


#### iOS version support


| iOS Version      | Status        | Notes           |
| ---------------- | ------------- | --------------- |
| iOS 18.x         | Full          | Latest          |
| iOS 17.x         | Full          |                 |
| iOS 16.x         | Full          |                 |
| iOS 15.x         | Full          |                 |
| iOS 14.x         | Full          |                 |
| iOS 13.x         | Full          | Minimum version |
| iOS 12 and below | Not Supported |                 |


#### Device support


| Device Type                    | Status   | Notes                                       |
| ------------------------------ | -------- | ------------------------------------------- |
| iPhone (all models iOS 13+)    | Full     | Portrait/landscape, card slides from bottom |
| iPad                           | Full     | Centered presentation, all orientations     |
| iPad (Split View / Slide Over) | Full     | Responsive layout                           |
| Mac (Catalyst)                 | Untested | Should work; not officially tested yet      |


### Testing

We test this library using BrowserStack App Automate devices. Supported environments are listed in the [App Automate list of browsers and platforms](https://www.browserstack.com/list-of-browsers-and-platforms/app_automate).

### Known limitations

**Android**

- Huawei (2019+ without GMS): openBrowser uses system browser instead of Chrome Custom Tabs; other features work normally.
- Android Go: Performance may vary on low-memory devices (<1GB RAM), please use the [keep-alive service](#keep-alive-service).
- WebView updates: Devices without Play Store may have outdated WebView.
- Android emulator (arm64-v8a, Apple Silicon): see [Sample apps](#sample-apps) (GPU / `swangle` note)

**iOS**

- iOS 13: Automatic theme detection not available on iOS 13.0-13.3. Fixed in iOS 13.4
- **Landscape-locked games (Unity, Unreal):** `forcePortrait` works automatically — the SDK hooks `application:supportedInterfaceOrientationsForWindow:` to unlock portrait for its windows without affecting the rest of the app. The one exception is an explicit `UISceneSupportedInterfaceOrientations` key set to landscape-only in the scene configuration in `Info.plist` — see [Portrait orientation on iOS](#portrait-orientation-on-ios-landscape-locked-games) for the fix.

---

## Versioning

This package follows [Semantic Versioning](https://semver.org/) (major.minor.patch):

- **Major**: Breaking changes
- **Minor**: New features (backward compatible)
- **Patch**: Bug fixes

## Platform API & Store Compliance Notes

The SDK uses only public, documented APIs on both platforms. Below is a summary of techniques that are worth noting for store review awareness.

### iOS

| Technique | Purpose | Store Risk |
|-----------|---------|------------|
| AppDelegate swizzle (`application:supportedInterfaceOrientationsForWindow:`) | Allows portrait window in landscape-locked games | Very low |
| `UIDevice` KVC (`setValue:forKey:@"orientation"`) | Forces orientation on older iOS | Very low |
| Remove WKWebView keyboard toolbar | Prevents orientation issues in game engines | Very low |
| Deprecated API usage | Backwards compatibility | None |

### Android

| Technique | Purpose | Store Risk |
|-----------|---------|------------|
| `@JavascriptInterface` bridge | Native↔WebView communication | None |
| Reflection on AndroidX classes | Ensures compatibility with older libraries | None |
| Third-party cookies | Needed for payments and SSO | None |
| Short foreground service | Keeps app alive for payment in browser | None |

## Support

- Documentation: [https://docs.stash.gg](https://docs.stash.gg)
- Email: [developers@stash.gg](mailto:developers@stash.gg)

