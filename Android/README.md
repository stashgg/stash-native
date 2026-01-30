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

You can customize the size of the checkout card for both phones and tablets. The SDK supports orientation-specific sizing to ensure optimal display in both portrait and landscape orientations.

### Orientation-Specific Sizing (Recommended)

Configure different sizes for portrait and landscape orientations:

```java
StashPayCard stashPay = StashPayCard.getInstance();

// Phone card size - portrait and landscape
stashPay.setCardHeightRatioPortrait(0.68f);   // 68% height in portrait (default)
stashPay.setCardHeightRatioLandscape(0.5f);   // 50% height in landscape (default)
stashPay.setCardWidthRatioPortrait(1.0f);     // Full width in portrait (default)
stashPay.setCardWidthRatioLandscape(0.8f);    // 80% width in landscape (default)

// Tablet card size - portrait and landscape
stashPay.setTabletWidthRatioPortrait(0.6f);   // 60% width in portrait (default)
stashPay.setTabletHeightRatioPortrait(0.8f);  // 80% height in portrait (default)
stashPay.setTabletWidthRatioLandscape(0.8f);  // 80% width in landscape (default)
stashPay.setTabletHeightRatioLandscape(0.65f); // 65% height in landscape (default)
```

### Legacy Single-Ratio Properties

The legacy single-ratio methods are still available for backward compatibility:

```java
StashPayCard stashPay = StashPayCard.getInstance();

// Phone (deprecated - use portrait/landscape methods instead)
stashPay.setCardHeightRatio(0.68f);  // Sets portrait ratio
stashPay.setCardWidthRatio(1.0f);

// Tablet (deprecated - use portrait/landscape methods instead)
stashPay.setTabletWidthRatio(0.8f);
stashPay.setTabletHeightRatio(0.75f);
```

### Complete Example

```java
StashPayCard stashPay = StashPayCard.getInstance();
stashPay.setActivity(this);

// Configure phone card size for both orientations
stashPay.setCardHeightRatioPortrait(0.7f);
stashPay.setCardHeightRatioLandscape(0.5f);

// Configure tablet card size for both orientations
stashPay.setTabletWidthRatioPortrait(0.6f);
stashPay.setTabletHeightRatioPortrait(0.8f);
stashPay.setTabletWidthRatioLandscape(0.8f);
stashPay.setTabletHeightRatioLandscape(0.65f);

// Open checkout - sizing will automatically adjust on rotation
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
| `setCardHeightRatio(float)` | Set phone card height (0.1-1.0) |
| `setCardWidthRatio(float)` | Set phone card width (0.1-1.0) |
| `setTabletWidthRatio(float)` | Set tablet card width (0.1-1.0) |
| `setTabletHeightRatio(float)` | Set tablet card height (0.1-1.0) |
| `getCardHeightRatio()` | Get phone card height ratio |
| `getCardWidthRatio()` | Get phone card width ratio |
| `getTabletWidthRatio()` | Get tablet card width ratio |
| `getTabletHeightRatio()` | Get tablet card height ratio |

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
