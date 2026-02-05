# Stash for Android / iOS [![Build & Deploy](https://github.com/stashgg/stash-native/actions/workflows/main.yml/badge.svg)](https://github.com/stashgg/stash-native/actions/workflows/main.yml)

The stash-native package makes it simple to add Stash in-app purchases (IAPs) and webshops to your game or app. It delivers seamless, native-like payment flows and selection dialogs, which appear as system dialogs on Android and iOS through lightweight embedded webviews, while providing direct callbacks to your application.

## Platforms

|                                                                                            | Platform | Readme                             | Description                  |
| ------------------------------------------------------------------------------------------ | -------- | ---------------------------------- | ---------------------------- |
| <img src=".github/assets/stash_native.png" alt="Stash Native Icon" width="64" height="64"> | Android  | [Android SDK](./Android/README.md) | Android library (AAR).       |
| <img src=".github/assets/stash_native.png" alt="Stash Native Icon" width="64" height="64"> | iOS      | [iOS SDK](./iOS/README.md)         | iOS framework (XCFramework). |

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

## Quick Start

Before getting started with this library, we recommend familiarizing yourself with the basics of the Stash platform by reviewing the [official Stash documentation](https://docs.stash.gg/guides).

The typical integration process involves these steps:

1. Create a Stash Pay checkout link, a pre-authenticated webshop link, or a channel selection link.
2. Retrieve the generated URL from the step above.
3. Provide this URL to one of the supported presentation methods, configuring any desired presentation options.

### Available Methods

| Method           | Use                                                                                                                                        | Docs                                                                        |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| **openCheckout** | Drawer-style dialog that can be used for Stash Pay payment links or channel selection.                                                     | [Integrating Stash Pay](https://docs.stash.gg/guides/stash-pay/integration) |
| **openModal**    | Centered modal dialog that can be used for channel selection but also as alternative presentation style for your Stash Pay checkout links. | [Stash Pay Opt-In](https://docs.stash.gg/guides/stash-pay/opt-in)           |

---

### Callbacks / Events

Both presentation methods provide the following callbacks and events. You can implement only those that are relevant for your use case.

| Event                | Description                                                                                   |
| -------------------- | --------------------------------------------------------------------------------------------- |
| **Payment Success**  | Called when the Stash Pay / Webshop payment completes successfully.                           |
| **Payment Failure**  | Called when the payment fails.                                                                |
| **Dialog Dismissed** | Called when the user dismisses the dialog.                                                    |
| **Opt-In Response**  | Called when an channel selection response is received.                                        |
| **Page Loaded**      | Called when the checkout page finishes loading (with load time).                              |
| **Network Error**    | Called when requested dialog page load fails (no connection, HTTP 4xx/5xx, timeout after 5s). |

### Android Sample

```java
// Initialize
StashPayCard stashPay = StashPayCard.getInstance();
stashPay.setActivity(this);

// Set up callbacks
stashPay.setListener(new StashPayCard.StashPayListenerAdapter() {
    @Override
    public void onPaymentSuccess() {
        // Handle success
    }

    @Override
    public void onPaymentFailure() {
        // Handle failure
    }
});

// Open checkout (drawer-style)
stashPay.openCheckout("https://your-stash-checkout-url.com");

// Or open modal (centered modal)
stashPay.openModal("https://your-modal-url.com");
```

### iOS (Swift) Sample

```swift
// Initialize
let stashPay = StashPayCard.sharedInstance()
stashPay.delegate = self

// Open checkout (drawer-style)
stashPay.openCheckout(withURL: "https://your-checkout-url.com")

// Or open modal (centered modal)
stashPay.openModal(withURL: "https://your-modal-url.com")
```

```swift
// Implement delegate
extension YourViewController: StashPayCardDelegate {
    func stashPayCardDidCompletePayment() {
        // Handle success
    }

    func stashPayCardDidFailPayment() {
        // Handle failure
    }
}
```

### iOS (Objective-C) Sample

```objc
// Initialize
StashPayCard *stashPay = [StashPayCard sharedInstance];
stashPay.delegate = self;

// Open checkout (drawer-style)
[stashPay openCheckoutWithURL:@"https://your-checkout-url.com"];

// Or open modal (centered)
[stashPay openModalWithURL:@"https://your-modal-url.com"];
```

For detailed installation instructions and feature overviews, please see the [Android README](./Android/README.md) or the [iOS README](./iOS/README.md) next.

---

## Customizing `OpenCheckout`

### Sizing

You can fully customize the dialog size for phones, tablets, and for both portrait and landscape orientations by adjusting size properties.

### Force portrait orientation

**Force portrait on checkout** controls how the checkout card appears on phones:

- **Enabled**  
  When enabled, checkout dialog opens **portrait-locked**: a separate activity on Android and a portrait-only view on iOS. The device automatically tries to rotate to portrait mode during checkout for a consistent payment experience, similar to native purchase dialogs.

  > ⚠️ **Warning:**  
  > Make sure your app "supports" portrait orientation even if it's alandscape app, or can unlock to portrait while checkout is active. This library cannot always enforce portrait mode due to platform limitations. Read more in the platform-specific READMEs.

- **Disabled (default)**  
  Checkout appears in the **current orientation** as an card on top of your app and does not enforce rotation to potrait mode.

```java
// Android
StashPayCard stashPay = StashPayCard.getInstance();
stashPay.setForcePortraitOnCheckout(false);   // Allow all orientations
stashPay.setCardHeightRatioPortrait(0.68f);    // Portrait: full width, 68% height
stashPay.setCardWidthRatioLandscape(0.9f);    // Landscape: 90% width
stashPay.setCardHeightRatioLandscape(0.6f);   // Landscape: 60% height
// Tablet (centered card on tablets)
stashPay.setTabletWidthRatioPortrait(0.4f);   // Tablet portrait: 40% width
stashPay.setTabletHeightRatioPortrait(0.5f);  // Tablet portrait: 50% height
stashPay.setTabletWidthRatioLandscape(0.3f);  // Tablet landscape: 30% width
stashPay.setTabletHeightRatioLandscape(0.6f);  // Tablet landscape: 60% height
stashPay.openCheckout(url);
```

```swift
// iOS
let stashPay = StashPayCard.sharedInstance()
stashPay.forcePortraitOnCheckout = false      // Allow all orientations
stashPay.cardHeightRatioPortrait = 0.68       // Portrait: full width, 68% height
stashPay.cardWidthRatioLandscape = 0.9        // Landscape: 90% width
stashPay.cardHeightRatioLandscape = 0.6       // Landscape: 60% height
// iPad (centered card on iPad)
stashPay.tabletWidthRatioPortrait = 0.4       // Tablet portrait: 40% width
stashPay.tabletHeightRatioPortrait = 0.5      // Tablet portrait: 50% height
stashPay.tabletWidthRatioLandscape = 0.3      // Tablet landscape: 30% width
stashPay.tabletHeightRatioLandscape = 0.6     // Tablet landscape: 60% height
stashPay.openCheckout(withURL: url)
```

### Force Chrome Custom Tab / Safari View Controller.

You can require the checkout dialog to use Chrome Custom Tabs on Android or Safari View Controller on iOS. Instead of displaying the URL inside your game or app, the Stash native library will present the checkout experience in the device’s secure browser tab. This is useful for meeting regulatory requirements in certain regions and saves you from having to implement your own out-of-app or fallback checkout solution.

```java
// Android – use before openCheckout
stashPay.setForceWebBasedCheckout(true);
stashPay.openCheckout(checkoutUrl);
```

```swift
// iOS – use before openCheckout
stashPay.forceWebBasedCheckout = true
stashPay.openCheckout(withURL: checkoutUrl)
```

---

## Customize `OpenModal`

The modal supports behavior options and full sizing for phone and tablet in portrait and landscape:

- **showDragBar** — Show a visual drag bar at the top of the modal (default: true).
- **allowDismiss** — Allow dismissing by tapping outside or by drag (default: true).
- **Phone portrait** — `phoneWidthRatioPortrait`, `phoneHeightRatioPortrait` (e.g. 0.8, 0.5).
- **Phone landscape** — `phoneWidthRatioLandscape`, `phoneHeightRatioLandscape` (e.g. 0.5, 0.8).
- **Tablet portrait** — `tabletWidthRatioPortrait`, `tabletHeightRatioPortrait` (e.g. 0.4, 0.3).
- **Tablet landscape** — `tabletWidthRatioLandscape`, `tabletHeightRatioLandscape` (e.g. 0.3, 0.4).

```java
// Android
StashPayCard.ModalConfig config = new StashPayCard.ModalConfig();
config.showDragBar = true;       // Show visual drag bar
config.allowDismiss = true;      // Allow tap-outside to dismiss
config.phoneWidthRatioPortrait = 0.9f;   // Phone portrait: 90% width
config.phoneHeightRatioPortrait = 0.7f;  // Phone portrait: 70% height
config.phoneWidthRatioLandscape = 0.5f;  // Phone landscape: 50% width
config.phoneHeightRatioLandscape = 0.8f; // Phone landscape: 80% height
config.tabletWidthRatioPortrait = 0.4f;  // Tablet portrait: 40% width
config.tabletHeightRatioPortrait = 0.3f; // Tablet portrait: 30% height
config.tabletWidthRatioLandscape = 0.3f;  // Tablet landscape: 30% width
config.tabletHeightRatioLandscape = 0.4f;// Tablet landscape: 40% height
stashPay.openModal(url, config);
```

```swift
// iOS
let config = StashPayModalConfig()
config.showDragBar = true
config.allowDismiss = true
config.phoneWidthRatioPortrait = 0.9
config.phoneHeightRatioPortrait = 0.7
config.phoneWidthRatioLandscape = 0.5
config.phoneHeightRatioLandscape = 0.8
config.tabletWidthRatioPortrait = 0.4
config.tabletHeightRatioPortrait = 0.3
config.tabletWidthRatioLandscape = 0.3
config.tabletHeightRatioLandscape = 0.4
stashPay.openModal(withURL: url, config: config)
```

---

## Versioning

This package follows [Semantic Versioning](https://semver.org/) (major.minor.patch):

- **Major**: Breaking changes
- **Minor**: New features (backward compatible)
- **Patch**: Bug fixes

## Support

- Documentation: https://docs.stash.gg
- Email: developers@stash.gg
