# Keep-Alive Service (Android)

This document describes the **keep-alive** foreground service used when checkout is opened in Chrome Custom Tabs or the system browser. It explains how it works, how it is started and stopped, and the notification behavior.

---

## Purpose

When the user is sent to Chrome Custom Tabs (CCT) or the default browser to complete payment, the host app moves to the background. Android may kill background apps under memory pressure. The keep-alive service:

- Runs as a **foreground service** so the system is less likely to kill the app process while the user is in the browser.
- Shows a **persistent notification** (“Active” / “Keeping the session active.”) so the user knows the session is still active. The notification is not clickable.
- Stops automatically when the app regains focus, when a timeout elapses, or when the platform enforces its own limit (Android 14+).

---

## Components

| Component | Role |
|-----------|------|
| **StashKeepAliveService** | Foreground `Service` that shows the notification, applies timeouts, and handles platform timeout (Android 14+). |
| **StashKeepAliveManager** | Static helper to start and stop the service from activities or the SDK. |
| **Manifest** | Declares the service and `foregroundServiceType="shortService"` (Android 14+). |

---

## How It Works

### 1. Starting the service

The service is started only when **force web-based checkout** (e.g. Chrome Custom Tabs) is used. The SDK or the portrait checkout activity calls:

```java
StashKeepAliveManager.start(context, "checkout", 30000L);
```

Example from `StashPayCardPortraitActivity` when opening CCT:

```java
if (forceSafariViewController) {
    requestNotificationPermissionIfNeeded(activity);
    StashKeepAliveManager.start(activity, "checkout", 30000L);
}
if (StashWebViewUtils.isChromeCustomTabsAvailable(activity)) {
    StashWebViewUtils.openWithChromeCustomTabs(activity, url);
}
```

`StashKeepAliveManager.start()` builds an `Intent` for `StashKeepAliveService`, adds extras `reason` and `timeoutBufferMs`, and starts the service with `ContextCompat.startForegroundService()` on API 26+ (or `startService()` on older versions).

### 2. Service lifecycle

When the service starts (`onStartCommand`):

- It **starts in the foreground** with a notification so the process is protected.
- It **schedules a soft timeout** so the service does not run indefinitely:
  - **Android 13 and below:** 5 minutes.
  - **Android 14+:** platform limit is 3 minutes for `shortService`; the service uses that limit minus a configurable buffer (default 30 seconds), so the soft timeout is about 2.5 minutes to avoid hitting the platform limit unexpectedly.

Relevant constants in `StashKeepAliveService`:

```java
private static final long SOFT_TIMEOUT_MS_LEGACY = 5 * 60 * 1000; // 5 minutes
private static final long PLATFORM_TIMEOUT_MS = 3 * 60 * 1000;    // 3 minutes (Android 14+)
private static final long DEFAULT_TIMEOUT_BUFFER_MS = 30 * 1000; // 30 seconds
```

If the platform timeout fires on Android 14+, the service implements `onTimeout()` and stops immediately to avoid ANR.

### 3. Stopping the service

The service stops when:

1. **App regains focus** – The activity that launched checkout calls `StashKeepAliveManager.stop(context)` in `onResume()` (and optionally in `onDestroy()`). That sends an intent with `ACTION_STOP`; the service then calls `stopForeground(true)` and `stopSelf()`.
2. **Soft timeout** – The handler runnable fires; the service removes the notification and stops.
3. **Platform timeout (Android 14+)** – `onTimeout()` is invoked; the service cleans up and stops.

Example of stopping when the user returns to the app (`StashPayCardPortraitActivity`):

```java
@Override
protected void onResume() {
    super.onResume();
    // Stop keep-alive service when app regains focus
    StashKeepAliveManager.stop(this);
    // ...
}
```

### 4. Notification (not clickable)

The service builds a foreground notification with title “Active” and text “Keeping the session active.” No content intent is set, so the notification is **not clickable**—it only indicates that the session is active.

```java
private Notification createNotification() {
    // Notification is not clickable; it only indicates the session is active
    int icon = getApplicationInfo().icon;
    if (icon == 0) {
        icon = android.R.drawable.ic_menu_info_details;
    }
    return new NotificationCompat.Builder(this, CHANNEL_ID)
        .setContentTitle("Active")
        .setContentText("Keeping the session active.")
        .setSmallIcon(icon)
        // ... ongoing, no setContentIntent()
        .build();
}
```

---

## Manifest and permissions

The `stashpay` module declares the service and the required permissions:

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SHORT_SERVICE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<service
    android:name=".keepalive.StashKeepAliveService"
    android:foregroundServiceType="shortService"
    android:exported="false" />
```

- **shortService** is required on Android 14+ for this type of short-lived foreground service and enforces the 3-minute platform limit.
- **POST_NOTIFICATIONS** is needed on API 33+ for the notification to be shown; the host app should request this when using keep-alive (e.g. before starting checkout in CCT).

---

## Summary

| Topic | Detail |
|-------|--------|
| **When it runs** | Only when checkout is opened in Chrome Custom Tabs or the system browser (e.g. when `forceSafariViewController` is enabled in the portrait flow). |
| **What it does** | Runs as a foreground service with a visible notification to reduce the chance the app process is killed while the user is in the browser. |
| **When it stops** | When the app calls `StashKeepAliveManager.stop()`, when the soft timeout elapses, or when the Android 14+ platform timeout fires. |
| **Notification** | Not clickable; it only shows that the session is active. |
