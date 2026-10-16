---
title: Browser
parent: Usage
nav_order: 3
description: Open checkout or webshop links in Safari View Controller or Chrome Custom Tabs.
---

# Browser

![Checkout in Safari View Controller on iPhone and Chrome Custom Tabs on Android](https://raw.githubusercontent.com/stashgg/stash-native/main/.github/assets/openbrowser-devices-dark.png)

## Open

Opens a checkout or webshop URL in Safari View Controller (iOS) or Chrome Custom Tabs (Android). Without `androidx.browser`, Android opens the system browser. The browser sends no payment callbacks, so checkout returns its result through a deep link.

```swift
StashNativeCard.sharedInstance().openBrowser(withURL: url, from: self)
```

```java
StashNativeCard.getInstance().openBrowser(activity, url);
```

## Close detection

`stashNativeCardDidCloseBrowser` (iOS) and `onBrowserClosed()` (Android) fire when the user closes the browser. Android tracks Custom Tabs itself; hosts do not forward `onActivityResult`.

## Close from a deep link (iOS)

```swift
StashNativeCard.sharedInstance().closeBrowser()
```

Calls `stashNativeCardDidDismiss`, then `stashNativeCardDidCloseBrowser`. To also report the result, call `dismissSafariViewController(withResult: true)` instead; it calls the payment callback first. Android cannot close Custom Tabs.

## Portrait Safari (iOS)

```swift
let config = StashNativeBrowserConfig()
config.orientationPreference = .portrait
StashNativeCard.sharedInstance().openBrowser(withURL: url, from: self, config: config)
```

Applies on iPhone. iPad ignores it.

## Keep-alive service (Android)

Runs a short foreground service while the browser is open, so low-memory devices are less likely to kill the game. It is off by default.

```java
StashNativeCard.KeepAliveConfig config = new StashNativeCard.KeepAliveConfig();
config.notificationTitle = "Payment in progress";
config.notificationText = "Tap to return to the game";
config.notificationIconResId = R.drawable.ic_notification; // 0 uses the SDK icon
StashNativeCard.getInstance().setKeepAliveConfig(config);
StashNativeCard.getInstance().setKeepAliveEnabled(true);
```

The service stops when the game returns to the foreground.
