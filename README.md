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

## Features

| Feature | Description |
|---------|-------------|
| **openCheckout** | Stash Pay checkout URLs: card-style (phone portrait-locked, tablet centered) |
| **openModal** | Stash Pay opt-in flows: centered modal on all devices |
| **Force web–based checkout** | openCheckout only: use system browser (Chrome Custom Tabs / SFSafariViewController) instead of in-app card |
| **Callbacks** | Payment success, failure, dismissal, opt-in response, page load, network error |
| **Customization** | Configurable sizing for checkout and modal (phone/tablet, portrait/landscape) |

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
| **openCheckout** | Stash Pay **checkout URLs** only. Phone: portrait-locked card; tablet: centered modal. | [Integrating Stash Pay](https://docs.stash.gg/guides/stash-pay/integration) |
| **openModal** | Stash Pay **opt-in flows** (payment channel selection, etc.). Centered modal on all devices. | [Stash Pay Opt-In](https://docs.stash.gg/guides/stash-pay/opt-in) |

Do not use openCheckout for opt-in URLs or openModal for checkout URLs; each method is for its own URL type.

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

## Modal Configuration

The modal supports extensive customization:

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

## Force web–based checkout (openCheckout only)

**Force web–based checkout** applies only to **openCheckout**. It opens Stash Pay checkout links in the system browser (Chrome Custom Tabs on Android, SFSafariViewController on iOS) instead of the in-app card. It does not affect openModal.

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

## Sample Apps

Both platforms include sample apps (StashNativeDemo) demonstrating SDK integration:

- **Android**: `./Android/sample/` - Run with `./gradlew :sample:installDebug`
- **iOS**: `./iOS/Sample/` - Open `StashPaySample.xcodeproj` in Xcode

The sample apps include:
- Separate URL inputs for Checkout and Modal
- Advanced Options for Checkout (web view mode, sizing)
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
