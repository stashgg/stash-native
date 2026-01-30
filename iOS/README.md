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

You can customize the size of the checkout card for both iPhones and iPads. The SDK supports orientation-specific sizing to ensure optimal display in both portrait and landscape orientations.

### Orientation-Specific Sizing (Recommended)

Configure different sizes for portrait and landscape orientations:

```swift
let stashPay = StashPayCard.sharedInstance()

// iPhone card size - portrait and landscape
stashPay.cardHeightRatioPortrait = 0.68   // 68% height in portrait (default)
stashPay.cardHeightRatioLandscape = 0.5   // 50% height in landscape (default)
stashPay.cardWidthRatioPortrait = 1.0     // Full width in portrait (default)
stashPay.cardWidthRatioLandscape = 0.8    // 80% width in landscape (default)

// iPad card size - portrait and landscape
stashPay.tabletWidthRatioPortrait = 0.4   // 40% width in portrait (default)
stashPay.tabletHeightRatioPortrait = 0.5  // 50% height in portrait (default)
stashPay.tabletWidthRatioLandscape = 0.3  // 30% width in landscape (default)
stashPay.tabletHeightRatioLandscape = 0.6 // 60% height in landscape (default)
```

### Legacy Single-Ratio Properties

The legacy single-ratio properties are still available for backward compatibility:

```swift
let stashPay = StashPayCard.sharedInstance()

// iPhone (deprecated - use portrait/landscape properties instead)
stashPay.cardHeightRatio = 0.68  // Sets portrait ratio
stashPay.cardWidthRatio = 1.0

// iPad (deprecated - use portrait/landscape properties instead)
stashPay.tabletWidthRatio = 0.8
stashPay.tabletHeightRatio = 0.75
```

### Complete Example (Swift)

```swift
let stashPay = StashPayCard.sharedInstance()
stashPay.delegate = self

// Configure iPhone card size for both orientations
stashPay.cardHeightRatioPortrait = 0.7
stashPay.cardHeightRatioLandscape = 0.5

// Configure iPad card size for both orientations
stashPay.tabletWidthRatioPortrait = 0.4
stashPay.tabletHeightRatioPortrait = 0.5
stashPay.tabletWidthRatioLandscape = 0.3
stashPay.tabletHeightRatioLandscape = 0.6

// Open checkout - sizing will automatically adjust on rotation
stashPay.openCheckout(withURL: url)
```

### Objective-C Example

```objc
StashPayCard *stashPay = [StashPayCard sharedInstance];
stashPay.delegate = self;

// Configure iPhone card size for both orientations
stashPay.cardHeightRatioPortrait = 0.7;
stashPay.cardHeightRatioLandscape = 0.5;

// Configure iPad card size for both orientations
stashPay.tabletWidthRatioPortrait = 0.4;
stashPay.tabletHeightRatioPortrait = 0.5;
stashPay.tabletWidthRatioLandscape = 0.3;
stashPay.tabletHeightRatioLandscape = 0.6;

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

