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
| **Checkout** | Card-style checkout (bottom sheet on phones, centered on tablets) with expand/collapse gestures |
| **Modal** | Centered modal presentation on all devices with customizable sizing |
| **Web-Based** | Fallback to system browser (Chrome Custom Tabs / SFSafariViewController) |
| **Callbacks** | Events for payment success, failure, dismissal, and page load |
| **Customization** | Configurable sizing for phones and tablets in both orientations |

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

| Method | Phone Behavior | Tablet Behavior | Use Case |
|--------|----------------|-----------------|----------|
| `openCheckout` | Card slides from bottom (portrait, full width) | Centered modal with rotation | Standard checkout flow |
| `openModal` | Centered modal with custom sizing | Centered modal with custom sizing | Custom modal content |

---

## Callbacks / Events

| Event | Description |
|-------|-------------|
| Payment Success | Called when the payment completes successfully |
| Payment Failure | Called when the payment fails |
| Dialog Dismissed | Called when the user dismisses the checkout UI |
| Opt-In Response | Called when an opt-in response is received |
| Page Loaded | Called when the checkout page finishes loading (with load time) |

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

## Web-Based Checkout

If you need to use the system browser instead of the in-app card UI:

```java
// Android - Use Chrome Custom Tabs
stashPay.setForceWebBasedCheckout(true);
```

```swift
// iOS - Use SFSafariViewController
stashPay.forceWebBasedCheckout = true
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
