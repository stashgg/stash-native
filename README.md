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

## Wrappers

If you're using one of the game engines listed below, we offer dedicated wrappers for this library. These wrappers provide ready-to-use interfaces for integrating Stash features into your project, along with added development tools—such as full flow testing directly in the Unity Editor.

|                                                                                             | Engine        | Repository                                              | Compatibility                   |
| ------------------------------------------------------------------------------------------- | ------------- | ------------------------------------------------------- | ------------------------------- |
| <img src=".github/assets/stash_unity.png" alt="Unity Icon" width="64" height="64">          | Unity         | [stash-unity](https://github.com/stashgg/stash-unity)   | Unity 2019.4+ (LTS recommended) |
| <img src=".github/assets/stash_unreal.png" alt="Unreal Engine Icon" width="64" height="64"> | Unreal Engine 5 | [stash-unreal (main)](https://github.com/stashgg/stash-unreal)                 | Unreal Engine 5.0+                |
| <img src=".github/assets/stash_unreal.png" alt="Unreal Engine Icon" width="64" height="64"> | Unreal Engine 4 | [stash-unreal (4.27-plus)](https://github.com/stashgg/stash-unreal/tree/4.27-plus) | Unreal Engine 4.27-plus           |

## Downloads

Latest pre-built binaries are always available on [Releases Page](https://github.com/stashgg/stash-native/releases):

- **Android**: `stashpay-release.aar`
- **iOS**: `StashPay.xcframework.zip`

## Sample Apps

Both platforms contain up-to-date sample apps that demonstrate the library usage and functions. You can run them from source 

- **Android**: `./Android/sample/` - Run with `./gradlew :sample:installDebug`
- **iOS**: `./iOS/Sample/` - Open `StashPaySample.xcodeproj` in Xcode

or try them instantly in your browser using the Appetize online emulator:

- [Android Sample App](https://appetize.io/app/b_3l3fzg5qiahx6p2xpwp3kcirhy)
- [iOS Sample App](https://appetize.io/app/b_qbywqclhrfl6lk3i3ehovfqa2m)

---

## Installation

### Android

1. Download `stashpay-release.aar` from [GitHub Releases](https://github.com/stashgg/stash-native/releases) and add it to your project (e.g. `libs/`).
2. In your app's `build.gradle`:

```groovy
dependencies {
    implementation files('libs/stashpay-release.aar')
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'androidx.browser:browser:1.7.0'
}
```

To build the AAR locally: `cd Android && ./gradlew :stashpay:assembleRelease` (output in `stashpay/build/outputs/aar/`).

### iOS

**XCFramework (recommended):** Download `StashPay.xcframework.zip` from [GitHub Releases](https://github.com/stashgg/stash-native/releases), unzip it, add `StashPay.xcframework` to your Xcode project, and under **Frameworks, Libraries, and Embedded Content** set it to **Embed & Sign**.

**Swift Package Manager:** In Xcode choose File → Add Packages... and add `https://github.com/stashgg/stash-native.git`, then select the StashPay package for your target.

**Manual integration:** Copy all files from `StashPay/Sources/StashPay/` into your project, add them to your target, and link **SafariServices.framework** and **WebKit.framework**.

---

## Usage

The library provides three distinct ways to present Stash URLs within your app or game: **openCard**, **openModal**, and **openBrowser**. Each method lets you present different types of Stash experiences—such as Stash Pay checkout, Stash Web Shop, or Stash Opt-in—in a style that best fits your user flow. Details for each option are provided below.

### openCard

Drawer-style card: slides up from the bottom on phones, centered on tablets. Suited for Stash Pay payment links or channel selection. [Integrating Stash Pay](https://docs.stash.gg/guides/stash-pay/integration)

#### Usage

**Android**

```java
StashPayCard.CardConfig config = new StashPayCard.CardConfig();  // or null for defaults
StashPayCard.getInstance().openCard("https://your-url.com", config);
```

**iOS (Swift)**

```swift
let config = StashPayCardConfig()  // or nil for defaults
StashPayCard.sharedInstance().openCard(withURL: "https://your-url.com", config: config)
```

**iOS (Objective-C)**

```objc
StashPayCardConfig *config = [[StashPayCardConfig alloc] init];  // or nil for defaults
[[StashPayCard sharedInstance] openCardWithURL:@"https://your-url.com" config:config];
```

#### Config

Pass a `CardConfig` (or `nil`/`null`) to control orientation and sizing. Pass `nil`/`null` for defaults.

| Aspect | Description |
| ------ | ----------- |
| **forcePortrait** | `true`: card opens portrait-locked (separate activity on Android, portrait-only on iOS). `false` (default): card appears in current orientation as an overlay. |
| **Phone** | `cardHeightRatioPortrait`, `cardWidthRatioLandscape`, `cardHeightRatioLandscape` (0.1–1.0). |
| **Tablet** | `tabletWidthRatioPortrait`, `tabletHeightRatioPortrait`, `tabletWidthRatioLandscape`, `tabletHeightRatioLandscape` (0.1–1.0). |

> **Warning:** If using `forcePortrait`, ensure your app supports portrait or can unlock to portrait while the card is shown.

**Android**

```java
StashPayCard.CardConfig config = new StashPayCard.CardConfig();
config.forcePortrait = false;
config.cardHeightRatioPortrait = 0.68f;
// ... tabletWidthRatioPortrait, tabletHeightRatioPortrait, etc. (see table above)
stashPay.openCard(url, config);
```

**iOS (Swift)**

```swift
let config = StashPayCardConfig()
config.forcePortrait = false
config.cardHeightRatioPortrait = 0.68
// ... tabletWidthRatioPortrait, tabletHeightRatioPortrait, etc. (see table above)
stashPay.openCard(withURL: url, config: config)
```

#### Callbacks

| Event            | Description |
| ---------------- | ----------- |
| Payment Success  | Called when the payment completes successfully. |
| Payment Failure  | Called when the payment fails. |
| Dialog Dismissed | Called when the user dismisses the dialog. |
| Opt-In Response  | Called when a channel selection response is received. |
| Page Loaded      | Called when the page finishes loading (with load time). |
| Network Error    | Called when the page load fails (no connection, HTTP error, timeout). |

Set a listener (Android) or delegate (iOS) before calling `openCard`.

---

### openModal

Centered modal on all devices. Same layout on phone and tablet; resizes on rotation. Suited for channel selection or an alternative checkout style. [Stash Pay Opt-In](https://docs.stash.gg/guides/stash-pay/opt-in)

#### Usage

**Android**

```java
StashPayCard.ModalConfig config = new StashPayCard.ModalConfig();  // or null for defaults
StashPayCard.getInstance().openModal("https://your-url.com", config);
```

**iOS (Swift)**

```swift
let config = StashPayModalConfig()  // or nil for defaults
StashPayCard.sharedInstance().openModal(withURL: "https://your-url.com", config: config)
```

**iOS (Objective-C)**

```objc
StashPayModalConfig *config = [[StashPayModalConfig alloc] init];  // or nil for defaults
[[StashPayCard sharedInstance] openModalWithURL:@"https://your-url.com" config:config];
```

#### Config

Pass a `ModalConfig` (or `nil`/`null`) to control drag bar, dismiss behavior, and sizing. Pass `nil`/`null` for defaults.

| Aspect | Description |
| ------ | ----------- |
| **Behavior** | `showDragBar` (default `true`), `allowDismiss` (default `true`). |
| **Phone** | `phoneWidthRatioPortrait`, `phoneHeightRatioPortrait`, `phoneWidthRatioLandscape`, `phoneHeightRatioLandscape` (0.1–1.0). |
| **Tablet** | `tabletWidthRatioPortrait`, `tabletHeightRatioPortrait`, `tabletWidthRatioLandscape`, `tabletHeightRatioLandscape` (0.1–1.0). |

**Android**

```java
StashPayCard.ModalConfig config = new StashPayCard.ModalConfig();
config.showDragBar = true;
config.allowDismiss = true;
// ... phoneWidthRatioPortrait, phoneHeightRatioPortrait, tablet ratios, etc. (see table above)
stashPay.openModal(url, config);
```

**iOS (Swift)**

```swift
let config = StashPayModalConfig()
config.showDragBar = true
config.allowDismiss = true
// ... phoneWidthRatioPortrait, phoneHeightRatioPortrait, tablet ratios, etc. (see table above)
stashPay.openModal(withURL: url, config: config)
```

#### Callbacks

Same as **openCard**: Payment Success, Payment Failure, Dialog Dismissed, Opt-In Response, Page Loaded, Network Error. Set a listener (Android) or delegate (iOS) before calling `openModal`.

---

### openBrowser

Opens the URL in the platform browser (Chrome Custom Tabs on Android, SFSafariViewController on iOS). No in-app UI, no config, no callbacks. Use when you only need a simple browser view.

#### Usage

**Android**

```java
StashPayCard.getInstance().openBrowser("https://your-url.com");
```

**iOS (Swift)**

```swift
StashPayCard.sharedInstance().openBrowser(withURL: "https://your-url.com")
// Optionally dismiss when handling a deeplink:
StashPayCard.sharedInstance().closeBrowser()
```

**iOS (Objective-C)**

```objc
[[StashPayCard sharedInstance] openBrowserWithURL:@"https://your-url.com"];
// Optionally dismiss when handling a deeplink:
[[StashPayCard sharedInstance] closeBrowser];
```

On iOS, **closeBrowser()** dismisses the Safari view. On Android, **closeBrowser()** is a no-op (Chrome Custom Tabs cannot be closed by the app).

---

## Versioning

This package follows [Semantic Versioning](https://semver.org/) (major.minor.patch):

- **Major**: Breaking changes
- **Minor**: New features (backward compatible)
- **Patch**: Bug fixes

## Support

- Documentation: https://docs.stash.gg
- Email: developers@stash.gg
