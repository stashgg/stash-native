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
        
        // Set the current activity (required)
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

### 2. Open Card

The card slides up from the bottom on phones (portrait, full width) and appears centered on tablets. Pass a `CardConfig` for sizing, or `null` for defaults.

```java
StashPayCard.CardConfig config = new StashPayCard.CardConfig();  // or null for defaults
StashPayCard.getInstance().openCard("https://your-checkout-url.com", config);
```

### 3. Open Modal

```java
StashPayCard.ModalConfig config = new StashPayCard.ModalConfig();  // or null for defaults
StashPayCard.getInstance().openModal("https://your-modal-url.com", config);
```

### 4. Open in Browser

To open a URL in Chrome Custom Tabs (no callbacks or config):

```java
StashPayCard.getInstance().openBrowser("https://your-url.com");
```

`closeBrowser()` exists for API consistency with iOS but has no effect on Android (Chrome Custom Tabs cannot be closed programmatically).

### 5. Using StashPayListenerAdapter

If you only need to implement some callbacks, use the adapter class:

```java
stashPay.setListener(new StashPayCard.StashPayListenerAdapter() {
    @Override
    public void onPaymentSuccess() {
        Toast.makeText(MainActivity.this, "Payment Success!", Toast.LENGTH_SHORT).show();
    }
});
```

---

## Presentation Methods

**openCard** is used for checkout or other URLs in a card: [Integrating Stash Pay](https://docs.stash.gg/guides/stash-pay/integration).

**openModal** is used for the opt-in dialog: [Stash Pay Opt-In](https://docs.stash.gg/guides/stash-pay/opt-in).

| Method | Phone Behavior | Tablet Behavior | Use Case |
|--------|----------------|-----------------|----------|
| `openCard()` | Card: portrait-locked activity or overlay in current orientation (expand/collapse, resizes on rotation) | Centered modal with rotation support | Standard checkout flow |
| `openModal()` | Centered modal with custom sizing | Centered modal with custom sizing | Custom modal content, no card behavior |

---

## Card Configuration

Card sizing and orientation are set via **CardConfig** passed to `openCard(url, config)`. Pass `null` for defaults.

### Force portrait (phone)

- **forcePortrait = true** — Card opens in a **separate portrait-locked activity**. Full width, configurable height ratio.
- **forcePortrait = false (default)** — Card appears as an **overlay** in the current orientation with expand/collapse.

### CardConfig properties

**Phone:** `forcePortrait`, `cardHeightRatioPortrait`, `cardWidthRatioLandscape`, `cardHeightRatioLandscape`  
**Tablet:** `tabletWidthRatioPortrait`, `tabletHeightRatioPortrait`, `tabletWidthRatioLandscape`, `tabletHeightRatioLandscape`

```java
StashPayCard.CardConfig config = new StashPayCard.CardConfig();
config.forcePortrait = false;
config.cardHeightRatioPortrait = 0.68f;
config.cardWidthRatioLandscape = 0.9f;
config.cardHeightRatioLandscape = 0.6f;
config.tabletWidthRatioPortrait = 0.4f;
config.tabletHeightRatioPortrait = 0.5f;
config.tabletWidthRatioLandscape = 0.3f;
config.tabletHeightRatioLandscape = 0.6f;
StashPayCard.getInstance().openCard(url, config);
```

---

## Modal Configuration

The modal uses `ModalConfig` for full control over appearance and behavior.

### ModalConfig Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `showDragBar` | boolean | `true` | Show visual drag bar at top of modal |
| `allowDismiss` | boolean | `true` | Allow tap-outside to dismiss |
| `phoneWidthRatioPortrait` | float | `0.8` | Phone width in portrait (80%) |
| `phoneHeightRatioPortrait` | float | `0.5` | Phone height in portrait (50%) |
| `phoneWidthRatioLandscape` | float | `0.5` | Phone width in landscape (50%) |
| `phoneHeightRatioLandscape` | float | `0.8` | Phone height in landscape (80%) |
| `tabletWidthRatioPortrait` | float | `0.4` | Tablet width in portrait (40%) |
| `tabletHeightRatioPortrait` | float | `0.3` | Tablet height in portrait (30%) |
| `tabletWidthRatioLandscape` | float | `0.3` | Tablet width in landscape (30%) |
| `tabletHeightRatioLandscape` | float | `0.4` | Tablet height in landscape (40%) |

### Example: Custom Modal Sizing

```java
StashPayCard.ModalConfig config = new StashPayCard.ModalConfig();

// Behavior
config.showDragBar = false;     // Hide drag bar
config.allowDismiss = false;    // Prevent dismissal by tapping outside

// Phone sizing
config.phoneWidthRatioPortrait = 0.95f;
config.phoneHeightRatioPortrait = 0.8f;
config.phoneWidthRatioLandscape = 0.8f;
config.phoneHeightRatioLandscape = 0.9f;

// Tablet sizing
config.tabletWidthRatioPortrait = 0.5f;
config.tabletHeightRatioPortrait = 0.6f;
config.tabletWidthRatioLandscape = 0.4f;
config.tabletHeightRatioLandscape = 0.7f;

StashPayCard.getInstance().openModal(url, config);
```

---

## Open in Browser

To open a URL in Chrome Custom Tabs (no callbacks or config):

```java
StashPayCard.getInstance().openBrowser(url);
```

---

## API Reference

### Core Methods

| Method | Description |
|--------|-------------|
| `getInstance()` | Get the singleton instance |
| `setActivity(Activity)` | Set the current activity (required before any presentation) |
| `setListener(StashPayListener)` | Set the event listener for callbacks |

### Presentation Methods

| Method | Description |
|--------|-------------|
| `openCard(String url, CardConfig config)` | Open card (bottom sheet on phones, centered on tablets). Pass `null` for default config. |
| `openModal(String url, ModalConfig config)` | Open centered modal. Pass `null` for default config. |
| `openBrowser(String url)` | Open URL in Chrome Custom Tabs (no callbacks). |
| `closeBrowser()` | No-op on Android (API consistency with iOS). |
| `dismiss()` | Dismiss the current dialog |
| `resetPresentationState()` | Reset internal state and dismiss |

### State Properties

| Method | Description |
|--------|-------------|
| `isCurrentlyPresented()` | Returns `true` if a dialog is currently shown |
| `isPurchaseProcessing()` | Returns `true` if a payment is in progress |

### CardConfig (for openCard)

| Property | Default | Description |
|----------|---------|-------------|
| `forcePortrait` | `false` | If true, card opens in portrait-locked activity; if false, overlay in current orientation |
| `cardHeightRatioPortrait` | `0.68` | Card height in portrait (0.1-1.0) |
| `cardWidthRatioLandscape` | `0.9` | Card width in landscape (0.1-1.0) |
| `cardHeightRatioLandscape` | `0.6` | Card height in landscape (0.1-1.0) |
| `tabletWidthRatioPortrait` | `0.4` | Tablet card width in portrait (0.1-1.0) |
| `tabletHeightRatioPortrait` | `0.5` | Tablet card height in portrait (0.1-1.0) |
| `tabletWidthRatioLandscape` | `0.3` | Tablet card width in landscape (0.1-1.0) |
| `tabletHeightRatioLandscape` | `0.6` | Tablet card height in landscape (0.1-1.0) |

### Other Settings

| Method | Description |
|--------|-------------|
| `setForceWebBasedCheckout(boolean)` | Use Chrome Custom Tabs instead of in-app UI |

---

## Callbacks (StashPayListener)

| Callback | Description |
|----------|-------------|
| `onPaymentSuccess()` | Payment completed successfully |
| `onPaymentFailure()` | Payment failed |
| `onDialogDismissed()` | User dismissed the dialog |
| `onOptInResponse(String optinType)` | Opt-in response received |
| `onPageLoaded(long loadTimeMs)` | Page finished loading (time in milliseconds) |
| `onNetworkError()` | Network error during initial page load (see below) |

### Network Error Handling

The `onNetworkError()` callback is triggered when the initial page load fails. This occurs in the following scenarios:

- **No network connection**: Device is offline or has no internet access
- **Page load failure**: DNS failure, connection refused, or other network issues
- **HTTP errors**: Server returns 4xx or 5xx status codes (404, 500, etc.)
- **Timeout**: Page does not load within 5 seconds

When a network error occurs:
1. The dialog is automatically dismissed
2. The `onNetworkError()` callback is invoked
3. The `onDialogDismissed()` callback is NOT called (to avoid duplicate handling)

```java
stashPay.setListener(new StashPayCard.StashPayListenerAdapter() {
    @Override
    public void onNetworkError() {
        // Handle network error - show retry option, offline message, etc.
        Toast.makeText(context, "Network error. Please check your connection.", Toast.LENGTH_LONG).show();
    }
});
```

---

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

The sample app includes:
- Separate URL inputs for Checkout and Modal
- Advanced Options for Checkout (web view mode, force portrait, landscape sizing)
- Advanced Options for Modal (drag bar, dismiss, sizing)
