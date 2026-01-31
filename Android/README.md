# StashPay Android SDK

Native Android SDK for integrating Stash Pay checkout into your Android applications.

> [!WARNING]
> This repository is currently being actively built. Information may be incorrect or outdated. Please reach out to developers@stash.gg if you have any issues.

## Installation

### AAR File (Recommended)

Download the pre-built AAR from [GitHub Releases](https://github.com/stashgg/stash-native/releases):

1. Download `stashpay-release.aar` from the latest release
2. Copy it to your project's `libs` folder
3. Add to your `build.gradle`:

```groovy
dependencies {
    implementation files('libs/stashpay-release.aar')
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'androidx.browser:browser:1.7.0'
}
```

### Build AAR Locally

Alternatively, build the AAR yourself:

```bash
cd Android
./gradlew :stashpay:assembleRelease
```

The AAR will be at `stashpay/build/outputs/aar/stashpay-release.aar`.

### Gradle (Local Module)

For development or if you want to modify the source:

1. Copy the `stashpay` module to your project
2. Add to your `settings.gradle`:

```groovy
include ':stashpay'
```

3. Add dependency in your app's `build.gradle`:

```groovy
dependencies {
    implementation project(':stashpay')
}
```

## Quick Start

### 1. Initialize the SDK

```java
import com.stash.popup.StashPayCard;

public class MainActivity extends AppCompatActivity {
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        // Get the singleton instance
        StashPayCard stashPay = StashPayCard.getInstance();
        
        // Set the current activity
        stashPay.setActivity(this);
        
        // Set up event listener
        stashPay.setListener(new StashPayCard.StashPayListener() {
            @Override
            public void onPaymentSuccess() {
                Log.i("StashPay", "Payment successful");
            }
            
            @Override
            public void onPaymentFailure() {
                Log.e("StashPay", "Payment failed");
            }
            
            @Override
            public void onDialogDismissed() {
                Log.d("StashPay", "Dialog was dismissed");
            }
            
            @Override
            public void onOptInResponse(String optinType) {
                Log.d("StashPay", "Opt-in: " + optinType);
            }
            
            @Override
            public void onPageLoaded(long loadTimeMs) {
                Log.d("StashPay", "Page loaded in " + loadTimeMs + "ms");
            }
        });
    }
    
    @Override
    protected void onResume() {
        super.onResume();
        // Update activity reference when resumed
        StashPayCard.getInstance().setActivity(this);
    }
}
```

### 2. Open Checkout

```java
// Open checkout card (slides up from bottom)
StashPayCard.getInstance().openCheckout("https://your-checkout-url.com");
```

### 3. Using StashPayListenerAdapter

If you only need to implement some callbacks, use the adapter class:

```java
stashPay.setListener(new StashPayCard.StashPayListenerAdapter() {
    @Override
    public void onPaymentSuccess() {
        // Only implement the callbacks you need
        Toast.makeText(MainActivity.this, "Payment Success!", Toast.LENGTH_SHORT).show();
    }
});
```

## Card Size Configuration

Card size configuration is **optional**. Only change it if your specific Stash Pay configuration requires custom sizing. In most scenarios, leave the default sizing unchanged.

You can customize the size of the checkout card for phones and tablets as follows.

### Phone

The phone card **always forces portrait** and **always uses full screen width**. Only the card height is configurable (as a ratio of screen height in portrait):

```java
StashPayCard stashPay = StashPayCard.getInstance();

// Phone: only height is configurable (card is always full width, portrait only)
stashPay.setCardHeightRatioPortrait(0.68f);   // 68% of screen height (default)
```

### Tablet

On tablets the card can rotate; configure width and height for portrait and landscape:

```java
StashPayCard stashPay = StashPayCard.getInstance();

stashPay.setTabletWidthRatioPortrait(0.4f);   // 40% width in portrait (default)
stashPay.setTabletHeightRatioPortrait(0.5f);  // 50% height in portrait (default)
stashPay.setTabletWidthRatioLandscape(0.3f);  // 30% width in landscape (default)
stashPay.setTabletHeightRatioLandscape(0.6f); // 60% height in landscape (default)
```

### Complete Example

```java
StashPayCard stashPay = StashPayCard.getInstance();
stashPay.setActivity(this);

// Phone: customize card height only (portrait, full width)
stashPay.setCardHeightRatioPortrait(0.7f);

// Tablet: configure for both orientations
stashPay.setTabletWidthRatioPortrait(0.4f);
stashPay.setTabletHeightRatioPortrait(0.5f);
stashPay.setTabletWidthRatioLandscape(0.3f);
stashPay.setTabletHeightRatioLandscape(0.6f);

stashPay.openCheckout(url);
```

## Web-Based Checkout

To use Chrome Custom Tabs instead of the in-app card UI:

```java
StashPayCard.getInstance().setForceWebBasedCheckout(true);
StashPayCard.getInstance().openCheckout(url);
```

## API Reference

### StashPayCard

| Method | Description |
|--------|-------------|
| `getInstance()` | Get the singleton instance |
| `setActivity(Activity)` | Set the current activity (required) |
| `setListener(StashPayListener)` | Set the event listener |
| `openCheckout(String url)` | Open checkout in card UI |
| `dismiss()` | Dismiss the current dialog |
| `resetPresentationState()` | Reset and dismiss |
| `isCurrentlyPresented()` | Check if dialog is shown |
| `setForceWebBasedCheckout(boolean)` | Use Chrome Custom Tabs |
| `isPurchaseProcessing()` | Check if payment is in progress |
| `setCardHeightRatioPortrait(float)` | Set phone card height (0.1-1.0). Phone card is always portrait and full width. |
| `setTabletWidthRatioPortrait(float)` | Set tablet card width in portrait (0.1-1.0) |
| `setTabletHeightRatioPortrait(float)` | Set tablet card height in portrait (0.1-1.0) |
| `setTabletWidthRatioLandscape(float)` | Set tablet card width in landscape (0.1-1.0) |
| `setTabletHeightRatioLandscape(float)` | Set tablet card height in landscape (0.1-1.0) |

### StashPayListener

| Callback | Description |
|----------|-------------|
| `onPaymentSuccess()` | Payment completed successfully |
| `onPaymentFailure()` | Payment failed |
| `onDialogDismissed()` | User dismissed the dialog |
| `onOptInResponse(String)` | Opt-in response received |
| `onPageLoaded(long)` | Page finished loading |

## Requirements

- Android 5.0+ (API level 21)
- AndroidX libraries
- Internet permission (automatically included)

## ProGuard

The SDK includes ProGuard rules. If you encounter issues, add:

```proguard
-keep class com.stash.popup.** { *; }
```

## Sample App

See the `sample/` directory for a complete working example (StashNativeDemo).

```bash
cd Android
./gradlew :sample:installDebug
```

The sample app includes a toggle to switch between the native card UI and Chrome Custom Tabs checkout.
