# Stash Native [![Lint](https://github.com/stashgg/stash-native/actions/workflows/lint.yml/badge.svg)](https://github.com/stashgg/stash-native/actions/workflows/lint.yml) [![Build & Deploy](https://github.com/stashgg/stash-native/actions/workflows/main.yml/badge.svg)](https://github.com/stashgg/stash-native/actions/workflows/main.yml)

<p align="left">
  <img src="docs/assets/images/stash_native_rounded.png" width="128" height="128" alt="Stash Native logo"/>
</p>

Stash Native adds Stash Pay checkout and Stash webshop account linking to native iOS and Android games and apps. For web pages and web apps, use [stash-web](https://github.com/stashgg/stash-web).

**Documentation:** [stashgg.github.io/stash-native](https://stashgg.github.io/stash-native/)

## Game Engine Wrappers

Unity and Unreal Engine games use these wrappers instead of installing Stash Native directly.

| | Engine | Repository |
| --- | --- | --- |
| <img src="docs/assets/images/stash_unity_rounded.png" alt="Unity" width="64" height="64"> | Unity | [stash-unity](https://github.com/stashgg/stash-unity) |
| <img src="docs/assets/images/stash_unreal_rounded.png" alt="Unreal Engine" width="64" height="64"> | Unreal Engine | [stash-unreal](https://github.com/stashgg/stash-unreal) |

## Installation

Prebuilt packages are on [GitHub Releases](https://github.com/stashgg/stash-native/releases). The core package covers the Checkout Card and In-Game Browser. QR Code Linking needs the optional `StashNativeCodeLink` module.

**iOS 15 or later.** In Xcode, choose **File > Add Package Dependencies**, enter `https://github.com/stashgg/stash-native.git`, and add the `StashNative` library. Without Swift Package Manager, embed `StashNative.xcframework`.

**Android API 21 or later.** Copy the AAR into `app/libs/` and add it with its dependencies:

```groovy
dependencies {
    implementation files('libs/StashNative-<tag>.aar')
    implementation 'androidx.core:core:1.12.0'
    implementation 'androidx.webkit:webkit:1.11.0'
    implementation 'androidx.window:window:1.4.0'
    implementation 'androidx.window:window-java:1.4.0'
}
```

Optional dependencies and the QR Code Linking module: [Package Installation](https://stashgg.github.io/stash-native/#package-installation).

## Checkout Card

![Checkout card on iPhone, unfolded iPhone Duo, and iPad](docs/assets/images/opencard-devices-dark.png)

Shows Stash Pay checkout in a native card over the game. The card fits phones, tablets, foldables, and split screen.

```swift
// iOS
StashNative.sharedInstance().openCard(withURL: checkoutURL, from: self, config: nil)
```

```java
// Android
StashNative.getInstance().openCard(activity, checkoutUrl, null);
```

Docs: [Checkout Card](https://stashgg.github.io/stash-native/usage/checkout-card.html)

## In-Game Browser

![Checkout in Safari View Controller on iPhone and Chrome Custom Tabs on Android](docs/assets/images/openbrowser-devices-dark.png)

Opens checkout or webshop links in Safari View Controller (iOS) or Chrome Custom Tabs (Android) without leaving the game.

```swift
// iOS
StashNative.sharedInstance().openBrowser(withURL: url, from: self)
```

```java
// Android
StashNative.getInstance().openBrowser(activity, url);
```

Docs: [In-Game Browser](https://stashgg.github.io/stash-native/usage/browser.html)

## QR Code Linking

![QR code scanners on iPhone and Android](docs/assets/images/codelink-devices-dark.png)

Links a player's Stash webshop account by scanning the QR code the webshop shows. Needs the optional `StashNativeCodeLink` module.

```swift
// iOS
StashNative.sharedInstance().openScanner(from: self, config: nil)
```

```java
// Android
StashNative.getInstance().openScanner(activity, null);
```

Docs: [QR Code Linking](https://stashgg.github.io/stash-native/usage/codelink.html)

## Sample Apps

Open the [iOS sample](iOS/Sample/StashNativeSample/StashNativeSample.xcodeproj) in Xcode, or run `./gradlew :sample:installDebug` from [`Android/`](Android/). To try the card without a checkout link, open `https://test.stashpreview.com`. Docs: [Sample Apps](https://stashgg.github.io/stash-native/usage/sample-apps.html)

## Versioning and Support

Releases follow [Semantic Versioning](https://semver.org/); see the [changelog](CHANGELOG.md). Integration guides are on [docs.stash.gg](https://docs.stash.gg). Questions: [developers@stash.gg](mailto:developers@stash.gg).
