# Stash Pay for Android / iOS

Unity package for integrating in-app Stash Pay checkout flows inside native iOS and Android applications.

These packages are standalone ports of the Stash Pay Unity plugin, designed to work with native Android and iOS projects.

# Platform SDKs

### [Android SDK](./Android/README.md)

Native Android library with Gradle support.

### [iOS SDK](./iOS/README.md)

Native iOS framework with Swift Package Manager support.

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

// Open checkout
stashPay.openCheckout("https://your-checkout-url.com");
```

### iOS (Swift)

```swift
// Initialize
let stashPay = StashPayCard.sharedInstance()
stashPay.delegate = self

// Open checkout
stashPay.openCheckout(withURL: "https://your-checkout-url.com")
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

// Open checkout
[stashPay openCheckoutWithURL:@"https://your-checkout-url.com"];
```

## Presentation Modes

### Checkout Card

Opens the checkout URL in a sliding card that appears from the bottom of the screen (or centered on tablets).

```java
// Android
stashPay.openCheckout(url);
```

```swift
// iOS
stashPay.openCheckout(withURL: url)
```

### Popup

Opens a centered modal popup, ideal for opt-in flows or smaller content.

```java
// Android - default size
stashPay.openPopup(url);

// Android - custom size
StashPayCard.PopupSizeConfig config = new StashPayCard.PopupSizeConfig(
    0.9f,   // portrait width multiplier
    0.8f,   // portrait height multiplier
    0.85f,  // landscape width multiplier
    0.75f   // landscape height multiplier
);
stashPay.openPopup(url, config);
```

```swift
// iOS - default size
stashPay.openPopup(withURL: url)

// iOS - custom size
let config = StashPayPopupSizeConfig(
    portraitWidth: 0.9,
    portraitHeight: 0.8,
    landscapeWidth: 0.85,
    landscapeHeight: 0.75
)
stashPay.openPopup(withURL: url, sizeConfig: config)
```

## Callbacks / Events

| Event | Description |
|-------|-------------|
| Payment Success | Called when the payment completes successfully |
| Payment Failure | Called when the payment fails |
| Dialog Dismissed | Called when the user dismisses the checkout UI |
| Opt-in Response | Called when an opt-in response is received |
| Page Loaded | Called when the checkout page finishes loading (with load time) |

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

## Sample Apps

Both platforms include sample apps demonstrating SDK integration:

- **Android**: `./Android/sample/`
- **iOS**: `./iOS/Sample/`

## Versioning

This package follows [Semantic Versioning](https://semver.org/) (major.minor.patch):

- **Major**: Breaking changes
- **Minor**: New features (backward compatible)
- **Patch**: Bug fixes

## Support

- Documentation: https://docs.stash.gg
- Email: developers@stash.gg
