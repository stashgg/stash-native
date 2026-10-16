# Stash Native [![Lint](https://github.com/stashgg/stash-native/actions/workflows/lint.yml/badge.svg)](https://github.com/stashgg/stash-native/actions/workflows/lint.yml) [![Build & Deploy](https://github.com/stashgg/stash-native/actions/workflows/main.yml/badge.svg)](https://github.com/stashgg/stash-native/actions/workflows/main.yml)


<p align="left">
  <img src=".github/assets/stash_native_rounded.png" width="128" height="128" alt="Stash Native blueprint logo"/>
</p>

The stash-native package adds Stash Pay in-app purchases (IAPs) and Stash webshop authentication to native games or apps. It presents checkout in a responsive native card or platform browser and sends payment and lifecycle callbacks to your application. Code Link feature scans webshop QR codes inside your app for seamless account linking. For integrating Stash into web pages or web applications, please use [stash-web](https://github.com/stashgg/stash-web) instead.

### Game Engine Wrappers

Unity and Unreal bindings for this library live in separate repositories. Use them for seamless engine integrations.

|                                                                                         | Engine        | Repository                                          |
| --------------------------------------------------------------------------------------- | ------------- | --------------------------------------------------- |
| <img src=".github/assets/stash_unity_rounded.png" alt="Unity Icon" width="64" height="64">          | Unity         | [stash-unity](https://github.com/stashgg/stash-unity)   |
| <img src=".github/assets/stash_unreal_rounded.png" alt="Unreal Engine Icon" width="64" height="64"> | Unreal Engine | [stash-unreal](https://github.com/stashgg/stash-unreal) |

### Downloads

Pre-built binaries are available on the [Releases Page](https://github.com/stashgg/stash-native/releases):

- **Android**: `stashnative-release.aar` (or `StashNative-<tag>.aar` from releases)
- **iOS**: `StashNative.xcframework.zip`

### Sample apps

Run `./gradlew :sample:installDebug` from [`Android/`](Android/) or open the [iOS sample project](iOS/Sample/StashNativeSample/StashNativeSample.xcodeproj) in Xcode. 

For quick testing of the Stash's in-app checkout card use [callback test page](https://test.stashpreview.com/) that can trigger different events and simulate various scenarios.

## Installation

### Android

Minimum Android: **API 21**. The SDK builds with **JDK 17** and **compile SDK 34**.

1. Download `StashNative-<tag>.aar` from [GitHub Releases](https://github.com/stashgg/stash-native/releases) and add it to your project, for example under `libs/`.
2. Add the AAR and its base runtime dependencies to your app's `build.gradle`:

```groovy
dependencies {
    implementation files('libs/StashNative-<tag>.aar')
    implementation 'androidx.core:core:1.12.0'
    implementation 'androidx.webkit:webkit:1.11.0'
    implementation 'androidx.window:window:1.4.0'
    implementation 'androidx.window:window-java:1.4.0'
}
```

Optional dependencies:

```groovy
dependencies {
    // openBrowser and external payments in Chrome Custom Tabs:
    implementation 'androidx.browser:browser:1.7.0'

    // Only for CodeLink QR scanning (include all four):
    implementation 'androidx.camera:camera-camera2:1.4.2'
    implementation 'androidx.camera:camera-lifecycle:1.4.2'
    implementation 'androidx.camera:camera-view:1.4.2'
    implementation 'com.google.zxing:core:3.5.3'
}
```

AAR integrations must declare the base dependencies and any optional groups they use. Source-module integrations inherit the base dependencies. See the [installation guide](docs/usage/installation.md#android) for details.

### iOS

Minimum iOS: **15.0**. Use **27.1** for iPhone Duo APIs and compatibility. The host app must also link against SDK 27.1 to adopt the new iPhone Duo display behavior.

**XCFramework:** Download `StashNative.xcframework.zip` from [GitHub Releases](https://github.com/stashgg/stash-native/releases), unzip it, add `StashNative.xcframework` to your Xcode project, and under **Frameworks, Libraries, and Embedded Content** set it to **Embed & Sign**.

**Swift Package Manager:** In Xcode choose File → Add Packages... and add `https://github.com/stashgg/stash-native.git`, then select the StashNative package for your target.


## Features

- **OpenCard:** Open Stash Pay checkout links in an embedded card, with purchase lifecycle callbacks delivered directly to your app.
- **OpenBrowser:** Open Stash Pay checkout and Stash Webshop links in an in-app browser using Chrome Custom Tabs on Android or Safari View Controller on iOS.
- **CodeLinking:** Scan QR codes in your app for quick account linking to Stash Webshops.

## Stash Pay Checkout Card

Pass the activity or view controller belonging to the initiating app window. Set callbacks before opening. Pass a generated Stash Pay link to **openCard** to display a responsive card that adapts to phones, tablets, foldables, and multitasking states.

![Stash Pay checkout card in dark mode on iPhone, unfolded iPhone Duo, and iPad](.github/assets/opencard-devices-dark.png)

**Android**

```java
StashNativeCard.getInstance().openCard(this, "https://test.stashpreview.com", null);
```

**iOS (Swift)**

```swift
StashNativeCard.sharedInstance().openCard(
    withURL: "https://test.stashpreview.com", from: self, config: nil)
```

**iOS (Objective-C)**

```objc
[[StashNativeCard sharedInstance] openCardWithURL:@"https://test.stashpreview.com"
                            fromViewController:self
                                        config:nil];
```

#### Card Configuration

Pass `StashNativeCard.CardConfig` on Android or `StashNativeCardConfig` on iOS. `null` / `nil` uses responsive defaults. Dimensions are **dp on Android** and **points on iOS**, and available window space always limits the requested size. We recommend the default responsive sizing for Stash Pay. Only adjust it when explicitly needed.

| Property | Default | Description |
| --- | --- | --- |
| `preferredContentWidth` | `400` | Preferred content width, constrained by the available window and platform sheet. |
| `preferredContentHeight` | `560` | Resting height ceiling and fallback. Shorter intrinsic content can shrink the card. |
| `maximumContentHeight` | `720` | Expanded content-height cap. `0` uses all available height. |
| `edgeMargin` | `16` | Preferred margin where the presentation has space for it. |
| `orientationPreference` | Follow host | Request portrait for phone checkout; see below. |
| `allowDismiss` | `true` | Allows user dismissal by swipe, backdrop tap, or Android Back. Set to `false` to block these actions; page close and callbacks remain available. |
| `autoClose` | `true` | Closes after payment success or failure. When `false`, callbacks still fire and the card stays open. |

#### Forcing Portrait Orientation

For landscape games, set `orientationPreference` to request a portrait checkout card. The SDK makes a best-effort attempt, but portrait presentation may not work in every app or device state. The SDK handles portrait presentation and restores the host orientation afterward, while tablets and restricted windows follow the available geometry.

```java
config.orientationPreference = StashNativeCard.CardConfig.ORIENTATION_PORTRAIT;
```

```swift
config.orientationPreference = .portrait
```

#### Landscape Backdrop (Android only)

In some cases, forced potrait checkout on Android can cause unexpected behaviour of the app (Such as visual incosistences of the app during the card presentation). To mask these rotation artifacts, you can optionally supply a screenshot or different backdrop before opening a portrait card:

```java
StashNativeCard.setBackdropBitmap(screenshot);
// Or: StashNativeCard.setBackdropBytes(pngOrJpeg);
config.orientationPreference = StashNativeCard.CardConfig.ORIENTATION_PORTRAIT;
StashNativeCard.getInstance().openCard(this, checkoutUrl, config);
```

#### WebView debugging

Enable WebView inspection before opening a card during development to debug checkout with `chrome://inspect` on Android or Safari Web Inspector on iOS 16.4+.

```java
// Android and iOS (Swift)
StashNativeCard.setInspectableWebViewsEnabled(true);
```

#### Callbacks

Card provides various callbacks to report the purchase process state or other events. Set a listener on Android or a delegate on iOS before opening a presentation. The same interface serves card, browser, and CodeLink events.

| Event | Description |
| --- | --- |
| Payment Success | Reports the order string or serialized JSON supplied by the page, or `null` / `nil` when omitted. |
| Payment Failure | Reports the page's payment-failure signal. |
| Dialog Dismissed | Reports user dismissal, page `window.close()` outside purchase processing, or native `dismiss()`. |
| External Payment | Reports the external-payment URL after closing embedded checkout without a normal dismissal callback. |
| Browser Closed | Reports closure of the browser opened by `openBrowser` or an external-payment handoff. |
| Page Loaded | Reports page-load duration in milliseconds. |
| Network Error | Reports a checkout load failure; see platform documentation for failure and teardown details. |

**Android** - extend `StashNativeCardListenerAdapter` to override the callbacks you need, or implement `StashNativeCardListener`:

```java
StashNativeCard.getInstance().setListener(new StashNativeCard.StashNativeCardListenerAdapter() {
    @Override
    public void onPaymentSuccess(String order) {
        // Verify the purchase through your backend before fulfilling items.
    }

    @Override
    public void onPaymentFailure() {
        // Update the game's payment UI.
    }

    @Override
    public void onDialogDismissed() {
        // Resume the game UI.
    }
});
```

**iOS (Swift)** — set the delegate and implement the optional protocol methods:

```swift
StashNativeCard.sharedInstance().delegate = self

extension YourViewController: StashNativeCardDelegate {
    func stashNativeCardDidCompletePayment(withOrder order: String?) {
        // Verify the purchase through your backend before fulfilling items.
    }

    func stashNativeCardDidFailPayment() {
        // Update the game's payment UI.
    }

    func stashNativeCardDidDismiss() {
        // Resume the game UI.
    }
}
```

**iOS (Objective-C)**

```objc
[StashNativeCard sharedInstance].delegate = self;

// Implement these optional StashNativeCardDelegate methods on your controller:
- (void)stashNativeCardDidCompletePaymentWithOrder:(NSString *)order {
    // Verify the purchase through your backend before fulfilling items.
}

- (void)stashNativeCardDidFailPayment {
    // Update the game's payment UI.
}

- (void)stashNativeCardDidDismiss {
    // Resume the game UI.
}
```

## Using in-game browser (Stash Pay & Webshop)

As an alternative, you can use the **OpenBrowser** feature to open your Stash Pay and pre-authenticated webshop links in an in-game browser, using Chrome Custom Tabs on Android and Safari View Controller on iOS. Browser checkouts can't report direct purchase lifecycle callbacks so deeplinks are used instead.

![Stash Pay checkout in dark mode in Safari View Controller on iPhone and Chrome Custom Tabs on Android](.github/assets/openbrowser-devices-dark.png)

**Android**

```java
StashNativeCard.getInstance().openBrowser(this, "https://test.stashpreview.com");
```

**iOS (Swift)**

```swift
StashNativeCard.sharedInstance().openBrowser(withURL: "https://test.stashpreview.com", from: self)
// Optional when returning through a deep link:
StashNativeCard.sharedInstance().closeBrowser()
```

**iOS (Objective-C)**

```objc
[[StashNativeCard sharedInstance] openBrowserWithURL:@"https://test.stashpreview.com"
                               fromViewController:self];
[[StashNativeCard sharedInstance] closeBrowser];
```

Browser closure calls `onBrowserClosed` (Android) or `stashNativeCardDidCloseBrowser` (iOS). `closeBrowser()` dismisses Safari on iOS and has no effect on Android.

#### Prefer Potrait for Browser (iOS Only)

```swift
let config = StashNativeBrowserConfig()
config.orientationPreference = .portrait
StashNativeCard.sharedInstance().openBrowser(withURL: checkoutURL, from: self, config: config)
```

Safari keeps its native sheet presentation and restores the host orientation when it closes. The default follows the host; iPad ignores the preference. Android Custom Tabs control their own orientation.

#### Keep-alive service (Android Only)

Optional short foreground service shows a low-priority notification while the browser is open. This prevents Android on low-memory devices from killing your game process. It is **off by default** but highly recommended.

```java
StashNativeCard.getInstance().setKeepAliveEnabled(true);
StashNativeCard.KeepAliveConfig config = new StashNativeCard.KeepAliveConfig();
config.notificationTitle = "Payment in progress";
config.notificationText = "Tap to return to the app";
config.notificationIconResId = R.drawable.ic_notification; // Use 0 for the library default.
StashNativeCard.getInstance().setKeepAliveConfig(config);
```

The library manifest includes the service and foreground-service permissions. Integrators enabling it must configure their app's service declarations and notification behavior appropriately. See [keep-alive service](docs/usage/browser.md#android-keep-alive-service) and [compatibility](docs/compatibility.md).

## CodeLink (iOS and Android)

Scan webshop QR codes in a responsive native card and use the returned content to link the account.

![CodeLink scanners on iPhone and Android with simulated camera previews](.github/assets/codelink-devices-dark.png)

Add `NSCameraUsageDescription` to your app's `Info.plist` on iOS and the [QR scanning dependencies](#android) on Android; camera permission is requested when the scanner opens.

**Android**

```java
StashNativeCard.getInstance().codeLink(this, null);
```

**iOS (Swift)**

```swift
StashNativeCard.sharedInstance().codeLink(from: self, config: nil)
```

**iOS (Objective-C)**

```objc
[[StashNativeCard sharedInstance] codeLinkFromViewController:self config:nil];
```

#### Scanner Configuration

Pass `StashNativeCard.CodeLinkConfig` on Android or `StashNativeCodeLinkConfig` on iOS to customize or translate the scanner text; omitted or empty text uses the defaults.

| Property | Default |
| --- | --- |
| `headerText` | Scan QR code |
| `calloutTitle` | Scan the webshop code |
| `calloutSubtitle` | Keep the QR code centered inside the frame. |
| `cameraUnavailableText` | Camera unavailable |
| `connectedText` | Connected |
| `showCallout` | `true` |

Set `showCallout` to `false` to hide the info callout.

#### Callbacks

Set the listener or delegate before opening; a successful scan shows **Connected**, closes the card, and returns the unchanged QR content once.

| Event | Android | iOS (Swift) |
| --- | --- | --- |
| QR scanned | `onQrCodeScanned(content)` | `stashNativeCardDidScanQRCode(_:)` |
| Camera or setup error | `onCodeLinkError(error)` | `stashNativeCardCodeLinkDidEncounterError(_:)` |
| Dismissed without a scan | `onDialogDismissed()` | `stashNativeCardDidDismiss()` |

---

Requirements, OS-specific behavior, and platform API notes for app review are in [Compatibility](docs/compatibility.md). The [technical documentation](docs/index.md) covers architecture, the API reference, the JavaScript bridge, and engine wrappers.

---

## Versioning

See the [changelog](CHANGELOG.md) for release history.

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

---

## Support

- Documentation: [docs.stash.gg](https://docs.stash.gg)
- JavaScript bridge: [stash_sdk API](docs/stash-sdk-js.md)
- Email: [developers@stash.gg](mailto:developers@stash.gg)
