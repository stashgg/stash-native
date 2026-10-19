package com.stash.stashnative;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.AnimatorSet;
import android.animation.ObjectAnimator;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.WebSettings;

/** Owns loading timers and the initial content crossfade; state stays with the activity. */
final class StashCheckoutLoadingSupport {
  private static final String TAG = "StashNative";

  private StashCheckoutLoadingSupport() {}

  static void scheduleInitialLoadTimers(StashCardActivity activity) {
    if (activity.loadTimersHandler == null) {
      activity.loadTimersHandler = new android.os.Handler(android.os.Looper.getMainLooper());
    }
    cancelLoadTimers(activity);
    activity.retryAfterStallRunnable = () -> {
      if (activity.networkErrorHandled || activity.isDismissing || activity.webView == null) {
        return;
      }
      if (activity.mainFrameNavigationCommitted || activity.isPurchaseProcessing) {
        return;
      }
      if (activity.webViewRetryCount >= 1) {
        return;
      }
      activity.webViewRetryCount = 1;
      // A cancelled crossfade must not remove the retry's loading overlay.
      cancelLoadingRevealAnimation(activity);
      activity.webViewLoadingRevealComplete = false;
      activity.webView.setAlpha(0f);
      showLoading(activity);
      Log.w(TAG, "StashNative: no HTTP response in "
          + (CardConstants.WEBVIEW_RETRY_TIMEOUT_MS / 1000.0)
          + "s — retrying checkout");
      int prevMode = activity.webView.getSettings().getCacheMode();
      try {
        activity.webView.getSettings().setCacheMode(WebSettings.LOAD_NO_CACHE);
        activity.webView.loadUrl(appendCacheBuster(activity.webViewCommittedReloadUrl));
      } finally {
        activity.webView.getSettings().setCacheMode(prevMode);
      }
    };
    activity.networkDeadlineRunnable = () -> {
      if (activity.networkErrorHandled || activity.isDismissing) {
        return;
      }
      if (activity.mainFrameNavigationCommitted) {
        return;
      }
      Log.e(TAG, "StashNative: TIMEOUT "
          + (CardConstants.WEBVIEW_NETWORK_DEADLINE_MS / 1000)
          + "s — main frame did not commit after "
          + (activity.webViewRetryCount + 1)
          + " attempt(s)");
      activity.handleNetworkError();
    };
    // Pause/resume preserves the original deadline.
    long now = android.os.SystemClock.uptimeMillis();
    if (activity.networkDeadlineTargetUptime == 0L) {
      activity.networkDeadlineTargetUptime = now + CardConstants.WEBVIEW_NETWORK_DEADLINE_MS;
    }
    long remaining = Math.max(0L, activity.networkDeadlineTargetUptime - now);
    activity.loadTimersHandler.postDelayed(
        activity.retryAfterStallRunnable, CardConstants.WEBVIEW_RETRY_TIMEOUT_MS);
    activity.loadTimersHandler.postDelayed(activity.networkDeadlineRunnable, remaining);
  }

  static void markMainFrameNavigationCommittedIfNeeded(StashCardActivity activity) {
    if (activity.mainFrameNavigationCommitted || activity.networkErrorHandled) {
      return;
    }
    activity.mainFrameNavigationCommitted = true;
    cancelLoadTimers(activity);
  }

  /** Waits for document completion and a committed frame before revealing content. */
  static void maybeRevealWhenReady(StashCardActivity activity) {
    if (activity.networkErrorHandled || activity.mainFrameErrorReceived || activity.isDismissing) {
      return;
    }
    if (!activity.initialPageLoadComplete || !activity.mainFrameNavigationCommitted) {
      return;
    }
    if (activity.contentRevealSupport != null) {
      activity.contentRevealSupport.check();
    }
  }

  static String appendCacheBuster(String url) {
    if (url == null || url.isEmpty()) {
      return url;
    }
    String sep = url.contains("?") ? "&" : "?";
    return url + sep + "_stash_nc=" + System.currentTimeMillis();
  }

  static void cancelLoadTimers(StashCardActivity activity) {
    if (activity.loadTimersHandler == null) {
      return;
    }
    if (activity.retryAfterStallRunnable != null) {
      activity.loadTimersHandler.removeCallbacks(activity.retryAfterStallRunnable);
    }
    if (activity.networkDeadlineRunnable != null) {
      activity.loadTimersHandler.removeCallbacks(activity.networkDeadlineRunnable);
    }
  }

  /**
   * Stops the loading/WebView crossfade and resets alpha so a new load can show the spinner until
   * {@link #revealWebViewAndRemoveLoading} runs again.
   */
  static void cancelLoadingRevealAnimation(StashCardActivity activity) {
    // Clear this before cancel() so any onAnimationEnd from the crossfade treats this as cancelled.
    activity.webViewRevealAnimationRunning = false;
    activity.webViewRevealAnimationToken++;
    if (activity.webViewRevealAnimator != null) {
      activity.webViewRevealAnimator.cancel();
      activity.webViewRevealAnimator = null;
    }
    if (activity.loadingView != null) {
      activity.loadingView.animate().cancel();
      activity.loadingView.setAlpha(1f);
    }
    if (activity.webView != null) {
      activity.webView.animate().cancel();
      activity.webView.setAlpha(0f);
    }
  }

  static void showLoading(StashCardActivity activity) {
    activity.runOnUiThread(() -> {
      if (activity.webViewLoadingRevealComplete || activity.webViewRevealAnimationRunning) {
        return;
      }
      if (activity.webView != null) {
        activity.webView.setAlpha(0f);
      }
      // Reuse the overlay to avoid a flash between navigation callbacks.
      if (activity.loadingView != null && activity.loadingView.getParent() != null) {
        activity.loadingView.setAlpha(1f);
        activity.loadingView.setVisibility(View.VISIBLE);
        activity.loadingView.bringToFront();
        return;
      }

      if (activity.cardContainer != null) {
        activity.loadingView = StashWebViewUtils.createAndShowLoadingView(
            activity.getApplicationContext(), activity.cardContainer,
            activity.sheetChromeBackgroundArgb,
            StashBackgroundColorUtils.spinnerAccentFor(activity.sheetChromeBackgroundArgb));
        if (activity.loadingView != null) {
          activity.loadingView.setAlpha(1f);
          activity.loadingView.setVisibility(View.VISIBLE);
        }
      }
    });
  }

  static void emitPageLoadedIfNeeded(StashCardActivity activity) {
    if (activity.pageLoadedCallbackSent || activity.pageLoadStartTime <= 0) {
      return;
    }
    activity.pageLoadedCallbackSent = true;
    long loadTimeMs = System.currentTimeMillis() - activity.pageLoadStartTime;
    activity.pageLoadStartTime = 0;
    StashCheckoutBridge.emitPageLoaded(activity, loadTimeMs);
    try {
      android.webkit.CookieManager.getInstance().flush();
    } catch (Throwable ignored) {
      // Cookie persistence is best effort; loading has already completed.
    }
  }

  /**
   * First load: crossfade loading overlay out and WebView in (aligned with iOS
   * {@code showWebViewAndRemoveLoading}). Later navigations: no-op if overlay already gone.
   */
  static void revealWebViewAndRemoveLoading(StashCardActivity activity) {
    activity.runOnUiThread(() -> {
      if (activity.webView == null || activity.isDismissing
          || activity.webViewRevealAnimationRunning) {
        return;
      }
      if (activity.webViewLoadingRevealComplete) {
        removeLoadingViewFromParent(activity);
        return;
      }
      if (activity.loadingView != null) {
        activity.webViewRevealAnimationRunning = true;
        final int revealToken = ++activity.webViewRevealAnimationToken;
        activity.loadingView.animate().cancel();
        activity.webView.animate().cancel();
        activity.loadingView.setAlpha(1f);
        activity.webView.setAlpha(0f);
        AnimatorSet crossfade = new AnimatorSet();
        activity.webViewRevealAnimator = crossfade;
        crossfade.playTogether(
            ObjectAnimator.ofFloat(activity.webView, View.ALPHA, 0f, 1f),
            ObjectAnimator.ofFloat(activity.loadingView, View.ALPHA, 1f, 0f));
        crossfade.setDuration(CardConstants.LOADING_REVEAL_DURATION_MS);
        crossfade.setInterpolator(
            new android.view.animation.AccelerateDecelerateInterpolator());
        crossfade.addListener(new AnimatorListenerAdapter() {
          @Override
          public void onAnimationEnd(Animator animation) {
            // An older crossfade cannot complete a newer load.
            if (!activity.webViewRevealAnimationRunning
                || revealToken != activity.webViewRevealAnimationToken) {
              return;
            }
            activity.webViewRevealAnimationRunning = false;
            activity.webViewRevealAnimator = null;
            activity.webViewLoadingRevealComplete = true;
            removeLoadingViewFromParent(activity);
            emitPageLoadedIfNeeded(activity);
          }
        });
        crossfade.start();
      } else {
        activity.webViewLoadingRevealComplete = true;
        activity.webView.setAlpha(1f);
        emitPageLoadedIfNeeded(activity);
      }
    });
  }

  static void removeLoadingViewFromParent(StashCardActivity activity) {
    if (activity.loadingView != null && activity.loadingView.getParent() != null) {
      ((ViewGroup) activity.loadingView.getParent()).removeView(activity.loadingView);
    }
    activity.loadingView = null;
  }
}
