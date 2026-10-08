# Stash Native for iOS and Android

Stash Native presents Stash Pay checkout and webshop pages in a native card or platform browser. It forwards payment and lifecycle events to the host app through a Java listener or Objective-C delegate.

3.0 uses responsive window-based sizing and explicit presentation hosts. See [migration from 2.x](docs/migration-3.0.md) before replacing an existing native binary. Unity and Unreal wrappers are maintained separately and must migrate before consuming 3.0.

## Installation

### iOS

Minimum iOS: **15.0**. Use Xcode 27.1 for the full Duo layout and validation path.

Add this repository through Swift Package Manager, or download `StashNative.xcframework.zip` from [Releases](https://github.com/stashgg/stash-native/releases) and embed the framework in the app. The host application must also link against SDK 27.1 to adopt the new Duo display behaviour.

### Android

Minimum Android: **API 21**. The SDK builds with JDK 17 and compile SDK 34.

A standalone AAR has no dependency metadata. Add these libraries alongside the downloaded AAR:

```groovy
dependencies {
    implementation files('libs/StashNative-3.0.0.aar')
    implementation 'androidx.core:core:1.12.0'
    implementation 'androidx.webkit:webkit:1.11.0'
    implementation 'androidx.window:window:1.4.0'
    implementation 'androidx.window:window-java:1.4.0'
    // Optional Chrome Custom Tabs support:
    implementation 'androidx.browser:browser:1.7.0'
}
```

Source-module consumers receive required dependencies transitively. AppCompat, Material, and Compose are not SDK runtime requirements. WindowManager 1.4.0 is intentional: newer 1.5.x versions require API 23.

## Presentation modes

Pass the current activity or the view controller belonging to the initiating window. Set callbacks before opening checkout. The SDK accepts one active presentation; resizing that presentation keeps its WebView and payment state alive.

### openCard

Cards use an adaptive sheet: attached at the bottom in compact space, floating where the platform has room. They support resting and expanded states. Defaults work without device-specific configuration.

```swift
let stash = StashNativeCard.sharedInstance()
stash.delegate = self
stash.openCard(withURL: checkoutURL, from: self, config: nil)
```

```java
StashNativeCard stash = StashNativeCard.getInstance();
stash.openCard(activity, checkoutUrl, null);
```

```objc
[[StashNativeCard sharedInstance] openCardWithURL:checkoutURL
                            fromViewController:self
                                        config:nil];
```

Passing `nil`/`null` uses automatic responsive defaults. Optional dimensions can be overridden through the card config. All sizing values are points on iOS and dp on Android:

| Property | iOS card | Android card |
|---|---:|---:|
| `preferredContentWidth` | 400 | 400 |
| `preferredContentHeight` | 560 | 560 |
| `maximumContentHeight` | 720 | 720 |
| `edgeMargin` | 16 | 16 |

A zero maximum uses all available height. `allowDismiss` and `autoClose` default to `true`. Native backgrounds follow the page and theme automatically; there is no background-color setting.

Override dimensions only when checkout needs a different size:

```swift
let config = StashNativeCardConfig()
config.preferredContentWidth = 360
config.preferredContentHeight = 520
stash.openCard(withURL: checkoutURL, from: self, config: config)
```

```java
StashNativeCard.CardConfig config = new StashNativeCard.CardConfig();
config.preferredContentWidth = 360f;
config.preferredContentHeight = 520f;
stash.openCard(activity, checkoutUrl, config);
```

For cards, preferred height is the resting ceiling and fallback. A page can provide a shorter intrinsic content height through `[data-stash-content]` or `stash_sdk.setContentHeight(...)`. Expansion uses the available height, subject to the maximum. A page can report its current intrinsic height with `window.stash_sdk?.setContentHeight(heightInCssPixels)`. See [responsive presentation](docs/responsive-presentation.md) for measurement requirements and platform behaviour.

`orientationPreference` defaults to following the host. A card can request portrait:

```swift
config.orientationPreference = .portrait
```

```java
config.orientationPreference = StashNativeCard.CardConfig.ORIENTATION_PORTRAIT;
```

On iPhone, portrait checkout uses a separate UIKit window, including when the game's plist and controllers allow only landscape. The SDK keeps the same native card and WebView, leaves the game controller's orientation restrictions unchanged, and restores the previous orientation before returning focus. External-payment Safari handoff keeps that portrait window until the browser closes. iPad ignores this preference. Android requests portrait through the checkout activity. System windowing restrictions can still limit rotation; checkout always fits the available space.

### openBrowser

```swift
stash.openBrowser(withURL: checkoutURL, from: self)
// Optional when returning through a deep link:
stash.closeBrowser()
```

```java
stash.openBrowser(activity, checkoutUrl);
```

Android uses Chrome Custom Tabs when its optional library is present, otherwise the system browser. Browser-close tracking is internal; hosts do not forward `onActivityResult`. Android `closeBrowser()` has no effect. iOS presents `SFSafariViewController` from the supplied controller.

Android's optional short foreground keep-alive service remains disabled by default. Enable it with `setKeepAliveEnabled(true)` and customize its notification through `KeepAliveConfig`. It improves survival during a browser payment flow but does not guarantee survival under memory pressure. See [Android implementation](docs/android.md).

## Callbacks

Use `StashNativeCardDelegate` on iOS and `StashNativeCardListener` or `StashNativeCardListenerAdapter` on Android. The callback interface serves card and browser lifecycle events.

- Success reports the order string or serialized JSON supplied by the page; failure reports payment failure.
- `autoClose = false` keeps the presentation open after success/failure while still delivering callbacks.
- Permitted user dismissal and `window.close()` produce dismissal callbacks. Both respect `allowDismiss` and the purchase-processing lock.
- `openExternalBrowser` closes embedded checkout without a normal dismissal callback and reports the external-payment URL. `openLink` leaves checkout open and emits no payment callback.
- Navigation, resizing, and folding must not duplicate terminal events.

Callbacks describe UI state. Verify purchases through your backend before fulfilling items. The complete page-facing contract is [documented here](docs/stash-sdk-js.md).

## Samples and testing

Samples are in `iOS/Sample` and `Android/sample`. They can generate checkout links using a configured test instance. Sample request signing is demonstration code; production ingress secrets belong on your backend.

Use [the callback test page](https://test.stashpreview.com/) or serve `.github/test/` locally. `responsive.html` exercises intrinsic content, height hints, persistent form input, expansion, and processing locks. Use only Stash's test API and test payment data for checkout validation.

Web inspection is disabled by default. Enable `StashNativeCard.setInspectableWebViewsEnabled(true)` before opening checkout in debug/sample apps; iOS inspection requires iOS 16.4+. Android inspection is process-wide.

Build from temporary source copies and put outputs under `$HS_TEMP` (or `~/Temp`). See [maintenance and testing](docs/maintenance-and-testing.md) for commands, and [compatibility](COMPATIBILITY.md) for supported versus unverified configurations.

## Game engine wrappers

[Unity](https://github.com/stashgg/stash-unity) and [Unreal](https://github.com/stashgg/stash-unreal) bindings live in separate repositories. Existing wrapper releases are not automatically compatible with native 3.0. See [building wrappers](docs/building-wrappers.md) and the [migration guide](docs/migration-3.0.md).

## Documentation

- [Architecture and repository map](docs/architecture-overview.md)
- [Responsive sizing](docs/responsive-presentation.md)
- [iOS implementation](docs/ios.md)
- [Android implementation](docs/android.md)
- [Version history](CHANGELOG.md)
