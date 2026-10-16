# Stash Native [![Lint](https://github.com/stashgg/stash-native/actions/workflows/lint.yml/badge.svg)](https://github.com/stashgg/stash-native/actions/workflows/lint.yml) [![Build & Deploy](https://github.com/stashgg/stash-native/actions/workflows/main.yml/badge.svg)](https://github.com/stashgg/stash-native/actions/workflows/main.yml)


<p align="left">
  <img src=".github/assets/stash_native_rounded.png" width="128" height="128" alt="Stash Native blueprint logo"/>
</p>

The stash-native package adds Stash Pay in-app purchases (IAPs) and Stash webshop authentication to native games and apps. It presents checkout in a responsive native card or the platform browser and sends payment and lifecycle callbacks to your app. The CodeLink feature scans webshop QR codes inside your app to link accounts. To integrate Stash into web pages or web applications, use [stash-web](https://github.com/stashgg/stash-web) instead.

### Game Engine Wrappers

Unity and Unreal bindings for this library live in separate repositories. Use them to integrate Stash into those engines.

|                                                                                         | Engine        | Repository                                          |
| --------------------------------------------------------------------------------------- | ------------- | --------------------------------------------------- |
| <img src=".github/assets/stash_unity_rounded.png" alt="Unity Icon" width="64" height="64">          | Unity         | [stash-unity](https://github.com/stashgg/stash-unity)   |
| <img src=".github/assets/stash_unreal_rounded.png" alt="Unreal Engine Icon" width="64" height="64"> | Unreal Engine | [stash-unreal](https://github.com/stashgg/stash-unreal) |

### Downloads

Prebuilt binaries are available on the [Releases page](https://github.com/stashgg/stash-native/releases):

- **Android**: `StashNative-<tag>.aar`
- **iOS**: `StashNative-<tag>.xcframework.zip`

### Sample Apps

Run `./gradlew :sample:installDebug` from [`Android/`](Android/), or open the [iOS sample project](iOS/Sample/StashNativeSample/StashNativeSample.xcodeproj) in Xcode.

To test the in-app checkout card quickly, use the [callback test page](https://test.stashpreview.com/). It can trigger each checkout callback.

## Installation

### Android

Minimum Android: API 21. The SDK builds with JDK 17 and compile SDK 34.

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

AAR integrations must declare the base dependencies and any optional groups they use. Source-module integrations inherit the base dependencies. See the [installation guide](https://stashgg.github.io/stash-native/usage/installation.html#android) for details.

### iOS

Minimum iOS: 15.0. Build with Xcode 27.1 for iPhone Duo APIs and compatibility. The host app must also link against the iOS 27.1 SDK to adopt the new iPhone Duo display behavior.

**XCFramework:** Download `StashNative-<tag>.xcframework.zip` from [GitHub Releases](https://github.com/stashgg/stash-native/releases), unzip it, and add `StashNative.xcframework` to your Xcode project. Under **Frameworks, Libraries, and Embedded Content**, set it to **Embed & Sign**.

**Swift Package Manager:** In Xcode, choose **File > Add Package Dependencies**, enter `https://github.com/stashgg/stash-native.git`, and add the **StashNative** library to your target.


## Features

- **OpenCard:** Open Stash Pay checkout links in an embedded card, with purchase lifecycle callbacks delivered directly to your app.
- **OpenBrowser:** Open Stash Pay checkout and Stash Webshop links in an in-app browser: Chrome Custom Tabs on Android or Safari View Controller on iOS.
- **CodeLink:** Scan QR codes in your app for quick account linking to Stash Webshops.

## Stash Pay Checkout Card

Pass a generated Stash Pay link to `openCard` to display a responsive card that adapts to phones, tablets, foldables, and multitasking. Pass the activity or view controller that belongs to the initiating app window, and set callbacks before opening.

![Stash Pay checkout card in dark mode on iPhone, unfolded iPhone Duo, and iPad](.github/assets/opencard-devices-dark.png)

**Android**

```java
StashNativeCard.getInstance().openCard(this, "https://test.stashpreview.com", null);
```

**iOS**

```swift
StashNativeCard.sharedInstance().openCard(
    withURL: "https://test.stashpreview.com", from: self, config: nil)
```

#### Card Configuration

Pass `StashNativeCard.CardConfig` on Android or `StashNativeCardConfig` on iOS; `null` or `nil` uses the responsive defaults. Dimensions are dp on Android and points on iOS, and the available window space always limits the requested size. We recommend the default sizing for Stash Pay; adjust it only when needed.

| Property | Default | Description |
| --- | --- | --- |
| `preferredContentWidth` | `400` | Preferred content width, limited by the available window and the platform sheet. |
| `preferredContentHeight` | `560` | Resting height ceiling and fallback. Shorter content can shrink the card. |
| `maximumContentHeight` | `720` | Expanded content height cap. `0` uses all available height. |
| `edgeMargin` | `16` | Preferred margin when the presentation has room for it. |
| `orientationPreference` | Follow host | Requests portrait checkout on phones; see below. |
| `allowDismiss` | `true` | Allows user dismissal by swipe, backdrop tap, or Android Back. Set it to `false` to block these actions; page close and callbacks still work. |
| `autoClose` | `true` | Closes the card after payment success or failure. When `false`, callbacks still fire and the card stays open. |

#### Forcing Portrait Orientation

For landscape games, set `orientationPreference` to request a portrait checkout card. The SDK presents the card in portrait and restores the host orientation afterward. Portrait is best effort: it may not work in every app or device state, and tablets and restricted windows follow the available geometry.

```java
config.orientationPreference = StashNativeCard.CardConfig.ORIENTATION_PORTRAIT;
```

```swift
config.orientationPreference = .portrait
```

#### Landscape Backdrop (Android Only)

On Android, a forced portrait card can cause visual inconsistencies in the app behind it while the screen rotates. To mask these rotation artifacts, pass a screenshot or another backdrop to `StashNativeCard.setBackdropBitmap(bitmap)` or `setBackdropBytes(pngOrJpeg)` right before opening a portrait card. See [Android portrait backdrop](https://stashgg.github.io/stash-native/usage/checkout-card.html#android-portrait-backdrop).

#### WebView Debugging

During development, enable WebView inspection before opening a card to debug checkout with `chrome://inspect` on Android or Safari Web Inspector on iOS 16.4+.

```java
// Android and iOS
StashNativeCard.setInspectableWebViewsEnabled(true);
```

#### Callbacks

The card reports purchase state and other events through callbacks. Set a listener on Android or a delegate on iOS before opening a presentation. The same interface receives card, browser, and CodeLink events.

| Event | Description |
| --- | --- |
| Payment Success | Reports the order string or serialized JSON supplied by the page, or `null` / `nil` when omitted. |
| Payment Failure | Reports the page's payment failure signal. |
| Dialog Dismissed | Reports user dismissal, page `window.close()` outside purchase processing, or native `dismiss()`. |
| External Payment | Reports the external payment URL, then closes the embedded checkout without a dismissal callback. |
| Browser Closed | Reports that the browser opened by `openBrowser` or an external payment handoff has closed. |
| Page Loaded | Reports the page load duration in milliseconds. |
| Network Error | Reports a checkout load failure. See the [callbacks reference](https://stashgg.github.io/stash-native/usage/callbacks.html) for failure and teardown details. |

**Android:** extend `StashNativeCardListenerAdapter` to override only the callbacks you need, or implement `StashNativeCardListener`:

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

**iOS:** set the delegate and implement the optional protocol methods:

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

## Using the In-Game Browser (Stash Pay & Webshop)

Alternatively, use `openBrowser` to open Stash Pay and pre-authenticated webshop links in an in-game browser: Chrome Custom Tabs on Android and Safari View Controller on iOS. Browser checkouts can't report purchase lifecycle callbacks directly, so they use deep links instead.

![Stash Pay checkout in dark mode in Safari View Controller on iPhone and Chrome Custom Tabs on Android](.github/assets/openbrowser-devices-dark.png)

**Android**

```java
StashNativeCard.getInstance().openBrowser(this, "https://test.stashpreview.com");
```

**iOS**

```swift
StashNativeCard.sharedInstance().openBrowser(withURL: "https://test.stashpreview.com", from: self)
// Optional when returning through a deep link:
StashNativeCard.sharedInstance().closeBrowser()
```

When the browser closes, the SDK calls `onBrowserClosed` (Android) or `stashNativeCardDidCloseBrowser` (iOS). `closeBrowser()` dismisses Safari on iOS and has no effect on Android.

#### Portrait Browser (iOS Only)

```swift
let config = StashNativeBrowserConfig()
config.orientationPreference = .portrait
StashNativeCard.sharedInstance().openBrowser(withURL: checkoutURL, from: self, config: config)
```

Safari keeps its native sheet presentation and restores the host orientation when it closes. The default follows the host, and iPad ignores the preference. Android Custom Tabs control their own orientation.

#### Keep-Alive Service (Android Only)

An optional short foreground service shows a low-priority notification while the browser is open. It makes it less likely that Android kills your game process on low-memory devices. It is off by default; we recommend enabling it.

```java
StashNativeCard.getInstance().setKeepAliveEnabled(true);
StashNativeCard.KeepAliveConfig config = new StashNativeCard.KeepAliveConfig();
config.notificationTitle = "Payment in progress";
config.notificationText = "Tap to return to the app";
config.notificationIconResId = R.drawable.ic_notification; // Use 0 for the library default.
StashNativeCard.getInstance().setKeepAliveConfig(config);
```

The library manifest includes the service and its foreground-service permissions. If you enable it, configure your app's service declarations and notification behavior. See the [keep-alive service](https://stashgg.github.io/stash-native/usage/browser.html#keep-alive-service-android) docs.

## CodeLink (iOS and Android)

Scan webshop QR codes in a responsive native card and use the returned content to link the account.

![CodeLink scanners on iPhone and Android with simulated camera previews](.github/assets/codelink-devices-dark.png)

On iOS, add `NSCameraUsageDescription` to your app's `Info.plist`. On Android, add the [QR scanning dependencies](#android). The SDK requests camera permission when the scanner opens.

**Android**

```java
StashNativeCard.getInstance().codeLink(this, null);
```

**iOS**

```swift
StashNativeCard.sharedInstance().codeLink(from: self, config: nil)
```

#### Scanner Configuration

To customize or translate the scanner text, pass `StashNativeCard.CodeLinkConfig` on Android or `StashNativeCodeLinkConfig` on iOS. Omitted or empty text uses the defaults. Set `showCallout` to `false` to hide the info callout. See [scanner configuration](https://stashgg.github.io/stash-native/usage/codelink.html#configuration) for all properties and their default text.

#### Callbacks

Set the listener or delegate before opening. A successful scan shows **Connected**, closes the card, and returns the unchanged QR content once.

| Event | Android | iOS |
| --- | --- | --- |
| QR scanned | `onQrCodeScanned(content)` | `stashNativeCardDidScanQRCode(_:)` |
| Camera or setup error | `onCodeLinkError(error)` | `stashNativeCardCodeLinkDidEncounterError(_:)` |
| Dismissed without a scan | `onDialogDismissed()` | `stashNativeCardDidDismiss()` |

---

## Full Reference

For more detailed information, see the [Stash Native documentation](https://stashgg.github.io/stash-native/):

- [Usage](https://stashgg.github.io/stash-native/usage/): installation, API, configuration, and callbacks
- [JavaScript bridge](https://stashgg.github.io/stash-native/stash-sdk-js.html): the `window.stash_sdk` API for checkout pages
- [Engine wrappers](https://stashgg.github.io/stash-native/usage/engine-wrappers.html): Unity, Unreal, and custom engine bindings
- [Platform Architecture](https://stashgg.github.io/stash-native/architecture/): iOS and Android internals, lifecycle, and sizing
- [Compatibility](https://stashgg.github.io/stash-native/architecture/compatibility.html): supported versions, version-specific behavior, and runtime techniques for app review

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
// iOS
let version = StashNativeCard.sdkVersion()
```

---

## Support

- Documentation: [docs.stash.gg](https://docs.stash.gg)
- Email: [developers@stash.gg](mailto:developers@stash.gg)
