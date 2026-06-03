package com.stash.stashnative;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;
import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import androidx.core.app.NotificationCompat;

/**
 * Foreground service that raises process priority while an external browser or Chrome Custom Tabs
 * session is open. Enabled via {@link StashNativeCard#setKeepAliveEnabled(boolean)}.
 */
public class StashKeepAliveService extends Service {

  private static final String TAG = "StashKeepAlive";

  /** Notification channel id (low importance). */
  public static final String CHANNEL_ID = "stash_keep_alive";

  private static final int NOTIFICATION_ID = 0x73746173;

  public static final String EXTRA_TITLE = "com.stash.stashnative.keepalive.TITLE";
  public static final String EXTRA_TEXT = "com.stash.stashnative.keepalive.TEXT";
  public static final String EXTRA_ICON_RES_ID = "com.stash.stashnative.keepalive.ICON_RES_ID";

  /**
   * Starts the foreground keep-alive service. Runs in the app's default process. Accepts any app
   * context.
   */
  public static void start(
      Context appContext,
      String notificationTitle,
      String notificationText,
      int notificationIconResId) {
    if (appContext == null) {
      return;
    }
    Context app = appContext.getApplicationContext();
    Intent i = new Intent(app, StashKeepAliveService.class);
    i.putExtra(EXTRA_TITLE, notificationTitle);
    i.putExtra(EXTRA_TEXT, notificationText);
    i.putExtra(EXTRA_ICON_RES_ID, notificationIconResId);
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        app.startForegroundService(i);
      } else {
        app.startService(i);
      }
    } catch (Exception e) {
      Log.w(TAG, "Failed to start keep-alive service: " + e.getMessage(), e);
    }
  }

  /** Stops the keep-alive service if running. */
  public static void stop(Context context) {
    if (context == null) {
      return;
    }
    try {
      context.getApplicationContext()
          .stopService(new Intent(context.getApplicationContext(), StashKeepAliveService.class));
    } catch (Exception e) {
      Log.w(TAG, "Failed to stop keep-alive service: " + e.getMessage(), e);
    }
  }

  @Override
  public void onCreate() {
    super.onCreate();
    createChannelIfNeeded();
  }

  @Nullable
  @Override
  public IBinder onBind(Intent intent) {
    return null;
  }

  @Override
  public int onStartCommand(Intent intent, int flags, int startId) {
    String title =
        intent != null && intent.hasExtra(EXTRA_TITLE)
            ? intent.getStringExtra(EXTRA_TITLE)
            : getString(R.string.stash_keep_alive_title);
    String text =
        intent != null && intent.hasExtra(EXTRA_TEXT)
            ? intent.getStringExtra(EXTRA_TEXT)
            : getString(R.string.stash_keep_alive_text);
    if (title == null || title.isEmpty()) {
      title = getString(R.string.stash_keep_alive_title);
    }
    if (text == null || text.isEmpty()) {
      text = getString(R.string.stash_keep_alive_text);
    }
    int iconResId = 0;
    if (intent != null) {
      iconResId = intent.getIntExtra(EXTRA_ICON_RES_ID, 0);
    }
    if (iconResId == 0) {
      iconResId = R.drawable.ic_stash_keep_alive;
    }

    PendingIntent tap =
        buildLaunchAppPendingIntent();
    Notification notification =
        new NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(iconResId)
            .setContentIntent(tap)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .build();

    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        startForeground(
            NOTIFICATION_ID,
            notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE);
      } else {
        startForeground(NOTIFICATION_ID, notification);
      }
    } catch (Exception e) {
      Log.e(TAG, "startForeground failed: " + e.getMessage(), e);
      stopSelf(startId);
      return START_NOT_STICKY;
    }
    return START_NOT_STICKY;
  }

  /**
   * Android 14 (API 34) short-service timeout callback (~3 minutes). Calls stopSelf, which drives
   * onDestroy and removes the foreground notification.
   */
  @RequiresApi(api = Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
  @Override
  public void onTimeout(int startId) {
    Log.w(TAG, "Keep-alive short service timed out; stopping to avoid a host crash.");
    stopSelf(startId);
  }

  @Override
  public void onDestroy() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      stopForeground(STOP_FOREGROUND_REMOVE);
    } else {
      stopForeground(true);
    }
    super.onDestroy();
  }

  private void createChannelIfNeeded() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      return;
    }
    NotificationManager nm = getSystemService(NotificationManager.class);
    if (nm == null) {
      return;
    }
    NotificationChannel ch =
        new NotificationChannel(
            CHANNEL_ID,
            getString(R.string.stash_keep_alive_channel_name),
            NotificationManager.IMPORTANCE_LOW);
    ch.setDescription(getString(R.string.stash_keep_alive_channel_desc));
    ch.setShowBadge(false);
    nm.createNotificationChannel(ch);
  }

  private PendingIntent buildLaunchAppPendingIntent() {
    PackageManager pm = getPackageManager();
    Intent launch = pm.getLaunchIntentForPackage(getPackageName());
    if (launch == null) {
      launch = new Intent();
    }
    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
    int flags = PendingIntent.FLAG_UPDATE_CURRENT;
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      flags |= PendingIntent.FLAG_IMMUTABLE;
    }
    return PendingIntent.getActivity(this, 0, launch, flags);
  }
}
