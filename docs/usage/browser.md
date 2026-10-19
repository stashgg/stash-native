---
title: In-Game Browser
parent: Usage
nav_order: 3
description: Open Stash Pay checkout or webshop links in Safari View Controller or Chrome Custom Tabs without leaving the game.
---

# In-Game Browser

The in-game browser opens Stash Pay checkout or webshop links in Safari View Controller (iOS) or Chrome Custom Tabs (Android). Players stay in the game, and checkout brings them back with a deep link.

![Checkout in Safari View Controller on iPhone and Chrome Custom Tabs on Android](../assets/images/openbrowser-devices-dark.png)

## Open the browser

```swift
StashNative.sharedInstance().openBrowser(withURL: url, from: self)
```

```java
StashNative.getInstance().openBrowser(activity, url);
```

On Android, Custom Tabs need `androidx.browser` from [Package Installation](installation.md#android). Without it, links open in the system browser. On iOS, `closeBrowser()` closes Safari from code.

## Return to the game

The browser does not report payments through callbacks. Checkout opens your app with a deep link instead. Set your app's URL scheme in Stash Studio under **Project Settings > General > App Deeplink Protocol**, without `://`, for example `mygame`.

| Deep link | Sent when |
|---|---|
| `mygame://stash-pay/success` | The purchase completed |
| `mygame://stash-pay/failure` | The purchase failed |
| `mygame://stash-pay/cancel` | The player left checkout without paying. Not every checkout sends it. |

Register the scheme in your app. On iOS, add it to `CFBundleURLTypes`. On Android, add an intent filter with the `stash-pay` host, and give its activity `android:launchMode="singleTask"` so the deep link returns to the running game:

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="mygame" android:host="stash-pay" />
</intent-filter>
```

On iOS, close Safari when the deep link arrives. `dismissSafariViewController(withResult:)` also sends the payment result to your [callbacks](callbacks.md#in-game-browser):

```swift
func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
    guard let url = contexts.first?.url, url.scheme == "mygame", url.host == "stash-pay" else { return }
    switch url.path {
    case "/success": StashNative.sharedInstance().dismissSafariViewController(withResult: true)
    case "/failure": StashNative.sharedInstance().dismissSafariViewController(withResult: false)
    default: StashNative.sharedInstance().closeBrowser()
    }
}
```

Confirm every purchase on your backend before granting items.

## Portrait Safari (iOS)

On iPhone, a landscape game can show Safari in portrait. The game returns to its orientation when Safari closes. iPad ignores this setting.

```swift
let config = StashNativeBrowserConfig()
config.orientationPreference = .portrait
StashNative.sharedInstance().openBrowser(withURL: url, from: self, config: config)
```

## Keep-alive service (Android)

![Keep-alive notification on Android, reading Payment in progress and Tap to return to the game](../assets/images/keep-alive-notification-dark.png){: .close-up }

On low-memory devices, Android can stop the game while the player pays in the browser. The keep-alive service shows a notification while the browser is open, which makes this less likely. It is off by default; we recommend enabling it.

```java
StashNative.KeepAliveConfig config = new StashNative.KeepAliveConfig();
config.notificationTitle = "Payment in progress";
config.notificationText = "Tap to return to the game";
config.notificationIconResId = R.drawable.ic_notification; // 0 uses the SDK icon
StashNative.getInstance().setKeepAliveConfig(config);
StashNative.getInstance().setKeepAliveEnabled(true);
```

Write the notification text in the player's language.

On Android 13 and later, players see the notification only if the game has the `POST_NOTIFICATIONS` permission. The SDK does not declare or request it, so add it to your manifest and request it at runtime. Without it, the service still runs, but the notification stays hidden.

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

## Callbacks

See [In-Game Browser callbacks](callbacks.md#in-game-browser) for the browser-dismissed event.
