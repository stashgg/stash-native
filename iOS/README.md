# StashPay iOS SDK

Native iOS SDK for integrating Stash Pay checkout into your iOS applications.

> [!WARNING]
> This repository is currently being actively built. Information may be incorrect or outdated. Please reach out to developers@stash.gg if you have any issues.

## Installation

### XCFramework (Recommended)

Download the pre-built XCFramework from [GitHub Releases](https://github.com/stashgg/stash-native/releases):

1. Download `StashPay.xcframework.zip` from the latest release
2. Unzip and drag `StashPay.xcframework` into your Xcode project
3. In your target's **General** tab, ensure it appears under **Frameworks, Libraries, and Embedded Content**
4. Set the embed option to **Embed & Sign**

### Swift Package Manager

Add via Xcode:
1. File > Add Packages...
2. Enter the repository URL: `https://github.com/stashgg/stash-native.git`
3. Select "StashPay" and add to your target

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/stashgg/stash-native.git", from: "1.0.0")
]
```

### Manual Integration

1. Copy all files from `StashPay/Sources/StashPay/` to your project
2. Add to your target
3. Ensure these frameworks are linked:
   - `SafariServices.framework`
   - `WebKit.framework`

## Quick Start

### Swift

```swift
import StashPay

class ViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the delegate to receive callbacks
        StashPayCard.sharedInstance().delegate = self
    }
    
    func openCheckout() {
        // Open checkout card (slides up from bottom)
        StashPayCard.sharedInstance().openCheckout(withURL: "https://your-checkout-url.com")
    }
}

// MARK: - StashPayCardDelegate

extension ViewController: StashPayCardDelegate {
    
    func stashPayCardDidCompletePayment() {
        print("Payment successful")
    }
    
    func stashPayCardDidFailPayment() {
        print("Payment failed")
    }
    
    func stashPayCardDidDismiss() {
        print("Dialog was dismissed")
    }
    
    func stashPayCardDidReceiveOptIn(_ optinType: String) {
        print("Opt-in: \(optinType)")
    }
    
    func stashPayCardDidLoadPage(_ loadTimeMs: Double) {
        print("Page loaded in \(loadTimeMs)ms")
    }
}
```

### Objective-C

```objc
#import <StashPay/StashPay.h>

@interface ViewController () <StashPayCardDelegate>
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Set the delegate to receive callbacks
    [StashPayCard sharedInstance].delegate = self;
}

- (void)openCheckout {
    // Open checkout card
    [[StashPayCard sharedInstance] openCheckoutWithURL:@"https://your-checkout-url.com"];
}

#pragma mark - StashPayCardDelegate

- (void)stashPayCardDidCompletePayment {
    NSLog(@"Payment successful");
}

- (void)stashPayCardDidFailPayment {
    NSLog(@"Payment failed");
}

- (void)stashPayCardDidDismiss {
    NSLog(@"Dialog was dismissed");
}

- (void)stashPayCardDidReceiveOptIn:(NSString *)optinType {
    NSLog(@"Opt-in: %@", optinType);
}

- (void)stashPayCardDidLoadPage:(double)loadTimeMs {
    NSLog(@"Page loaded in %.0fms", loadTimeMs);
}

@end
```

## Card Size Configuration

You can customize the size of the checkout card for both iPhones and iPads.

### iPhone Card Size

On iPhones, the checkout card slides up from the bottom. You can configure its height:

```swift
let stashPay = StashPayCard.sharedInstance()

// Set card height (0.1 to 1.0, default 0.6 = 60% of screen height)
stashPay.cardHeightRatio = 0.75  // 75% of screen height

// Set card width (0.1 to 1.0, default 1.0 = full width)
stashPay.cardWidthRatio = 0.9  // 90% of screen width
```

### iPad Card Size

On iPads, the checkout card appears centered on screen. You can configure its size:

```swift
let stashPay = StashPayCard.sharedInstance()

// Set tablet width (0.1 to 1.0, default 0.8 = 80% of screen width)
stashPay.tabletWidthRatio = 0.7  // 70% of screen width

// Set tablet height (0.1 to 1.0, default 0.75 = 75% of screen height)
stashPay.tabletHeightRatio = 0.85  // 85% of screen height
```

### Complete Example (Swift)

```swift
let stashPay = StashPayCard.sharedInstance()
stashPay.delegate = self

// Configure iPhone card size
stashPay.cardHeightRatio = 0.75

// Configure iPad card size
stashPay.tabletWidthRatio = 0.7
stashPay.tabletHeightRatio = 0.85

// Open checkout with configured sizes
stashPay.openCheckout(withURL: url)
```

### Objective-C Example

```objc
StashPayCard *stashPay = [StashPayCard sharedInstance];
stashPay.delegate = self;

// Configure iPhone card size
stashPay.cardHeightRatio = 0.75;

// Configure iPad card size
stashPay.tabletWidthRatio = 0.7;
stashPay.tabletHeightRatio = 0.85;

// Open checkout with configured sizes
[stashPay openCheckoutWithURL:url];
```

## Web-Based Checkout

To use SFSafariViewController instead of the in-app card UI:

```swift
StashPayCard.sharedInstance().forceWebBasedCheckout = true
StashPayCard.sharedInstance().openCheckout(withURL: url)
```

## Handling Deep Links

When using `forceWebBasedCheckout`, you may need to handle deep links to dismiss the Safari view controller:

```swift
func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    
    if url.absoluteString.contains("stash/purchaseSuccess") {
        StashPayCard.sharedInstance().dismissSafariViewController(withResult: true)
        return true
    } else if url.absoluteString.contains("stash/purchaseFailure") {
        StashPayCard.sharedInstance().dismissSafariViewController(withResult: false)
        return true
    }
    
    return false
}
```

## API Reference

### StashPayCard

| Property/Method | Description |
|-----------------|-------------|
| `sharedInstance()` | Get the singleton instance |
| `delegate` | Set the delegate to receive callbacks |
| `forceWebBasedCheckout` | Use SFSafariViewController |
| `isCurrentlyPresented` | Check if dialog is shown |
| `isPurchaseProcessing` | Check if payment is in progress |
| `cardHeightRatio` | iPhone card height ratio (0.1-1.0) |
| `cardVerticalPosition` | Vertical position (0.0-1.0) |
| `cardWidthRatio` | iPhone card width ratio (0.1-1.0) |
| `tabletWidthRatio` | iPad card width ratio (0.1-1.0) |
| `tabletHeightRatio` | iPad card height ratio (0.1-1.0) |
| `openCheckout(withURL:)` | Open checkout in card UI |
| `dismiss()` | Dismiss the current dialog |
| `resetPresentationState()` | Reset and dismiss |
| `dismissSafariViewController()` | Dismiss Safari VC |
| `dismissSafariViewController(withResult:)` | Dismiss with success/failure |

### StashPayCardDelegate

| Method | Description |
|--------|-------------|
| `stashPayCardDidCompletePayment()` | Payment completed successfully |
| `stashPayCardDidFailPayment()` | Payment failed |
| `stashPayCardDidDismiss()` | User dismissed the dialog |
| `stashPayCardDidReceiveOptIn(_:)` | Opt-in response received |
| `stashPayCardDidLoadPage(_:)` | Page finished loading |

All delegate methods are optional.

## Requirements

- iOS 13.0+
- Xcode 14+
- Swift 5.5+ (for Swift Package Manager)

## Sample App

See the `Sample/` directory for a complete working example (StashNativeDemo).

To run the sample:
1. Open `Sample/StashPaySample.xcodeproj` in Xcode
2. Select a simulator or device
3. Build and run

The sample app includes a toggle to switch between the native card UI and Safari-based checkout.

