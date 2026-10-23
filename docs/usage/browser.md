---
title: In-Game Browser
nav_order: 4
description: Open Stash Pay checkout or webshop links in Safari View Controller or Chrome Custom Tabs without leaving the game.
---

# In-Game Browser

The in-game browser opens [checkout](https://docs.stash.gg/guides/stash-pay/integration#create-a-checkout-link) or [webshop](https://docs.stash.gg/guides/stash-webshop/about) links in Safari View Controller (iOS) or Chrome Custom Tabs (Android) without leaving the game.

![Checkout in Safari View Controller on iPhone and Chrome Custom Tabs on Android](../assets/images/openbrowser-devices-dark.png)

## Open the browser

```swift
StashNative.sharedInstance().openBrowser(withURL: url, from: self)
```

```java
StashNative.getInstance().openBrowser(activity, url);
```

On Android, Custom Tabs need `androidx.browser` ([Package Installation](../index.md#android)). Without it, links open in the system browser. On iOS, `closeBrowser()` closes Safari. On Android, Custom Tabs cannot be closed programmatically, so it only closes a browser that checkout opened over the card (see below). While a card is open, `openBrowser` is ignored on iOS and opens on Android. `isCurrentlyPresented` is `true` while Safari is open, and `false` while Custom Tabs are open. When checkout opens the browser over the card, the card stays presented and `isCurrentlyPresented` stays `true` on both platforms.

## Handling Results

{: .warning }
Unlike the Checkout Card, the in-game browser sends no direct payment callbacks, because the browser is isolated from the game. Checkout reports results to the game through a deep link instead.

Set your URL scheme in [Stash Studio](https://docs.stash.gg/guides/get-started/stash-studio/getting-started) under **Project Settings > General > App Deeplink Protocol**, without `://`, for example `mygame`.

| Deep link | Sent when |
|---|---|
| `mygame://stash-pay/success` | The purchase completed |
| `mygame://stash-pay/failure` | The purchase failed |

Register the scheme with the system, as described by [Apple](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app) and [Android](https://developer.android.com/training/app-links/create-deeplinks).

On iOS, close Safari when the deep link arrives. `dismissSafariViewController(withResult:)` closes it and sends the payment [callback](#callbacks):

```swift
StashNative.sharedInstance().dismissSafariViewController(withResult: true)  // mygame://stash-pay/success
StashNative.sharedInstance().dismissSafariViewController(withResult: false) // mygame://stash-pay/failure
```

Checkout can also open the browser over the card, which stays open for the player's return. The checkout page then reports the payment itself, and the game hears it once. On iOS, `dismissSafariViewController(withResult:)` closes Safari back to the card; with `autoClose` on, it also closes the card with that result. On Android, call `closeBrowser()` when the deep link arrives to close the browser and return to the card.

[Confirm every purchase](https://docs.stash.gg/guides/stash-pay/integration#processing-purchase) on your backend before granting items.

## Forcing Portrait Browser (iOS)

On iPhone, Safari can open in portrait in a landscape game. iPad ignores this setting. On Android, the orientation of Chrome Custom Tabs cannot be forced.

```swift
let config = StashNativeBrowserConfig()
config.orientationPreference = .portrait
StashNative.sharedInstance().openBrowser(withURL: url, from: self, config: config)
```

## Keep-alive service (Android)

![Keep-alive notification on Android, reading Payment in progress and Tap to return to the game](../assets/images/keep-alive-notification-dark.png){: .close-up }

On low-memory devices, Android can stop the game while the player pays in the browser. The keep-alive service lowers that risk by showing a foreground notification while the browser is open. It is off by default; we recommend enabling it.

```java
StashNative.KeepAliveConfig config = new StashNative.KeepAliveConfig();
config.notificationTitle = "Payment in progress";
config.notificationText = "Tap to return to the game";
config.notificationIconResId = R.drawable.ic_notification; // 0 uses the SDK icon
StashNative.getInstance().setKeepAliveConfig(config);
StashNative.getInstance().setKeepAliveEnabled(true);
```

Write the notification text in the player's language.

On Android 13 and later, the notification appears only if the game has the `POST_NOTIFICATIONS` permission. The SDK does not declare or request it: add it to your manifest and request it at runtime. Without it, the service still runs, but the notification is hidden.

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

## Callbacks

These events go to the shared receiver; see [Setting Callbacks](callbacks.md).

| Callback (iOS / Android) | Fires when |
|---|---|
| `stashNativeDidDismissBrowser()`<br>`onBrowserDismissed()` | The browser closes, after `openBrowser` or an external payment that closed the card |

The browser ends with browser dismissed. A browser opened over the card sends no browser event; the card continues and ends with its own events. On iOS, `dismissSafariViewController(withResult:)` first sends payment success or failure; see [Checkout Card callbacks](checkout-card.md#callbacks).
