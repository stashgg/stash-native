---
title: Setting Callbacks
nav_order: 6
description: How the shared Stash Native callback receiver works, and why.
---

# Setting Callbacks

Every feature reports events to one shared receiver: a delegate on iOS or a listener on Android. Each feature page lists its events: [Checkout Card](checkout-card.md#callbacks), [In-Game Browser](browser.md#callbacks), and [QR Code Linking](codelink.md#callbacks).

## Set the receiver

Set the receiver on the main thread before you open anything. Open calls work from any thread.

```swift
StashNative.sharedInstance().delegate = self
```

```java
StashNative.getInstance().setListener(listener);
```

- iOS: all `StashNativeDelegate` methods are optional. The SDK does not retain the delegate; keep your own reference.
- Android: extend `StashNative.StashNativeListenerAdapter` and override only what you need. The SDK keeps the listener until you call `setListener(null)`.

## How shared callbacks work

- `StashNative` runs one presentation at a time, so one receiver serves every feature. Each event has its own method, which tells you the feature that sent it.
- The receiver is global, not tied to an open call. Each event goes to the receiver set when it fires, including events from a presentation that is already open. Use a long-lived object, such as your store or app controller, not a screen that can close or be recreated during checkout.
- Events arrive on the main thread, so you can update the UI directly.
- Clearing the receiver stops future events. Events are never replayed.
- Engine wrappers register one receiver and forward its events to the engine; see [Engine Wrappers](../architecture/engine-wrappers.md).

## Order of events

Each presentation ends with one final event, listed on its feature page. Resume the game when it arrives. You can open the next card, browser, or scanner from that callback. `resetPresentationState()` closes the card or scanner, and Safari on iOS, without sending events.
