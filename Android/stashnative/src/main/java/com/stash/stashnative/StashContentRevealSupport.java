package com.stash.stashnative;

import android.annotation.SuppressLint;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.webkit.WebView;

/**
 * Keeps the initial cover until the loaded document has committed and painted. There is no page
 * readiness check; a committed document that never reports a paint is revealed after 15 seconds
 * of foreground time.
 */
final class StashContentRevealSupport {
  private static final long WAIT_MS = 15000;
  private static final long POLL_MS = 100;

  private final StashCardActivity activity;
  private final Handler handler = new Handler(Looper.getMainLooper());
  private final Runnable poll = this::check;
  private long elapsed;
  private long foregroundStart = -1;
  private int generation;
  private boolean started;
  private boolean finished;
  private boolean pending;
  private boolean done;
  private boolean disposed;

  StashContentRevealSupport(StashCardActivity activity) {
    this.activity = activity;
  }

  void navigationStarted() {
    if (disposed || activity.webViewLoadingRevealComplete) {
      return;
    }
    generation++;
    pending = false;
    finished = false;
    done = false;
    started = true;
    if (activity.webViewRevealAnimationRunning) {
      StashCheckoutLoadingSupport.cancelLoadingRevealAnimation(activity);
    }
    check();
  }

  void documentFinished() {
    finished = true;
    check();
  }

  void check() {
    handler.removeCallbacks(poll);
    if (!active() || !started || activity.isActivityPaused) {
      return;
    }
    long now = SystemClock.uptimeMillis();
    if (foregroundStart < 0) {
      foregroundStart = now;
    }
    if (elapsed + now - foregroundStart >= WAIT_MS && activity.mainFrameNavigationCommitted) {
      reveal();
      return;
    }
    handler.postDelayed(poll, POLL_MS);
    if (pending || !finished || !activity.mainFrameNavigationCommitted) {
      return;
    }
    pending = true;
    afterPaint(activity.webView, generation);
  }

  private boolean active() {
    return !disposed && !done && !activity.isDismissing && !activity.networkErrorHandled
        && !activity.mainFrameErrorReceived && activity.webView != null
        && !activity.webViewLoadingRevealComplete;
  }

  private boolean current(WebView web, int token) {
    return active() && !activity.isActivityPaused && web == activity.webView && token == generation;
  }

  // Keep the older-provider fallback usable by AAR-only hosts without AndroidX WebKit.
  @SuppressLint("WebViewApiAvailability")
  private void afterPaint(WebView web, int token) {
    Runnable revealIfCurrent = () -> {
      if (current(web, token)) {
        reveal();
      }
    };
    if (Build.VERSION.SDK_INT >= 23) {
      try {
        web.postVisualStateCallback(token, new WebView.VisualStateCallback() {
          @Override
          public void onComplete(long requestId) {
            revealIfCurrent.run();
          }
        });
        return;
      } catch (RuntimeException ignored) {
        // Older providers may not implement the platform's paint callback.
      }
    }
    handler.postDelayed(revealIfCurrent, 50);
  }

  private void reveal() {
    done = true;
    generation++;
    pending = false;
    handler.removeCallbacks(poll);
    StashCheckoutLoadingSupport.revealWebViewAndRemoveLoading(activity);
  }

  void pause() {
    if (foregroundStart >= 0) {
      elapsed += SystemClock.uptimeMillis() - foregroundStart;
      foregroundStart = -1;
    }
    generation++;
    pending = false;
    handler.removeCallbacks(poll);
  }

  void dispose() {
    disposed = true;
    generation++;
    handler.removeCallbacksAndMessages(null);
  }
}
