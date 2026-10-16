package com.stash.stashnative;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import androidx.browser.customtabs.CustomTabColorSchemeParams;
import androidx.browser.customtabs.CustomTabsCallback;
import androidx.browser.customtabs.CustomTabsClient;
import androidx.browser.customtabs.CustomTabsIntent;
import androidx.browser.customtabs.CustomTabsServiceConnection;
import androidx.browser.customtabs.CustomTabsSession;
import androidx.browser.customtabs.EngagementSignalsCallback;
import java.lang.ref.WeakReference;

/**
 * Binds Custom Tabs, attaches a {@link CustomTabsSession} (so navigation / engagement callbacks
 * work), and launches with {@link Activity#startActivityForResult}. Uses {@link
 * EngagementSignalsCallback} when Chrome exposes it; the proxy owns activity-result and resume
 * fallback handling. Navigation cancellation does not establish that a tab has closed.
 */
public final class StashCustomTabsEngagement {

  private static final String TAG = "StashCustomTabs";
  /** Slow devices / OEM Chrome can connect late; short timeouts caused session-less fallback. */
  private static final long BIND_TIMEOUT_MS = 2500L;

  private static final Object LOCK = new Object();
  private static EngagementConnection activeConnection;
  private static Context bindContext;

  private StashCustomTabsEngagement() {}

  /**
   * Binds the Custom Tabs service, registers engagement signals, and launches the tab with
   * {@link Activity#startActivityForResult}.
   *
   * @return true if bind was started (launch mode is delivered asynchronously); false to use the
   *     synchronous {@link StashUrlLauncher#openExternalUrl} path immediately
   */
  public static boolean tryLaunchForResult(
      Activity activity,
      Uri uri,
      int requestCode,
      StashUrlLauncher.LaunchModeCallback launchCallback,
      Runnable engagementSessionEnded) {
    if (activity == null || uri == null || launchCallback == null) {
      return false;
    }
    Runnable ended = engagementSessionEnded != null ? engagementSessionEnded : () -> {};
    Context appCtx = activity.getApplicationContext();
    String pkg = CustomTabsClient.getPackageName(activity, null);
    if (pkg == null) {
      return false;
    }

    Handler main = new Handler(Looper.getMainLooper());
    synchronized (LOCK) {
      unbindIfBoundLocked(appCtx);
      EngagementConnection conn =
          new EngagementConnection(
              activity, uri, requestCode, launchCallback, ended, main);
      activeConnection = conn;
      bindContext = appCtx;
      boolean bound = CustomTabsClient.bindCustomTabsService(appCtx, pkg, conn);
      if (!bound) {
        activeConnection = null;
        bindContext = null;
        return false;
      }
      Runnable timeout =
          () -> {
            synchronized (LOCK) {
              if (activeConnection != conn) {
                return;
              }
              conn.superseded = true;
              Log.w(TAG, "Custom Tabs bind timeout; falling back");
              unbindIfBoundLocked(appCtx);
            }
            if (activity.isFinishing() || activity.isDestroyed()) {
              return;
            }
            launchCallback.onLaunchMode(
                StashUrlLauncher.openExternalUrl(activity, uri.toString(), requestCode));
          };
      conn.setTimeoutRunnable(timeout);
      main.postDelayed(timeout, BIND_TIMEOUT_MS);
      return true;
    }
  }

  /** Releases the active optional Custom Tabs service binding. */
  public static void unbindIfBound(Context context) {
    if (context == null) {
      return;
    }
    Context app = context.getApplicationContext();
    synchronized (LOCK) {
      unbindIfBoundLocked(app);
    }
  }

  private static void unbindIfBoundLocked(Context appCtx) {
    if (activeConnection != null && bindContext != null) {
      activeConnection.cancel();
      try {
        bindContext.unbindService(activeConnection);
      } catch (Throwable t) {
        Log.w(TAG, "unbind failed: " + t.getMessage());
      }
    }
    activeConnection = null;
    bindContext = null;
  }

  private static CustomTabsIntent buildStyledIntent(CustomTabsSession session) {
    CustomTabColorSchemeParams darkParams =
        new CustomTabColorSchemeParams.Builder()
            .setToolbarColor(Color.parseColor(CardConstants.COLOR_DARK_BG))
            .build();
    return new CustomTabsIntent.Builder(session)
        .setShowTitle(true)
        .setDefaultColorSchemeParams(darkParams)
        .build();
  }

  private static final class EngagementConnection extends CustomTabsServiceConnection {
    private final WeakReference<Activity> activityRef;
    private final Uri uri;
    private final int requestCode;
    private final StashUrlLauncher.LaunchModeCallback launchCallback;
    private final Runnable engagementSessionEnded;
    private final Handler main;
    private Runnable timeoutRunnable;
    volatile boolean superseded;

    EngagementConnection(
        Activity activity,
        Uri uri,
        int requestCode,
        StashUrlLauncher.LaunchModeCallback launchCallback,
        Runnable engagementSessionEnded,
        Handler main) {
      this.activityRef = new WeakReference<>(activity);
      this.uri = uri;
      this.requestCode = requestCode;
      this.launchCallback = launchCallback;
      this.engagementSessionEnded = engagementSessionEnded;
      this.main = main;
    }

    void setTimeoutRunnable(Runnable timeoutRunnable) {
      this.timeoutRunnable = timeoutRunnable;
    }

    private boolean isActive() {
      synchronized (LOCK) {
        return !superseded && activeConnection == this;
      }
    }

    private void cancel() {
      superseded = true;
      if (timeoutRunnable != null) {
        main.removeCallbacks(timeoutRunnable);
        timeoutRunnable = null;
      }
    }

    private void releaseConnection() {
      synchronized (LOCK) {
        if (activeConnection == this) {
          unbindIfBoundLocked(bindContext);
        }
      }
    }

    @Override
    public void onCustomTabsServiceConnected(ComponentName name, CustomTabsClient client) {
      if (timeoutRunnable != null) {
        main.removeCallbacks(timeoutRunnable);
        timeoutRunnable = null;
      }
      if (!isActive()) {
        return;
      }
      Activity activity = activityRef.get();
      if (activity == null || activity.isFinishing() || activity.isDestroyed()) {
        releaseConnection();
        return;
      }
      try {
        CustomTabsSession session = client.newSession(new CustomTabsCallback());
        Bundle extras = Bundle.EMPTY;
        boolean engagementAvail = false;
        try {
          engagementAvail = session.isEngagementSignalsApiAvailable(extras);
        } catch (Throwable t) {
          Log.w(TAG, "isEngagementSignalsApiAvailable: " + t.getMessage());
        }
        if (engagementAvail) {
          try {
            session.setEngagementSignalsCallback(
                main::post,
                new EngagementSignalsCallback() {
                  @Override
                  public void onSessionEnded(boolean didInteract, Bundle bundle) {
                    main.post(
                        () -> {
                          if (!isActive()) {
                            return;
                          }
                          releaseConnection();
                          try {
                            engagementSessionEnded.run();
                          } catch (Throwable t) {
                            Log.w(TAG, "engagementSessionEnded: " + t.getMessage());
                          }
                        });
                  }
                },
                extras);
          } catch (Throwable t) {
            Log.w(TAG, "setEngagementSignalsCallback failed: " + t.getMessage());
          }
        }
        CustomTabsIntent cti = buildStyledIntent(session);
        Intent intent = new Intent(cti.intent);
        intent.setData(uri);
        launchCallback.onLaunchMode(StashUrlLauncher.OPEN_EXTERNAL_CCT_ACTIVITY_FOR_RESULT);
        if (!isActive() || activity.isFinishing() || activity.isDestroyed()) {
          return;
        }
        activity.startActivityForResult(intent, requestCode);
      } catch (Throwable t) {
        Log.w(TAG, "Engagement launch failed: " + t.getMessage());
        if (!isActive()) {
          return;
        }
        releaseConnection();
        launchCallback.onLaunchMode(
            StashUrlLauncher.openExternalUrl(activity, uri.toString(), requestCode));
      }
    }

    @Override
    public void onServiceDisconnected(ComponentName name) {
      synchronized (LOCK) {
        if (activeConnection == this) {
          cancel();
          activeConnection = null;
          bindContext = null;
        }
      }
    }
  }
}
