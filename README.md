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
| Android       | [Android SDK](./Android/README.md)        | Native Android library with Gradle support.       |
| iOS           | [iOS SDK](./iOS/README.md)                | Native iOS framework with Swift Package Manager support. |

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

```objc
// Implement delegate
- (void)stashPayCardDidCompletePayment {
    // Handle success
}

- (void)stashPayCardDidFailPayment {
    // Handle failure
}
```

## Callbacks / Events

| Event | Description |
|-------|-------------|
| Payment Success | Called when the payment completes successfully |
| Payment Failure | Called when the payment fails |
| Dialog Dismissed | Called when the user dismisses the checkout UI |
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
