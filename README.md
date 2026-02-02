# Stash Pay for Android / iOS [Preview]

Standalone packages that enable Stash Pay checkout flows within native Android and iOS applications. 
They are adapted from the [Stash Pay Unity plugin](https://github.com/stashgg/stash-unity) to work directly with native applications.

> [!WARNING]
> This repository is currently being actively built. Information may be incorrect or outdated. Please reach out to developers@stash.gg if you have any issues.

> [!WARNING]
> Stash primarily maintains the Unity version. Changes and patches may be propagated slowly to the standalone versions.

## Platforms

| Platform      | Readme                      | Description                                      |
|---------------|-------------------------------------------|--------------------------------------------------|
| Android       | [Android SDK](./Android/README.md)        | Native Android library (AAR) with Gradle support.       |
| iOS           | [iOS SDK](./iOS/README.md)                | Native iOS framework (XCFramework) with Swift Package Manager support. |

## Downloads

Pre-built binaries are available on [GitHub Releases](https://github.com/stashgg/stash-native/releases):

- **Android**: `stashpay-release.aar`
- **iOS**: `StashPay.xcframework.zip`

---

## Quick Start

### Android

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

// Open checkout (card-style)
stashPay.openCheckout("https://your-checkout-url.com");

// Or open modal (centered)
stashPay.openModal("https://your-modal-url.com");
```

### iOS (Swift)

```swift
// Initialize
let stashPay = StashPayCard.sharedInstance()
stashPay.delegate = self

// Open checkout (card-style)
stashPay.openCheckout(withURL: "https://your-checkout-url.com")

// Or open modal (centered)
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

### iOS (Objective-C)

```objc
// Initialize
StashPayCard *stashPay = [StashPayCard sharedInstance];
stashPay.delegate = self;

// Open checkout (card-style)
[stashPay openCheckoutWithURL:@"https://your-checkout-url.com"];

// Or open modal (centered)
[stashPay openModalWithURL:@"https://your-modal-url.com"];
```

---

## Presentation Methods

| Method | Use | Docs |
|--------|-----|------|
| **openCheckout** | Stash Pay **checkout URLs** only. Phone: card , Tablet: centered modal. | [Integrating Stash Pay](https://docs.stash.gg/guides/stash-pay/integration) |
| **openModal** | Stash Pay **opt-in flows** (payment channel selection, etc.). Centered modal on all devices. | [Stash Pay Opt-In](https://docs.stash.gg/guides/stash-pay/opt-in) |

---

## Callbacks / Events

| Event | Description |
|-------|-------------|
| Payment Success | Called when the payment completes successfully |
| Payment Failure | Called when the payment fails |
| Dialog Dismissed | Called when the user dismisses the checkout UI |
| Opt-In Response | Called when an opt-in response is received |
| Page Loaded | Called when the checkout page finishes loading (with load time) |
| Network Error | Called when initial page load fails (no connection, HTTP 4xx/5xx, timeout after 5s) |

---


## Checkout Configuration

### Force portrait checkout

**Force portrait on checkout** controls how the checkout card appears on phones:

- **Enabled**  
  When enabled, checkout opens **portrait-locked**: a separate activity on Android and a portrait-only view on iOS. The device automatically rotates to portrait mode during checkout for a consistent payment experience, similar to native purchase dialogs. Make sure your app supports portrait orientation or can unlock to portrait while checkout is active, as this library cannot always force the portrait mode due to platform limitations.

- **Disabled (default)**  
  Checkout appears in the **current orientation** as an card on top of your app and does not enforce rotation to potrait mode.

```java
// Android
StashPayCard stashPay = StashPayCard.getInstance();
stashPay.setForcePortraitOnCheckout(false);   // Allow all orientations
stashPay.setCardHeightRatioPortrait(0.68f);    // Portrait: full width, 68% height
stashPay.setCardWidthRatioLandscape(0.9f);    // Landscape: 90% width
stashPay.setCardHeightRatioLandscape(0.6f);   // Landscape: 60% height
stashPay.openCheckout(url);
```

```swift
// iOS
let stashPay = StashPayCard.sharedInstance()
stashPay.forcePortraitOnCheckout = false      // Allow all orientations
stashPay.cardHeightRatioPortrait = 0.68       // Portrait: full width, 68% height
stashPay.cardWidthRatioLandscape = 0.9        // Landscape: 90% width
stashPay.cardHeightRatioLandscape = 0.6       // Landscape: 60% height
stashPay.openCheckout(withURL: url)
```

See the Android and iOS READMEs for full checkout configuration and API details.

### Force web–based checkout

**Force web–based checkout** opens Stash Pay checkout links in the system browser (Chrome Custom Tabs on Android, SFSafariViewController on iOS) instead of the in-app card.

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

## Modal Configuration

The modal supports sizing customization:

```java
// Android
StashPayCard.ModalConfig config = new StashPayCard.ModalConfig();
config.showDragBar = true;       // Show visual drag bar
config.allowDismiss = true;      // Allow tap-outside to dismiss
config.phoneWidthRatioPortrait = 0.9f;   // 90% width on phone portrait
config.phoneHeightRatioPortrait = 0.7f;  // 70% height on phone portrait
// ... more sizing options
stashPay.openModal(url, config);
```

```swift
// iOS
let config = StashPayModalConfig()
config.showDragBar = true
config.allowDismiss = true
config.phoneWidthRatioPortrait = 0.9
config.phoneHeightRatioPortrait = 0.7
// ... more sizing options
stashPay.openModal(withURL: url, config: config)
```

See platform-specific READMEs for full configuration options.

---

---

## Sample Apps

Both platforms include sample apps (StashNativeDemo) demonstrating SDK integration:

- **Android**: `./Android/sample/` - Run with `./gradlew :sample:installDebug`
- **iOS**: `./iOS/Sample/` - Open `StashPaySample.xcodeproj` in Xcode

The sample apps include:
- Separate URL inputs for Checkout and Modal
- Advanced Options for Checkout (web view mode, force portrait, landscape sizing)
- Advanced Options for Modal (drag bar, dismiss, sizing)

---

## Versioning

This package follows [Semantic Versioning](https://semver.org/) (major.minor.patch):

- **Major**: Breaking changes
- **Minor**: New features (backward compatible)
- **Patch**: Bug fixes

## Support

- Documentation: https://docs.stash.gg
- Email: developers@stash.gg
