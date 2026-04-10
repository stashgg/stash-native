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

- [Compatibility, platform API & store review](COMPATIBILITY.md)
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
| **forcePortrait**   | Forces the card to display in portrait mode, even if the host app or game is locked to landscape orientation. |
| **Phone Dimensions**           | `cardHeightRatioPortrait`, `cardWidthRatioLandscape`, `cardHeightRatioLandscape` (0.1–1.0).                                                                    |
| **Tablet Dimensions**          | `tabletWidthRatioPortrait`, `tabletHeightRatioPortrait`, `tabletWidthRatioLandscape`, `tabletHeightRatioLandscape` (0.1–1.0).                                  |
| **backgroundColor** | Color hex string (e.g. `#RRGGBB`). When set, the sheet background follows that color instead of system light/dark. Keep unset for best experience. Only for custom UIs, leave unchanged.            |


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

#### Forcing Portrait Orientation

Use `forcePortrait` when the host game or app is **landscape-only** but you want the Stash card in portrait.

**Android:** When `forcePortrait` is `true`, checkout opens in `StashNativeCardPortraitActivity`, a dedicated activity that is **portrait-locked** in the library manifest. It runs in the **same process** as your app (including Unity and Unreal), so the engine is not moved to an isolated process. If the user was in landscape, the system rotates into portrait when that activity is shown; the SDK coordinates layout with that transition. 

**iOS:** When `forcePortrait = true`, the SDK unlocks portrait for its **card and browser** windows at runtime including in landscape-locked Unity, Unreal, and custom game engine builds. **No AppDelegate changes or Info.plist edits are required.** The SDK installs a one-time hook on `application:supportedInterfaceOrientationsForWindow:` that returns all orientations for the SDK's own windows while passing through the original result for every other window. The game remains landscape-locked; only the card/browser window can rotate to portrait.

**Swizzling Opting out (iOS, advanced):** If you manage orientation unlocking yourself, disable the automatic hook and call the SDK bridge method manually:

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

> **Visual artifacts and sizing:** Forcing portrait from a landscape-locked host can still produce **visual artifacts** (brief flicker, letterboxing, dimmed regions, or system-bar quirks) on some devices and OS versions—the library **cannot** fully guarantee a seamless transition in every case. For landscape-locked games we recommend sizing the card to cover the full screen.

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

Centered modal on all devices. Same layout on phone and tablet; allows dynamic rotation. Suited for channel selection or an alternative checkout style.

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

Requirements, OS matrices, testing environments, known limitations, and platform API / store compliance notes are documented in **[COMPATIBILITY.md](COMPATIBILITY.md)**.

---

## Versioning

This package follows [Semantic Versioning](https://semver.org/) (major.minor.patch):

- **Major**: Breaking changes
- **Minor**: New features (backward compatible)
- **Patch**: Bug fixes

## Support

- Documentation: [https://docs.stash.gg](https://docs.stash.gg)
- Email: [developers@stash.gg](mailto:developers@stash.gg)

