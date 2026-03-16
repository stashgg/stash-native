# Stash for Android / iOS [![Lint](https://github.com/stashgg/stash-native/actions/workflows/lint.yml/badge.svg)](https://github.com/stashgg/stash-native/actions/workflows/lint.yml) [![Build & Deploy](https://github.com/stashgg/stash-native/actions/workflows/main.yml/badge.svg)](https://github.com/stashgg/stash-native/actions/workflows/main.yml)


<p align="left">
  <img src="https://github.com/stashgg/stash-native/raw/main/.github/assets/stash_native.png" width="128" height="128" alt="Stash Native Logo"/>
</p>


The stash-native package makes it simple to add Stash in-app purchases (IAPs) and webshops to your game or app. It delivers seamless, native-like payment flows and selection dialogs, which appear as system dialogs on Android and iOS through lightweight embedded webviews, while providing direct callbacks to your application.

## Platforms

| Platform | Description                  |
| -------- | ---------------------------- |
| Android  | Android library (AAR).       |
| iOS      | iOS framework (XCFramework). |

## Compatibility

### Android

| Attribute | Requirement |
|-----------|-------------|
| Minimum SDK | API 21 (Android 5.0 Lollipop) |
| Target SDK | API 34 (Android 14) |
| Compile SDK | 34 |
| Java Version | Java 8 (source/target), JDK 17 for build |
| Architecture | armeabi-v7a, arm64-v8a, x86, x86_64 |

#### Android Version Support

| Android Version | API Level | Status | Notes |
|-----------------|-----------|--------|-------|
| Android 14 (Upside Down Cake) | 34 | Full | Target SDK |
| Android 13 (Tiramisu) | 33 | Full | |
| Android 12/12L | 31-32 | Full | |
| Android 11 | 30 | Full | Enhanced window insets |
| Android 10 | 29 | Full | Dark mode support |
| Android 9 (Pie) | 28 | Full | |
| Android 8/8.1 (Oreo) | 26-27 | Full | |
| Android 7/7.1 (Nougat) | 24-25 | Full | |
| Android 6 (Marshmallow) | 23 | Full | |
| Android 5/5.1 (Lollipop) | 21-22 | Supported | Minimum SDK |
| Android 4.4 and below | <=20 | Not Supported | |

#### Vendor Compatibility (Android 7+)

| Vendor / Skin | Compatibility | WebView Source | Notes |
|---------------|--------------|----------------|-------|
| Google Pixel / Stock Android | Full | Google WebView (Play Store updates) | Reference implementation |
| Samsung (One UI / TouchWiz) | Full | Samsung Internet / Chrome WebView | No known issues |
| Xiaomi (MIUI) | Full | Chrome WebView | Some MIUI versions show battery optimization warnings |
| OnePlus (OxygenOS) | Full | Chrome WebView | Stock-like behavior |
| Oppo (ColorOS) | Full | Chrome WebView | |
| Vivo (Funtouch OS) | Full | Chrome WebView | |
| Realme (Realme UI) | Full | Chrome WebView | |
| Huawei (EMUI, pre-2019) | Full | Google WebView | Devices with GMS |
| Huawei (HarmonyOS/EMUI, 2019+) | Partial | Huawei WebView | No GMS; Chrome Custom Tabs unavailable; in-app WebView works |
| Honor (post-Huawei) | Full | Chrome WebView | Devices with GMS |
| Nokia (Android One) | Full | Google WebView | Stock Android |
| Motorola | Full | Chrome WebView | Near-stock Android |
| LG | Full | Chrome WebView | Legacy devices supported |
| Sony Xperia | Full | Chrome WebView | |
| ASUS (ZenUI) | Full | Chrome WebView | |
| Android Go Edition | Supported | Chrome WebView | Limited memory; may experience slower load times |
| Amazon Fire OS | Partial | Amazon WebView | Non-standard WebView; openCard/openModal work; openBrowser falls back to system browser |

#### Dependencies

| Dependency | Version | Required | Purpose |
|------------|---------|----------|---------|
| androidx.appcompat:appcompat | 1.6.1+ | Yes | Activity/Fragment support |
| androidx.browser:browser | 1.7.0+ | Yes | Chrome Custom Tabs (openBrowser) |

#### Feature Availability by API Level

| Feature | Min API | Notes |
|---------|---------|-------|
| In-app WebView (openCard, openModal) | 21 | Core functionality |
| Third-party cookies | 21 | Required for payment flows |
| Chrome Custom Tabs (openBrowser) | 21 | Requires compatible browser |
| Automatic dark mode detection | 29 | Falls back to light theme on older versions |
| Edge-to-edge display | 30 | Graceful fallback on older versions |

### iOS

| Attribute | Requirement |
|-----------|-------------|
| Minimum iOS | iOS 13.0 |
| Swift Version | 5.5+ |
| Xcode | 13.0+ |
| Architecture | arm64, arm64e (devices), x86_64 (simulator) |

#### iOS Version Support

| iOS Version | Status | Notes |
|-------------|--------|-------|
| iOS 18.x | Full | Latest |
| iOS 17.x | Full | |
| iOS 16.x | Full | |
| iOS 15.x | Full | |
| iOS 14.x | Full | |
| iOS 13.x | Supported | Minimum version |
| iOS 12 and below | Not Supported | |

#### Device Support

| Device Type | Status | Notes |
|-------------|--------|-------|
| iPhone (all models iOS 13+) | Full | Portrait/landscape, card slides from bottom |
| iPad | Full | Centered presentation, all orientations |
| iPad (Split View / Slide Over) | Full | Responsive layout |
| Mac (Catalyst) | Untested | Should work; not officially tested |

#### Framework Dependencies

| Framework | Required | Purpose |
|-----------|----------|---------|
| WebKit | Yes | WKWebView for in-app checkout |
| SafariServices | Yes | SFSafariViewController (openBrowser) |
| Foundation | Yes | Core framework |
| UIKit | Yes | UI components |

#### Language Support

| Language | Status | Notes |
|----------|--------|-------|
| Swift | Full | Native API |
| Objective-C | Full | Native API |
| ARC | Full | Automatic Reference Counting |
| Non-ARC | Full | Manual memory management (Unreal Engine compatibility) |

### Known Limitations

**Android**
- Huawei (2019+ without GMS): openBrowser uses system browser instead of Chrome Custom Tabs; other features work normally
- Android Go: Performance may vary on low-memory devices (<1GB RAM)
- WebView Updates: Devices without Play Store may have outdated WebView; recommend users update Android System WebView

**iOS**
- iOS 13 Dark Mode: Requires explicit theme parameter in URL; automatic detection not available on iOS 13.0-13.3

## Wrappers

If you're using one of the game engines listed below, we offer dedicated wrappers for this library. These wrappers provide ready-to-use interfaces for integrating Stash features into your project, along with added development tools—such as full flow testing directly in the Unity Editor.

|                                                                                             | Engine        | Repository                                              | Compatibility                   |
| ------------------------------------------------------------------------------------------- | ------------- | ------------------------------------------------------- | ------------------------------- |
| <img src=".github/assets/stash_unity.png" alt="Unity Icon" width="64" height="64">          | Unity         | [stash-unity](https://github.com/stashgg/stash-unity)   | Unity 2019.4+ (LTS recommended) |
| <img src=".github/assets/stash_unreal.png" alt="Unreal Engine Icon" width="64" height="64"> | Unreal Engine 5 | [stash-unreal (main)](https://github.com/stashgg/stash-unreal)                 | Unreal Engine 5.0+                |
| <img src=".github/assets/stash_unreal.png" alt="Unreal Engine Icon" width="64" height="64"> | Unreal Engine 4 | [stash-unreal (4.27-plus)](https://github.com/stashgg/stash-unreal/tree/4.27-plus) | Unreal Engine 4.27-plus           |

## Downloads

Latest pre-built binaries are always available on [Releases Page](https://github.com/stashgg/stash-native/releases):

- **Android**: `stashnative-release.aar` (or `StashNative-<tag>.aar` from releases)
- **iOS**: `StashNative.xcframework.zip`

## Sample Apps

Both platforms contain up-to-date sample apps that demonstrate the library usage and functions. You can run them from source 

- **Android**: `./Android/sample/` - Run with `./gradlew :sample:installDebug`
- **iOS**: `./iOS/Sample/` - Open `StashNativeSample.xcodeproj` in Xcode

or try them instantly in your browser using the Appetize online emulator:

- [Android Sample App](https://appetize.io/app/b_3l3fzg5qiahx6p2xpwp3kcirhy)
- [iOS Sample App](https://appetize.io/app/b_qbywqclhrfl6lk3i3ehovfqa2m)

---

# Installation

### Android

1. Download `StashNative-<tag>.aar` from [GitHub Releases](https://github.com/stashgg/stash-native/releases) and add it to your project (e.g. `libs/`).
2. In your app's `build.gradle`:

```groovy
dependencies {
    implementation files('libs/StashNative-<tag>.aar')
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'androidx.browser:browser:1.7.0'
}
```

To build the AAR locally: `cd Android && ./gradlew :stashnative:assembleRelease` (output in `stashnative/build/outputs/aar/`).

### iOS

**XCFramework (recommended):** Download `StashNative.xcframework.zip` from [GitHub Releases](https://github.com/stashgg/stash-native/releases), unzip it, add `StashNative.xcframework` to your Xcode project, and under **Frameworks, Libraries, and Embedded Content** set it to **Embed & Sign**.

**Swift Package Manager:** In Xcode choose File → Add Packages... and add `https://github.com/stashgg/stash-native.git`, then select the StashNative package for your target.

**Manual integration:** Copy all files from `StashNative/Sources/StashNative/` into your project, add them to your target, and link **SafariServices.framework** and **WebKit.framework**.

---

# Presentation Modes

The library provides three distinct ways to present Stash URLs within your app or game: **openCard**, **openModal**, and **openBrowser**. Each method lets you present different types of Stash experiences—such as Stash Pay checkout, Stash Web Shop, or Stash Opt-in—in a style that best fits your user flow. Details for each option are provided below.

## openCard

Drawer-style card: slides up from the bottom on phones, centered on tablets. Suited for Stash Pay payment links or channel selection. [Integrating Stash Pay](https://docs.stash.gg/guides/stash-pay/integration)

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

### Config

Pass a `CardConfig` (or `nil`/`null`) to control orientation and sizing. Pass `nil`/`null` for defaults.

| Aspect | Description |
| ------ | ----------- |
| **forcePortrait** | `true`: card opens portrait-locked (separate activity on Android, portrait-only on iOS). `false` (default): card appears in current orientation as an overlay. |
| **Phone** | `cardHeightRatioPortrait`, `cardWidthRatioLandscape`, `cardHeightRatioLandscape` (0.1–1.0). |
| **Tablet** | `tabletWidthRatioPortrait`, `tabletHeightRatioPortrait`, `tabletWidthRatioLandscape`, `tabletHeightRatioLandscape` (0.1–1.0). |

> **Warning:** If using `forcePortrait`, ensure your app supports portrait or can unlock to portrait while the card is shown.

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

### Callbacks

| Event            | Description |
| ---------------- | ----------- |
| Payment Success  | Called when the payment completes successfully. |
| Payment Failure  | Called when the payment fails. |
| Dialog Dismissed | Called when the user dismisses the dialog. |
| Opt-In Response  | Called when a channel selection response is received. |
| Page Loaded      | Called when the page finishes loading (with load time). |
| Network Error    | Called when the page load fails (no connection, HTTP error, timeout). |

Set a listener (Android) or delegate (iOS) before calling `openCard` or `openModal`. Same callback interface is used for both.

**Android** — implement `StashNativeCardListener` (or extend `StashNativeCardListenerAdapter` to override only the callbacks you need):

```java
StashNativeCard.getInstance().setActivity(this);
StashNativeCard.getInstance().setListener(new StashNativeCard.StashNativeCardListener() {
    @Override
    public void onPaymentSuccess() {
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
        // Channel selection response (e.g. "email", "sms")
    }

    @Override
    public void onPageLoaded(long loadTimeMs) {
        // Page finished loading
    }

    @Override
    public void onNetworkError() {
        // Load failed (no connection, HTTP error, or timeout)
    }
});
```

**iOS (Swift)** — set the delegate and implement `StashNativeCardDelegate` (all methods are optional):

```swift
StashNativeCard.sharedInstance().delegate = self
// In your class (e.g. ViewController):
extension YourViewController: StashNativeCardDelegate {
    func stashNativeCardDidCompletePayment() {
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
}
```

**iOS (Objective-C)** — set the delegate and implement the optional protocol methods:

```objc
[StashNativeCard sharedInstance].delegate = self;

// In your class:
- (void)stashNativeCardDidCompletePayment {
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
```

---

## openModal

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

### Config

Pass a `ModalConfig` (or `nil`/`null`) to control drag bar, dismiss behavior, and sizing. Pass `nil`/`null` for defaults.

| Aspect | Description |
| ------ | ----------- |
| **Behavior** | `showDragBar` (default `true`), `allowDismiss` (default `true`). |
| **Phone** | `phoneWidthRatioPortrait`, `phoneHeightRatioPortrait`, `phoneWidthRatioLandscape`, `phoneHeightRatioLandscape` (0.1–1.0). |
| **Tablet** | `tabletWidthRatioPortrait`, `tabletHeightRatioPortrait`, `tabletWidthRatioLandscape`, `tabletHeightRatioLandscape` (0.1–1.0). |

**Android**

```java
StashNativeCard.ModalConfig config = new StashNativeCard.ModalConfig();
config.showDragBar = true;
config.allowDismiss = true;
// ... phoneWidthRatioPortrait, phoneHeightRatioPortrait, tablet ratios, etc. (see table above)
stashNative.openModal(url, config);
```

**iOS (Swift)**

```swift
let config = StashNativeModalConfig()
config.showDragBar = true
config.allowDismiss = true
// ... phoneWidthRatioPortrait, phoneHeightRatioPortrait, tablet ratios, etc. (see table above)
stashNative.openModal(withURL: url, config: config)
```

### Callbacks

Same as **openCard**: same events and the same listener/delegate. Set it once as shown in the [Callbacks](#callbacks) section under openCard; it receives events for both card and modal.

---

## openBrowser

Opens the URL in the platform browser (Chrome Custom Tabs on Android, SFSafariViewController on iOS). No in-app UI, no config, no callbacks. Use when you only need a simple browser view.

**Android**

```java
StashNativeCard.getInstance().openBrowser("https://testcard.stashpreview.com");
```

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

# Versioning

This package follows [Semantic Versioning](https://semver.org/) (major.minor.patch):

- **Major**: Breaking changes
- **Minor**: New features (backward compatible)
- **Patch**: Bug fixes

# Support

- Documentation: https://docs.stash.gg
- Email: developers@stash.gg
