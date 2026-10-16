---
title: Browser
parent: Usage
nav_order: 3
description: Open Stash Pay checkout or webshop links in Safari View Controller or Chrome Custom Tabs, and return players through a deep link.
---

# Browser

The browser opens Stash Pay checkout or pre-authenticated webshop links in Safari View Controller (iOS) or Chrome Custom Tabs (Android). Players stay in your app, and the page has full browser features. Use it for your webshop, or when you prefer browser checkout over the [checkout card](checkout-card.md).

![Checkout in Safari View Controller on iPhone and Chrome Custom Tabs on Android](https://raw.githubusercontent.com/stashgg/stash-native/main/.github/assets/openbrowser-devices-dark.png)

The browser cannot send payment events to the game. Checkout returns the result through your app's [deep link](#return-to-the-game) instead.

## Open the browser

```swift
StashNativeCard.sharedInstance().openBrowser(withURL: url, from: self)
```

```java
StashNativeCard.getInstance().openBrowser(activity, url);
```

On Android, add `androidx.browser` ([Installation](installation.md#aar)). Without it, the link opens in the system browser and the player leaves your app.

## Return to the game

The checkout result page has a button that opens your app with a deep link. Set your app's URL scheme in Stash Studio under **Project Settings > General > App Deeplink Protocol**, without `://` (for example `mygame`). Checkout then sends:

| Deep link | Sent when |
|---|---|
| `mygame://stash-pay/success` | The purchase completed |
| `mygame://stash-pay/failure` | The purchase failed |
| `mygame://stash-pay/cancel` | The player left checkout without paying. Not every checkout layout sends it. |

Register the scheme in your app. On iOS, add it to `CFBundleURLTypes`. On Android, match the `stash-pay` host as well as the scheme:

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="mygame" android:host="stash-pay" />
</intent-filter>
```

On iOS, close Safari when the deep link arrives. `dismissSafariViewController(withResult:)` closes it and reports the result through your [payment callbacks](callbacks.md):

```swift
func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
    guard let url = contexts.first?.url, url.scheme == "mygame", url.host == "stash-pay" else { return }
    switch url.path {
    case "/success": StashNativeCard.sharedInstance().dismissSafariViewController(withResult: true)
    case "/failure": StashNativeCard.sharedInstance().dismissSafariViewController(withResult: false)
    default: StashNativeCard.sharedInstance().closeBrowser()
    }
}
```

Android cannot close Custom Tabs from code. Give the activity that receives the deep link `android:launchMode="singleTask"`, as the sample app does, so the running game comes to the front instead of a second copy opening over the browser.

As with the card, confirm every purchase on your backend before granting items.

## Browser closed

`stashNativeCardDidCloseBrowser` (iOS) and `onBrowserClosed()` (Android) fire when the browser closes, whether the player tapped Done or your app closed it. Use it to resume the game. Android needs no `onActivityResult` forwarding.

## Portrait Safari (iOS)

Landscape games can show Safari in portrait on iPhone. The game returns to its orientation when Safari closes. iPad ignores the setting, and Custom Tabs on Android control their own orientation.

```swift
let config = StashNativeBrowserConfig()
config.orientationPreference = .portrait
StashNativeCard.sharedInstance().openBrowser(withURL: url, from: self, config: config)
```

## Keep-alive service (Android)

On devices with little memory, Android can stop a backgrounded game while the player pays in the browser, and the player returns to a restarted game. The keep-alive service runs a short foreground service with a notification while the browser is open, which makes that less likely. It is off by default; we recommend enabling it.

```java
StashNativeCard.KeepAliveConfig config = new StashNativeCard.KeepAliveConfig();
config.notificationTitle = "Payment in progress";
config.notificationText = "Tap to return to the game";
config.notificationIconResId = R.drawable.ic_notification; // 0 uses the SDK icon
StashNativeCard.getInstance().setKeepAliveConfig(config);
StashNativeCard.getInstance().setKeepAliveEnabled(true);
```

Set the notification text in the player's language. The service stops when the game returns to the foreground. The manifest entries it needs are already in the SDK.
