# StashPay iOS SDK

Native iOS SDK for integrating Stash Pay checkout into your iOS applications.

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(path: "../StashPay")
]
```

Or add via Xcode:
1. File > Add Packages...
2. Enter the path to the StashPay folder
3. Select "StashPay" and add to your target

### CocoaPods (Manual)

Copy the `StashPay/Sources/StashPay` folder to your project and add the files to your target.

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
    
    func openPopup() {
        // Open popup (centered modal)
        StashPayCard.sharedInstance().openPopup(withURL: "https://your-popup-url.com")
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

- (void)openPopup {
    // Open popup
    [[StashPayCard sharedInstance] openPopupWithURL:@"https://your-popup-url.com"];
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

## Custom Popup Size

```swift
let config = StashPayPopupSizeConfig(
    portraitWidth: 0.9,
    portraitHeight: 0.8,
    landscapeWidth: 0.85,
    landscapeHeight: 0.75
)

StashPayCard.sharedInstance().openPopup(withURL: url, sizeConfig: config)
```

```objc
StashPayPopupSizeConfig *config = [[StashPayPopupSizeConfig alloc] 
    initWithPortraitWidth:0.9
           portraitHeight:0.8
           landscapeWidth:0.85
          landscapeHeight:0.75];

[[StashPayCard sharedInstance] openPopupWithURL:url sizeConfig:config];
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
| `cardHeightRatio` | Height ratio (0.0-1.0) |
| `cardVerticalPosition` | Vertical position (0.0-1.0) |
| `cardWidthRatio` | Width ratio (0.0-1.0) |
| `openCheckout(withURL:)` | Open checkout in card UI |
| `openPopup(withURL:)` | Open popup with default size |
| `openPopup(withURL:sizeConfig:)` | Open popup with custom size |
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

See the `Sample/` directory for a complete working example.

To run the sample:
1. Open `StashPaySample.xcodeproj` in Xcode
2. Select a simulator or device
3. Build and run

## License

Copyright 2024 Stash. All rights reserved.
