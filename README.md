# Stash for Android / iOS [![Lint](https://github.com/stashgg/stash-native/actions/workflows/lint.yml/badge.svg)](https://github.com/stashgg/stash-native/actions/workflows/lint.yml) [![Build & Deploy](https://github.com/stashgg/stash-native/actions/workflows/main.yml/badge.svg)](https://github.com/stashgg/stash-native/actions/workflows/main.yml)


<p align="left">
  <img src=".github/assets/stash_native.svg" width="128" height="128" alt="Stash Native blueprint logo"/>
</p>

The stash-native package adds Stash in-app purchases (IAPs) and webshops to your game or app. It presents checkout in a responsive native card or platform browser and sends payment and lifecycle callbacks to your application. CodeLink scans webshop QR codes in the same card. The library is delivered as an AAR for Android and an XCFramework or Swift package for iOS.

Version 3.0 replaces device-specific sizing with responsive window-based sizing and requires an explicit presentation host. Read the [migration guide](docs/migration-3.0.md) before replacing a 2.x binary.

---

## Table of contents

**Overview**

- [Game engine wrappers](#game-engine-wrappers)
- [Downloads](#downloads)
- [Sample apps & Testing](#sample-apps--testing)

**Setup**

- [Installation](#installation)
  - [Android](#android)
  - [iOS](#ios)

**API**

- [Presentation modes](#presentation-modes)
  - [openCard](#opencard)
    - [Config](#config)
    - [Forcing Portrait Orientation](#forcing-portrait-orientation)
    - [Callbacks](#callbacks)
  - [openBrowser](#openbrowser)
    - [Android Keep-alive service (Optional)](#android-keep-alive-service-optional)
  - [CodeLink](#codelink-ios-and-android)
    - [Config](#config-1)
    - [Callbacks](#callbacks-1)
- [Webview inspection (debug / testing)](#webview-inspection-debug--testing)

**Reference**

- [Compatibility, platform API & store review](COMPATIBILITY.md)
- [Migration from 2.x](docs/migration-3.0.md)
- [Responsive sizing](docs/responsive-presentation.md)
- [JavaScript bridge and telemetry](docs/stash-sdk-js.md)
- [Versioning](#versioning)
- [Support](#support)

---

## Game Engine Wrappers

Unity and Unreal bindings live in separate repositories. Their existing releases must migrate to the native 3.0 APIs before consuming this version.

|                                                                                             | Engine        | Repository                                              | Compatibility                                    |
| ------------------------------------------------------------------------------------------- | ------------- | ------------------------------------------------------- | ------------------------------------------------ |
| <img src=".github/assets/stash_unity.png" alt="Unity Icon" width="64" height="64">          | Unity         | [stash-unity](https://github.com/stashgg/stash-unity)   | Native 3.0 migration required                  |
| <img src=".github/assets/stash_unreal.png" alt="Unreal Engine Icon" width="64" height="64"> | Unreal Engine | [stash-unreal](https://github.com/stashgg/stash-unreal) | Native 3.0 migration required  |

For building your own wrappers, see [docs/building-wrappers.md](./docs/building-wrappers.md) and the [3.0 migration guide](docs/migration-3.0.md).

---

## Downloads

Pre-built binaries are available on the [Releases Page](https://github.com/stashgg/stash-native/releases). Choose a release matching the native SDK version your integration targets:

- **Android**: `stashnative-release.aar` (or `StashNative-<tag>.aar` from releases)
- **iOS**: `StashNative.xcframework.zip`

---

## Sample apps & Testing

Both platforms include sample apps under [`Android/sample`](Android/sample/) and [`iOS/Sample`](iOS/Sample/). Open `iOS/Sample/StashNativeSample/StashNativeSample.xcodeproj` in Xcode, or run `./gradlew :sample:installDebug` from the `Android/` directory.

The samples can generate checkout links using a configured test instance. **Link Webshop → Scan QR Code** opens CodeLink and logs its callbacks; **Settings → QR Code scan options** customizes or translates the scanner text and hides the info callout. Live scanning requires a physical camera; the iOS Simulator shows the unavailable state.

Use [the callback test page](https://test.stashpreview.com/) or serve [`.github/test/`](.github/test/) locally. `responsive.html` exercises content-height hints, form persistence, expansion, and processing locks. Use only the test API and test payment data. Sample request signing is demonstration code; production ingress secrets belong on your backend.

If an Apple Silicon emulator boots but its WebView fails GPU initialization, test another GPU backend, such as `-gpu swangle`. Verify the checkout page itself, not just emulator startup. See [compatibility](COMPATIBILITY.md) for testing limits.

See [maintenance and testing](docs/maintenance-and-testing.md) for build and validation commands.

---

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

Add optional libraries for the features your app uses:

| Feature | Additional dependencies | When omitted |
| --- | --- | --- |
| `openCard` | None beyond the base dependencies above | Checkout works without camera or QR libraries. |
| `openBrowser` and external payment links in Custom Tabs | `androidx.browser:browser:1.7.0` | Links open in the system browser. |
| `codeLink` QR scanning | CameraX and ZXing below | Scanning is unavailable; checkout and browser still work. |

```groovy
dependencies {
    // Only for Chrome Custom Tabs:
    implementation 'androidx.browser:browser:1.7.0'

    // Only for CodeLink QR scanning (include all four):
    implementation 'androidx.camera:camera-camera2:1.4.2'
    implementation 'androidx.camera:camera-lifecycle:1.4.2'
    implementation 'androidx.camera:camera-view:1.4.2'
    implementation 'com.google.zxing:core:3.5.3'
}
```

Standalone AAR files carry no transitive dependency metadata, so declare the base dependencies and the optional groups you need. Source-module consumers inherit the base dependencies through Gradle and add optional groups explicitly. AppCompat, Material, and Compose are not SDK runtime requirements. The minimal integration needs no explicit Kotlin BOM or Kotlin plugin. WindowManager 1.4.0 preserves the API 21 minimum; 1.5.x requires API 23. See the [dependency notes](docs/android.md#dependencies) for host-app version conflicts.

To build the AAR locally, run `./gradlew :stashnative:assembleRelease` from `Android/`. The output is in `stashnative/build/outputs/aar/`.

### iOS

Minimum iOS: **15.0**. Use **Xcode 27.1** for Duo APIs and full validation. The host app must also link against SDK 27.1 to adopt the new Duo display behavior.

**XCFramework:** Download `StashNative.xcframework.zip` from [GitHub Releases](https://github.com/stashgg/stash-native/releases), unzip it, add `StashNative.xcframework` to your Xcode project, and under **Frameworks, Libraries, and Embedded Content** set it to **Embed & Sign**.

**Swift Package Manager:** In Xcode choose File → Add Packages... and add `https://github.com/stashgg/stash-native.git`, then select the StashNative package for your target.

---

## Presentation modes

The library exposes **openCard** for embedded checkout and webshop URLs, **openBrowser** for Chrome Custom Tabs / Safari View Controller, and **CodeLink** for QR scanning. Version 3.0 removes `openModal`, popup APIs, and configurable background colors. Use `openCard` for embedded content; its defaults adapt to the current window.

Pass the activity or view controller belonging to the initiating app window. Set callbacks before opening. The SDK accepts one active presentation; rotating, folding, or resizing it preserves the live WebView and form state.

---

## openCard

A responsive card for Stash Pay checkout or pre-authenticated webshop links. It opens as a bottom sheet on phones and a compact centered card where the window has room, including tablets. Resting and expanded states adapt to the available space and keyboard.

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

### Config

Pass `StashNativeCard.CardConfig` on Android or `StashNativeCardConfig` on iOS. `null` / `nil` uses responsive defaults. Dimensions are **dp on Android** and **points on iOS**, and available window space always limits the requested size.

| Property | Default | Description |
| --- | --- | --- |
| `preferredContentWidth` | `400` | Preferred content width, constrained by the available window and platform sheet. |
| `preferredContentHeight` | `560` | Resting height ceiling and fallback. Shorter intrinsic content can shrink the card. |
| `maximumContentHeight` | `720` | Expanded content-height cap. `0` uses all available height. |
| `edgeMargin` | `16` | Preferred margin where the presentation has space for it. |
| `orientationPreference` | Follow host | Request portrait for phone checkout; see below. |
| `allowDismiss` | `true` | Allows user dismissal by swipe, backdrop tap, or Android Back. Set to `false` to block these actions; page close and callbacks remain available. |
| `autoClose` | `true` | Closes after payment success or failure. When `false`, callbacks still fire and the card stays open. |

Override dimensions only when your checkout needs a different size:

**Android**

```java
StashNativeCard.CardConfig config = new StashNativeCard.CardConfig();
config.preferredContentWidth = 360f;
config.preferredContentHeight = 520f;
StashNativeCard.getInstance().openCard(this, checkoutUrl, config);
```

**iOS (Swift)**

```swift
let config = StashNativeCardConfig()
config.preferredContentWidth = 360
config.preferredContentHeight = 520
StashNativeCard.sharedInstance().openCard(withURL: checkoutURL, from: self, config: config)
```

Pages can provide an intrinsic height through `[data-stash-content]` or `window.stash_sdk.setContentHeight(heightInCssPixels)`. The card renders without either. `stash_sdk.expand()` and `stash_sdk.collapse()` select the card state. See [responsive presentation](docs/responsive-presentation.md) for content measurement and safe-area requirements. Native backgrounds follow the page and theme automatically.

### Forcing Portrait Orientation

Set `orientationPreference` when the host game is landscape but checkout should prefer portrait:

```java
config.orientationPreference = StashNativeCard.CardConfig.ORIENTATION_PORTRAIT;
```

```swift
config.orientationPreference = .portrait
```

**Android:** Compact fullscreen checkout requests portrait through its own activity in the host app's process. Tablets and multi-window presentations follow the available window geometry.

**iOS:** On iPhone, the SDK presents the same native card and WebView in its own UIKit window and scopes orientation overrides to that window, including in landscape-only games. The game controller keeps its orientation restrictions. The SDK restores the previous orientation before returning focus; an external-payment Safari handoff retains the portrait window until the browser closes. iPad ignores this preference.

The default follows the host orientation. System windowing restrictions can limit rotation, so the card always fits the available space. The SDK owns orientation preparation and restoration; manual orientation hooks and screenshot-backdrop APIs from 2.x are removed. CodeLink always follows the host orientation.

### Callbacks

Set a listener on Android or a delegate on iOS before opening a presentation. The same interface serves card, browser, and CodeLink events.

| Event | Description |
| --- | --- |
| Payment Success | Reports the order string or serialized JSON supplied by the page, or `null` / `nil` when omitted. |
| Payment Failure | Reports the page's payment-failure signal. |
| Dialog Dismissed | Reports user dismissal, page `window.close()` outside purchase processing, or native `dismiss()`. |
| External Payment | Reports the external-payment URL after closing embedded checkout without a normal dismissal callback. |
| Browser Closed | Reports closure of the browser opened by `openBrowser` or an external-payment handoff. |
| Page Loaded | Reports page-load duration in milliseconds. |
| Network Error | Reports a checkout load failure; see platform documentation for failure and teardown details. |

**Android** — extend `StashNativeCardListenerAdapter` to override the callbacks you need, or implement `StashNativeCardListener`:

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

Android tracks browser closure internally. Hosts do not call `setActivity` or forward `onActivityResult`; pass the current activity to each opening call.

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

`allowDismiss` controls user dismissal only. With `allowDismiss = false`, the page can still call `window.close()` (including from its own close button), and payment callbacks still fire and follow `autoClose`. The purchase-processing lock blocks user dismissal and `window.close()` until processing ends. Native `dismiss()` remains available regardless of either setting.

With `autoClose = false`, payment callbacks leave checkout open. `resetPresentationState()` tears down without callbacks. `openExternalBrowser` closes embedded checkout without a dismissal callback, while `openLink` leaves it open and emits no payment callback.

The [JavaScript bridge reference](docs/stash-sdk-js.md) describes page messages, callback ordering, and `stash_sdk.getTelemetry()`, including device/window information and page timing. Callbacks describe UI state; verify purchases through your backend before fulfilling items.

---

## openBrowser

Opens the URL in Chrome Custom Tabs on Android when the optional Browser library is present, otherwise the system browser. iOS presents `SFSafariViewController` from the supplied controller. Use it for browser checkout or as a fallback to `openCard`.

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

Browser closure uses `onBrowserClosed` on Android and `stashNativeCardDidCloseBrowser` on iOS. Android owns Custom Tabs results through an internal proxy activity and uses lifecycle detection for its system-browser fallback. No host result forwarding is required. `closeBrowser()` dismisses Safari on iOS and has no effect on Android.

### Android Keep-alive service (Optional)

Android's optional short foreground service shows a low-priority notification while the payment browser is open. It improves process survival under memory pressure but cannot guarantee it. It is **off by default**.

```java
StashNativeCard.getInstance().setKeepAliveEnabled(true);
StashNativeCard.KeepAliveConfig config = new StashNativeCard.KeepAliveConfig();
config.notificationTitle = "Payment in progress";
config.notificationText = "Tap to return to the app";
config.notificationIconResId = R.drawable.ic_notification; // Use 0 for the library default.
StashNativeCard.getInstance().setKeepAliveConfig(config);
```

The library manifest includes the service and foreground-service permissions. Integrators enabling it must configure their app's service declarations and notification behavior appropriately. See [Android implementation](docs/android.md) and [compatibility](COMPATIBILITY.md).

---

## CodeLink (iOS and Android)

CodeLink hosts a QR camera in the same responsive native card as checkout. It follows the app's orientation on phones and tablets, including landscape-only games, and uses the same compact, centered card on tablets. The preview fills the card, with a centered scan frame and a “Scan the webshop code” callout. Camera startup shows only a spinner.

On iOS, add `NSCameraUsageDescription` to the **host app's** `Info.plist`, for example “Scan a webshop QR code to link it with your game.” Camera access is requested when CodeLink opens. No microphone or photo-library permission is needed; the SDK does not record or upload camera images.

```swift
let stash = StashNativeCard.sharedInstance()
stash.delegate = self
stash.codeLink(from: self)

func stashNativeCardDidScanQRCode(_ content: String) {
    // The card has closed. Interpret the raw QR content in your app.
}

func stashNativeCardCodeLinkDidEncounterError(_ error: Error) {
    // Camera access is denied, unavailable, or incorrectly configured.
}
```

Objective-C entry point: `-codeLinkFromViewController:` (or `-codeLinkFromViewController:config:`).

```java
StashNativeCard stash = StashNativeCard.getInstance();
stash.setListener(new StashNativeCard.StashNativeCardListenerAdapter() {
    @Override public void onQrCodeScanned(String content) {
        // The card has closed. Interpret the raw QR content in your app.
    }

    @Override public void onCodeLinkError(StashNativeCard.CodeLinkError error) {
        // The card remains open with the configured unavailable text.
    }
});
stash.codeLink(this);
```

### Config

Pass `StashNativeCodeLinkConfig` on iOS or `StashNativeCard.CodeLinkConfig` on Android to customize or translate the scanner copy:

```swift
let config = StashNativeCodeLinkConfig()
config.headerText = NSLocalizedString("scanner.header", comment: "QR scanner header")
config.calloutTitle = NSLocalizedString("scanner.title", comment: "QR scanner callout")
config.calloutSubtitle = NSLocalizedString("scanner.subtitle", comment: "QR positioning hint")
config.cameraUnavailableText = NSLocalizedString("scanner.unavailable", comment: "Camera unavailable status")
config.connectedText = NSLocalizedString("scanner.connected", comment: "QR scan confirmation")
config.showCallout = true
stash.codeLink(from: self, config: config)
```

```java
StashNativeCard.CodeLinkConfig config = new StashNativeCard.CodeLinkConfig();
config.headerText = getString(R.string.scanner_header);
config.calloutTitle = getString(R.string.scanner_title);
config.calloutSubtitle = getString(R.string.scanner_subtitle);
config.cameraUnavailableText = getString(R.string.scanner_unavailable);
config.connectedText = getString(R.string.scanner_connected);
config.showCallout = true;
stash.codeLink(this, config);
```

| Field | Default |
| --- | --- |
| `headerText` | Scan QR code |
| `calloutTitle` | Scan the webshop code |
| `calloutSubtitle` | Keep the QR code centered inside the frame. |
| `cameraUnavailableText` | Camera unavailable |
| `connectedText` | Connected |
| `showCallout` | `true` |

Omitting the config, or passing `nil`/`null` or an empty string for a text field, uses the built-in copy. Text is plain text and wraps to fit. `showCallout = false` removes the entire info callout from both the layout and accessibility, allowing a larger scan frame. Options are copied when opening, so later edits apply only to future scans. The unavailable state shows only `cameraUnavailableText`, without an explanatory subtitle. `connectedText` also supplies the accessibility announcement.

Android's library manifest declares `CAMERA` and optional camera hardware. The SDK requests camera permission when CodeLink opens; checkout and browser never request it. Android uses CameraX and ZXing, without Play Services or a model download. Apps using CodeLink must add the optional scanning dependencies listed in [Installation](#android), including when consuming the SDK as a source module. It requires no microphone, storage, or photo permission. The preview and QR decoding stay on the device.

### Callbacks

Only QR codes fully inside the scan frame are accepted. The first nonempty payload stops scanning and shows a brief **Connected** checkmark with success haptic feedback. The card then closes and delivers `stashNativeCardDidScanQRCode:` / `onQrCodeScanned` once on the main thread. The animation respects disabled system animations and allows extra reading time with VoiceOver or TalkBack. The payload is returned unchanged; the confirmation acknowledges the scan and does not perform account linking or open a URL. Success does not emit payment or dismissal callbacks. The close button, native sheet dismissal, and `dismiss()` use the existing dismissal callback; `resetPresentationState()` stays silent, including during the confirmation.

iOS camera errors use `StashNativeCodeLinkErrorDomain` and the public `StashNativeCodeLinkError` codes. Android reports `CodeLinkError.CAMERA_PERMISSION_DENIED`, `CAMERA_UNAVAILABLE`, `CAMERA_CONFIGURATION_FAILED`, or `CAMERA_PERMISSION_NOT_DECLARED`. An error is reported at most once per scanner session. The card remains open with the configured unavailable text and, when permission is denied, an **Open Settings** button. Returning after granting access resumes scanning. Capture stops when the card closes or the app leaves the foreground. Platforms without a usable camera, including the iOS Simulator, show the unavailable state. Physical-device testing is required for live scanning.

If Android's scanning dependencies are missing or cannot load, `codeLink` reports `CAMERA_CONFIGURATION_FAILED` and closes without showing a scanner or requesting camera permission. It does not emit a dismissal callback, and another presentation can be opened from the error callback.

Both mobile samples include **Link Webshop → Scan QR Code** and display results in the existing callback log. **Settings → QR Code scan options** edits the header, callout title/subtitle and visibility, camera-unavailable text, and connected text, with a reset to defaults. CodeLink is a native API; it is not exposed through the JavaScript bridge.

---

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

> **Do not enable this in production.** It exposes the checkout webview contents to remote inspection. Gate it behind a debug/QA build flag; the sample apps enable it only for local testing.

---

Requirements, OS matrices, testing environments, and platform API / store review notes are documented in [COMPATIBILITY.md](COMPATIBILITY.md). Implementation details are in the [architecture overview](docs/architecture-overview.md), [iOS documentation](docs/ios.md), and [Android documentation](docs/android.md).

---

## Versioning

Version **3.0.0** includes breaking native APIs. See the [migration guide](docs/migration-3.0.md) and [version history](CHANGELOG.md).

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
- Email: [developers@stash.gg](mailto:developers@stash.gg)
