---
title: Browser
parent: Usage reference
nav_order: 3
description: Open Stash Pay checkout or a webshop in Safari View Controller or Chrome Custom Tabs, detect browser close, and keep the game alive on Android.
---

# Browser

`openBrowser` opens a Stash Pay checkout or pre-authenticated webshop link in the platform browser. The same browser path handles external payments started from a checkout card with `stash_sdk.openExternalBrowser(url)`.

![Checkout in Safari View Controller on iPhone and Chrome Custom Tabs on Android](https://raw.githubusercontent.com/stashgg/stash-native/main/.github/assets/openbrowser-devices-dark.png)

| | iOS | Android |
|---|---|---|
| Surface | `SFSafariViewController` presented from the given controller | Chrome Custom Tabs through an internal proxy activity. `ACTION_VIEW` when `androidx.browser` is absent. |
| Bridge | None | None |
| Payment callbacks | None. Return results through a deep link. | None. Return results through a deep link. |
| Close callback | `stashNativeCardDidCloseBrowser` | `onBrowserClosed()` |
| Programmatic close | `closeBrowser()` | Not possible. `closeBrowser()` does nothing. |
| Orientation preference | `StashNativeBrowserConfig.orientationPreference` | Custom Tabs control their own orientation |

## Open the browser

Swift:

```swift
StashNativeCard.sharedInstance().openBrowser(withURL: url, from: self)
```

Objective-C:

```objc
[[StashNativeCard sharedInstance] openBrowserWithURL:url fromViewController:self];
```

Java:

```java
StashNativeCard.getInstance().openBrowser(activity, url);
```

The URL rules and the `theme` parameter are the same as for cards. On iOS the browser occupies the single presentation slot, so `openCard` and `codeLink` are ignored until Safari closes.

## Portrait browser on iPhone

```swift
let config = StashNativeBrowserConfig()
config.orientationPreference = .portrait
StashNativeCard.sharedInstance().openBrowser(withURL: url, from: self, config: config)
```

Safari keeps its native sheet presentation in the SDK's portrait window and restores the host orientation when it closes. iPad ignores the preference. The two-argument method follows the host. `closeBrowser()` and `resetPresentationState()` cancel a browser that is still waiting for portrait geometry.

## Close detection

| Platform | Detection |
|---|---|
| iOS | Safari's Done button calls `stashNativeCardDidCloseBrowser`. `closeBrowser()`, `dismiss()`, and swiping away a portrait Safari sheet call `stashNativeCardDidDismiss` first, then `stashNativeCardDidCloseBrowser`. |
| Android, Custom Tabs | The internal `StashNativeBrowserProxyActivity` receives the Custom Tabs result. Engagement signals cover tabs closed from floating or minimized UI on Chrome versions that support them. Hosts do not forward `onActivityResult`. |
| Android, `ACTION_VIEW` | `onBrowserClosed` fires after the host activity resumes and stays resumed for 500 ms |

Chrome builds without engagement support can delay the close callback in some floating-window cases until the next host activity transition.

## Deep link return

Browser checkouts report results by redirecting to your app's deep link. Handle the link in the app, then close the browser on iOS:

Swift:

```swift
// In your URL handler, after verifying the result on your backend:
StashNativeCard.sharedInstance().closeBrowser()
```

`dismissSafariViewController(withResult:)` closes Safari and also reports a payment result through the delegate: `true` calls `stashNativeCardDidCompletePayment(withOrder:)` with `nil`, `false` calls `stashNativeCardDidFailPayment`. `stashNativeCardDidDismiss` and `stashNativeCardDidCloseBrowser` follow. It works for `openBrowser` and for external payment browsers.

Android cannot close Custom Tabs programmatically. Handle the deep link in your activity; `onBrowserClosed` fires when the SDK detects that the tab closed.

## Android keep-alive service

Low-memory Android devices can kill a backgrounded game while the user pays in the browser. The optional keep-alive service runs a short foreground service with a low-importance notification while the browser is open. It is off by default.

```java
StashNativeCard stash = StashNativeCard.getInstance();
stash.setKeepAliveEnabled(true);

StashNativeCard.KeepAliveConfig config = new StashNativeCard.KeepAliveConfig();
config.notificationTitle = "Payment in progress";
config.notificationText = "Tap to return to the game";
config.notificationIconResId = R.drawable.ic_notification; // 0 uses the SDK icon
stash.setKeepAliveConfig(config);
```

| Member | Meaning |
|---|---|
| `setKeepAliveEnabled(boolean)` | Starts the service before `openBrowser` and external payment browser launches |
| `isKeepAliveEnabled()` | Current setting |
| `setKeepAliveConfig(KeepAliveConfig)` | Notification title, text, and small icon. `null` or empty strings use the SDK's strings; `null` config clears customization. |

The service stops when the host or checkout activity resumes. It uses the `shortService` foreground type, which Android 14 limits in duration; the SDK stops it on timeout. The service and its permissions are merged into the host manifest whether or not the feature is enabled. Enabling it reduces process kills; it does not prevent them.
