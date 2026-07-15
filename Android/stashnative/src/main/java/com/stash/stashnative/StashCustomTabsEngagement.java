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
 * EngagementSignalsCallback} when Chrome exposes it, and {@link CustomTabsCallback} {@code
 * NAVIGATION_ABORTED} as a fallback when {@code onActivityResult} is delayed (e.g. floating tab).
 */
final class StashCustomTabsEngagement {

  private static final String TAG = "StashCustomTabsEngagement";
  /** Slow devices / OEM Chrome can connect late; short timeouts caused session-less fallback. */
  private static final long BIND_TIMEOUT_MS = 2500L;
  private static final long NAV_ABORT_NOTIFY_DELAY_MS = 400L;

  private static final Object LOCK = new Object();
  private static CustomTabsServiceConnection activeConnection;
  private static Context bindContext;

  private StashCustomTabsEngagement() {}

  /**
   * Binds the Custom Tabs service, registers engagement signals, and launches the tab with
   * {@link Activity#startActivityForResult}.
   *
   * @return true if bind was started (launch mode is delivered asynchronously); false to use the
   *     synchronous {@link StashUrlLauncher#openExternalUrl} path immediately
   */
  static boolean tryLaunchForResult(
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
            launchCallback.onLaunchMode(
                StashUrlLauncher.openExternalUrl(activity, uri.toString(), requestCode));
          };
      conn.setTimeoutRunnable(timeout);
      main.postDelayed(timeout, BIND_TIMEOUT_MS);
      return true;
    }
  }

  static void unbindIfBound(Context context) {
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
      try {
        bindContext.unbindService(activeConnection);
      } catch (Throwable t) {
        Log.w(TAG, "unbind failed: " + t.getMessage());
      }
    }
    activeConnection = null;
    bindContext = null;
  }

  /**
   * Chrome does not always deliver {@link EngagementSignalsCallback#onSessionEnded} (e.g. some OEM
   * builds). {@link CustomTabsCallback#onNavigationEvent} can still report {@code
   * NAVIGATION_ABORTED} after a successful load when the user dismisses the tab, including from
   * floating UI.
   */
  private static CustomTabsCallback newSessionNavigationCallback(
      Activity activity, Runnable engagementSessionEnded, Handler main) {
    WeakReference<Activity> actRef = new WeakReference<>(activity);
    final Runnable notify =
        () -> {
          Activity a = actRef.get();
          if (a == null || a.isFinishing()) {
            return;
          }
          try {
            engagementSessionEnded.run();
          } catch (Throwable t) {
            Log.w(TAG, "navigation abort notify: " + t.getMessage());
          }
          unbindIfBound(a.getApplicationContext());
        };
    return new CustomTabsCallback() {
      private boolean sawNavigationStarted;
      private boolean sawNavigationFinished;

      @Override
      public void onNavigationEvent(int navigationEvent, Bundle extras) {
        switch (navigationEvent) {
          case NAVIGATION_STARTED:
            sawNavigationStarted = true;
            // A real navigation supersedes any pending abort-notify (e.g. JS/3DS redirect).
            main.removeCallbacks(notify);
            return;
          case NAVIGATION_FINISHED:
            sawNavigationFinished = true;
            main.removeCallbacks(notify);
            return;
          case NAVIGATION_ABORTED:
            if (!sawNavigationStarted && !sawNavigationFinished) {
              return;
            }
            main.removeCallbacks(notify);
            long delay =
                sawNavigationFinished
                    ? NAV_ABORT_NOTIFY_DELAY_MS
                    : NAV_ABORT_NOTIFY_DELAY_MS + 400L;
            main.postDelayed(notify, delay);
            return;
          default:
        }
      }
    };
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

    @Override
    public void onCustomTabsServiceConnected(ComponentName name, CustomTabsClient client) {
      if (timeoutRunnable != null) {
        main.removeCallbacks(timeoutRunnable);
        timeoutRunnable = null;
      }
      if (superseded) {
        return;
      }
      Activity activity = activityRef.get();
      if (activity == null || activity.isFinishing()) {
        synchronized (LOCK) {
          if (activeConnection == this) {
            unbindIfBoundLocked(bindContext);
          }
        }
        return;
      }
      try {
        CustomTabsCallback navCallback =
            newSessionNavigationCallback(activity, engagementSessionEnded, main);
        CustomTabsSession session = client.newSession(navCallback);
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
                          try {
                            engagementSessionEnded.run();
                          } catch (Throwable t) {
                            Log.w(TAG, "engagementSessionEnded: " + t.getMessage());
                          }
                          unbindIfBound(activity.getApplicationContext());
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
        activity.startActivityForResult(intent, requestCode);
      } catch (Throwable t) {
        Log.w(TAG, "Engagement launch failed: " + t.getMessage());
        unbindIfBound(activity.getApplicationContext());
        launchCallback.onLaunchMode(
            StashUrlLauncher.openExternalUrl(activity, uri.toString(), requestCode));
      }
    }

    @Override
    public void onServiceDisconnected(ComponentName name) {
      synchronized (LOCK) {
        if (activeConnection == this) {
          activeConnection = null;
          bindContext = null;
        }
      }
    }
  }
}
