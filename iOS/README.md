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
    
    func openCard() {
        // Open card (slides up from bottom on iPhone, centered on iPad). Pass nil for default config.
        let config = StashPayCardConfig()
        StashPayCard.sharedInstance().openCard(withURL: "https://your-checkout-url.com", config: config)
    }
    
    func openModal() {
        // Open centered modal (same on iPhone and iPad). Pass nil for default config.
        let config = StashPayModalConfig()
        config.showDragBar = true
        config.allowDismiss = true
        // Sizing: phoneWidthRatioPortrait, phoneHeightRatioPortrait, phoneWidthRatioLandscape, phoneHeightRatioLandscape, tabletWidthRatioPortrait, tabletHeightRatioPortrait, tabletWidthRatioLandscape, tabletHeightRatioLandscape (see Modal Configuration below)
        StashPayCard.sharedInstance().openModal(withURL: "https://your-modal-url.com", config: config)
    }
    
    func openBrowser() {
        // Open URL in SFSafariViewController (no callbacks). Call closeBrowser() to dismiss when handling deeplinks.
        StashPayCard.sharedInstance().openBrowser(withURL: "https://your-url.com")
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
    [StashPayCard sharedInstance].delegate = self;
}

- (void)openCard {
    StashPayCardConfig *config = [[StashPayCardConfig alloc] init];
    [[StashPayCard sharedInstance] openCardWithURL:@"https://your-checkout-url.com" config:config];
}

- (void)openModal {
    StashPayModalConfig *config = [[StashPayModalConfig alloc] init];
    config.showDragBar = YES;
    config.allowDismiss = YES;
    [[StashPayCard sharedInstance] openModalWithURL:@"https://your-modal-url.com" config:config];
}

- (void)openBrowser {
    [[StashPayCard sharedInstance] openBrowserWithURL:@"https://your-url.com"];
    // Call closeBrowser to dismiss when handling deeplinks
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

---

## Presentation Methods

**openCard** is used for checkout or other URLs in a card: [Integrating Stash Pay](https://docs.stash.gg/guides/stash-pay/integration).

**openModal** is used for the opt-in dialog: [Stash Pay Opt-In](https://docs.stash.gg/guides/stash-pay/opt-in).

| Method | iPhone Behavior | iPad Behavior | Use Case |
|--------|-----------------|---------------|----------|
| `openCard(withURL:config:)` | Card: portrait-only or current orientation (expand/collapse, resizes on rotation) | Centered modal with rotation support | Standard checkout flow |
| `openModal(withURL:config:)` | Centered modal with custom sizing | Centered modal with custom sizing | Custom modal content, no card behavior |

---

## Checkout Configuration

### Card configuration (StashPayCardConfig)

Card sizing and orientation are set via **StashPayCardConfig** passed to `openCard(withURL:config:)`. Pass `nil` for defaults.

- **forcePortrait = true** — Card is shown in a **portrait-only** view (full width, configurable height ratio).
- **forcePortrait = false (default)** — Card appears in the **current orientation** with expand/collapse.

```swift
let config = StashPayCardConfig()
config.forcePortrait = false
config.cardHeightRatioPortrait = 0.68
config.cardWidthRatioLandscape = 0.9
config.cardHeightRatioLandscape = 0.6
config.tabletWidthRatioPortrait = 0.4
config.tabletHeightRatioPortrait = 0.5
config.tabletWidthRatioLandscape = 0.3
config.tabletHeightRatioLandscape = 0.6
StashPayCard.sharedInstance().openCard(withURL: url, config: config)
```

---

## Modal Configuration

The modal uses `StashPayModalConfig` for full control over appearance and behavior.

### StashPayModalConfig Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `showDragBar` | BOOL | `YES` | Show visual drag bar at top of modal |
| `allowDismiss` | BOOL | `YES` | Allow tap-outside to dismiss |
| `phoneWidthRatioPortrait` | CGFloat | `0.8` | iPhone width in portrait (80%) |
| `phoneHeightRatioPortrait` | CGFloat | `0.5` | iPhone height in portrait (50%) |
| `phoneWidthRatioLandscape` | CGFloat | `0.5` | iPhone width in landscape (50%) |
| `phoneHeightRatioLandscape` | CGFloat | `0.8` | iPhone height in landscape (80%) |
| `tabletWidthRatioPortrait` | CGFloat | `0.4` | iPad width in portrait (40%) |
| `tabletHeightRatioPortrait` | CGFloat | `0.3` | iPad height in portrait (30%) |
| `tabletWidthRatioLandscape` | CGFloat | `0.3` | iPad width in landscape (30%) |
| `tabletHeightRatioLandscape` | CGFloat | `0.4` | iPad height in landscape (40%) |

### Example: Custom Modal Sizing (Swift)

```swift
let config = StashPayModalConfig()

// Behavior
config.showDragBar = false      // Hide drag bar
config.allowDismiss = false     // Prevent dismissal by tapping outside

// iPhone sizing
config.phoneWidthRatioPortrait = 0.95
config.phoneHeightRatioPortrait = 0.8
config.phoneWidthRatioLandscape = 0.8
config.phoneHeightRatioLandscape = 0.9

// iPad sizing
config.tabletWidthRatioPortrait = 0.5
config.tabletHeightRatioPortrait = 0.6
config.tabletWidthRatioLandscape = 0.4
config.tabletHeightRatioLandscape = 0.7

StashPayCard.sharedInstance().openModal(withURL: url, config: config)
```

### Example: Custom Modal Sizing (Objective-C)

```objc
StashPayModalConfig *config = [[StashPayModalConfig alloc] init];

// Behavior
config.showDragBar = NO;
config.allowDismiss = NO;

// iPhone sizing
config.phoneWidthRatioPortrait = 0.95;
config.phoneHeightRatioPortrait = 0.8;
config.phoneWidthRatioLandscape = 0.8;
config.phoneHeightRatioLandscape = 0.9;

// iPad sizing
config.tabletWidthRatioPortrait = 0.5;
config.tabletHeightRatioPortrait = 0.6;
config.tabletWidthRatioLandscape = 0.4;
config.tabletHeightRatioLandscape = 0.7;

[[StashPayCard sharedInstance] openModalWithURL:url config:config];
```

---

## Web-Based Checkout

To use SFSafariViewController instead of the in-app UI:

```swift
StashPayCard.sharedInstance().forceWebBasedCheckout = true
StashPayCard.sharedInstance().openCard(withURL: url, config: config)
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

---

## API Reference

### Core Properties & Methods

| Property/Method | Description |
|-----------------|-------------|
| `sharedInstance()` | Get the singleton instance |
| `delegate` | Set the delegate to receive callbacks |

### Presentation Methods

| Method | Description |
|--------|-------------|
| `openCard(withURL:config:)` | Open card (bottom sheet on iPhone, centered on iPad). Pass nil for default config. |
| `openBrowser(withURL:)` | Open URL in SFSafariViewController (no callbacks). |
| `closeBrowser` | Dismiss the Safari view (e.g. when handling deeplinks). |
| `openModal(withURL:)` | Open centered modal with default configuration |
| `openModal(withURL:config:)` | Open centered modal with custom configuration |
| `dismiss()` | Dismiss the current dialog |
| `resetPresentationState()` | Reset internal state and dismiss |
| `closeBrowser` | Dismiss the Safari view (e.g. when handling deeplinks). |
| `dismissSafariViewControllerWithResult(_:)` | Dismiss Safari VC and fire success/failure callback (advanced). |

### State Properties

| Property | Description |
|----------|-------------|
| `isCurrentlyPresented` | Returns `true` if a dialog is currently shown |
| `isPurchaseProcessing` | Returns `true` if a payment is in progress |

### StashPayCardConfig (for openCard)

| Property | Default | Description |
|----------|---------|-------------|
| `forcePortrait` | `false` | If true, show card in portrait only; if false, allow all orientations with rotation and expand/collapse |
| `cardHeightRatioPortrait` | `0.68` | Card height as ratio of screen height in portrait (0.1-1.0) |
| `cardWidthRatioLandscape` | `0.9` | Card width as ratio of screen width in landscape (0.1-1.0); used only when force portrait is off |
| `cardHeightRatioLandscape` | `0.6` | Card height as ratio of screen height in landscape (0.1-1.0); used only when force portrait is off |

### Checkout Sizing (iPad)

| Property | Default | Description |
|----------|---------|-------------|
| `tabletWidthRatioPortrait` | `0.4` | Card width in portrait (0.1-1.0) |
| `tabletHeightRatioPortrait` | `0.5` | Card height in portrait (0.1-1.0) |
| `tabletWidthRatioLandscape` | `0.3` | Card width in landscape (0.1-1.0) |
| `tabletHeightRatioLandscape` | `0.6` | Card height in landscape (0.1-1.0) |

### Other

Use `openBrowser(withURL:)` to open a URL in SFSafariViewController (no callbacks). Use `closeBrowser` to dismiss it (e.g. when handling deeplinks).

---

## Callbacks (StashPayCardDelegate)

All delegate methods are optional.

| Method | Description |
|--------|-------------|
| `stashPayCardDidCompletePayment()` | Payment completed successfully |
| `stashPayCardDidFailPayment()` | Payment failed |
| `stashPayCardDidDismiss()` | User dismissed the dialog |
| `stashPayCardDidReceiveOptIn(_:)` | Opt-in response received |
| `stashPayCardDidLoadPage(_:)` | Page finished loading (time in milliseconds) |
| `stashPayCardDidEncounterNetworkError()` | Network error during initial page load (see below) |

### Network Error Handling

The `stashPayCardDidEncounterNetworkError()` callback is triggered when the initial page load fails. This occurs in the following scenarios:

- **No network connection**: Device is offline or has no internet access
- **Page load failure**: DNS failure, connection refused, or other network issues
- **HTTP errors**: Server returns 4xx or 5xx status codes (404, 500, etc.)
- **Timeout**: Page does not load within 5 seconds

When a network error occurs:
1. The dialog is automatically dismissed
2. The `stashPayCardDidEncounterNetworkError()` callback is invoked
3. The `stashPayCardDidDismiss()` callback is NOT called (to avoid duplicate handling)

**Swift:**
```swift
func stashPayCardDidEncounterNetworkError() {
    // Handle network error - show retry option, offline message, etc.
    showAlert(title: "Network Error", message: "Please check your connection.")
}
```

**Objective-C:**
```objc
- (void)stashPayCardDidEncounterNetworkError {
    // Handle network error
    [self showAlertWithTitle:@"Network Error" message:@"Please check your connection."];
}
```

---

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

The sample app includes:
- Separate URL inputs for Checkout and Modal
- Advanced Options for Checkout (web view mode, force portrait, landscape sizing)
- Advanced Options for Modal (drag bar, dismiss, sizing)
