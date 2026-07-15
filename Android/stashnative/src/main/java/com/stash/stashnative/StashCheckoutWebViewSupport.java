package com.stash.stashnative;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.AnimatorSet;
import android.animation.ObjectAnimator;
import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import androidx.annotation.RequiresApi;

/**
 * Checkout WebView lifecycle for {@link StashNativeCardPortraitActivity}: creation and clients,
 * stall-retry and network-deadline timers, provider / Google Pay redirect checks, and the
 * loading-overlay / reveal crossfade. State lives on the activity (mirrors iOS
 * WebViewLoadDelegate timing).
 */
final class StashCheckoutWebViewSupport {
  private static final String TAG = "StashNativeCard";

  private StashCheckoutWebViewSupport() {}

  static void addWebView(StashNativeCardPortraitActivity activity) {
    if (activity.url == null || activity.url.isEmpty() || activity.cardContainer == null) {
      Log.e(TAG, "Invalid parameters in addWebView");
      return;
    }

    try {
      try {
        activity.webView = new WebView(activity);
      } catch (Throwable t) {
        // WebView creation can fail if running in a separate process (data directory lock),
        // on devices with broken WebView installs, or when Chromium init fails. Report as
        // network error and bail -- do not crash the host app.
        Log.e(TAG, "WebView creation failed: " + t.getMessage(), t);
        activity.handleNetworkError();
        return;
      }
      try {
        StashWebViewUtils.configureWebViewSettings(activity.webView, activity.effectiveIsDarkForContent);
      } catch (Exception e) {
        Log.w(TAG, "Error configuring WebView settings: " + e.getMessage(), e);
      }

      activity.webView.setWebViewClient(new WebViewClient() {
        @Override
        public boolean shouldOverrideUrlLoading(WebView view, android.webkit.WebResourceRequest request) {
          if (!request.isForMainFrame()) {
            return false;
          }
          return handleDeeplinkNavigation(
              activity, request.getUrl() != null ? request.getUrl().toString() : null);
        }

        @Override
        @SuppressWarnings("deprecation")
        public boolean shouldOverrideUrlLoading(WebView view, String url) {
          return handleDeeplinkNavigation(activity, url);
        }

        @Override
        public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
          try {
            super.onPageStarted(view, url, favicon);
            activity.pageLoadStartTime = System.currentTimeMillis();
            showLoading(activity);
            injectSDK(view);
            checkProvider(activity, url);
            checkGooglePayRedirect(activity, url);
          } catch (Exception e) {
            Log.w(TAG, "Error in onPageStarted: " + e.getMessage(), e);
          }
        }

        @Override
        public void onPageFinished(WebView view, String url) {
          try {
            super.onPageFinished(view, url);

            // Don't mark as complete if network error already handled or main frame error received
            if (activity.networkErrorHandled || activity.mainFrameErrorReceived) {
              return;
            }

            // Mark initial load as complete
            if (!activity.initialPageLoadComplete) {
              activity.initialPageLoadComplete = true;
            }

            maybeRevealWhenReady(activity);
            injectSDK(view);
            checkProvider(activity, url);
            checkGooglePayRedirect(activity, url);
          } catch (Exception e) {
            Log.w(TAG, "Error in onPageFinished: " + e.getMessage(), e);
          }
        }

        @Override
        public void onReceivedError(WebView view, android.webkit.WebResourceRequest request,
            android.webkit.WebResourceError error) {
          try {
            super.onReceivedError(view, request, error);
            if (error != null) {
              Log.e(TAG, "WebView error: " + error.getDescription());
            }

            // Check if this is the main frame and initial load hasn't completed
            if (request != null && request.isForMainFrame() && !activity.initialPageLoadComplete) {
              Log.e(TAG, "Network error on main frame during initial load");
              activity.mainFrameErrorReceived = true;
              activity.handleNetworkError();
            }
          } catch (Exception e) {
            Log.w(TAG, "Error in onReceivedError: " + e.getMessage(), e);
          }
        }

        @Override
        public void onReceivedHttpError(WebView view, android.webkit.WebResourceRequest request,
            android.webkit.WebResourceResponse errorResponse) {
          try {
            super.onReceivedHttpError(view, request, errorResponse);

            // Check if this is the main frame and initial load hasn't completed
            if (request != null && request.isForMainFrame() && !activity.initialPageLoadComplete) {
              int statusCode = errorResponse != null ? errorResponse.getStatusCode() : 0;
              Log.e(TAG, "HTTP error on main frame during initial load: " + statusCode);
              activity.mainFrameErrorReceived = true;
              activity.handleNetworkError();
            }
          } catch (Exception e) {
            Log.w(TAG, "Error in onReceivedHttpError: " + e.getMessage(), e);
          }
        }

        @Override
        @RequiresApi(Build.VERSION_CODES.Q)
        public void onPageCommitVisible(WebView view, String pageUrl) {
          super.onPageCommitVisible(view, pageUrl);
          markMainFrameNavigationCommittedIfNeeded(activity);
          maybeRevealWhenReady(activity);
        }

        @Override
        @RequiresApi(Build.VERSION_CODES.O)
        public boolean onRenderProcessGone(WebView view, RenderProcessGoneDetail detail) {
          Log.e(TAG, "WebView render process gone (didCrash=" + detail.didCrash() + ")");
          try {
            if (view.getParent() != null) {
              ((ViewGroup) view.getParent()).removeView(view);
            }
            view.destroy();
          } catch (Exception e) {
            Log.w(TAG, "Error removing dead WebView: " + e.getMessage(), e);
          }
          activity.webView = null;
          activity.handleNetworkError();
          return true;
        }
        });

      try {
        activity.webView.setWebChromeClient(new WebChromeClient() {
          @Override
          public void onProgressChanged(WebView view, int newProgress) {
            super.onProgressChanged(view, newProgress);
            // Below API 29 there is no onPageCommitVisible; first progress means bytes are arriving.
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q && newProgress > 0) {
              markMainFrameNavigationCommittedIfNeeded(activity);
              maybeRevealWhenReady(activity);
            }
          }
        });
        activity.webView.addJavascriptInterface(
            new StashCheckoutJsInterface(activity), StashWebViewUtils.JS_INTERFACE_NAME);
        activity.webView.setBackgroundColor(activity.sheetChromeBackgroundArgb);

        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
        activity.webView.setLayoutParams(params);
        activity.webViewLoadingRevealComplete = false;
        activity.webViewRevealAnimationRunning = false;
        activity.webView.setAlpha(0f);
        activity.cardContainer.addView(activity.webView);

        // Show loading immediately before loadUrl() so there is never a blank-card window
        // between addView() and the first onPageStarted callback. showLoading() is idempotent:
        // if the overlay already exists it will not remove/recreate it.
        activity.loadingView = StashWebViewUtils.createAndShowLoadingView(
            activity.getApplicationContext(), activity.cardContainer,
            activity.sheetChromeBackgroundArgb,
            StashBackgroundColorUtils.spinnerAccentFor(activity.sheetChromeBackgroundArgb));
        if (activity.loadingView != null) {
          activity.loadingView.setAlpha(1f);
          activity.loadingView.setVisibility(View.VISIBLE);
        }

        String urlWithTheme;
        try {
          urlWithTheme = StashWebViewUtils.appendThemeQueryParameter(activity.url, activity.effectiveIsDarkForContent);
        } catch (Exception e) {
          Log.w(TAG, "Error appending theme parameter: " + e.getMessage(), e);
          urlWithTheme = activity.url;
        }
        activity.webViewCommittedReloadUrl = urlWithTheme;
        activity.webViewRetryCount = 0;
        activity.pageLoadStartTime = 0;
        activity.pageLoadedCallbackSent = false;
        activity.mainFrameNavigationCommitted = false;
        activity.webView.loadUrl(urlWithTheme);
        scheduleInitialLoadTimers(activity);
      } catch (Exception e) {
        Log.w(TAG, "Error setting up WebView: " + e.getMessage(), e);
        activity.finish();
      }
    } catch (Exception e) {
      Log.w(TAG, "Error creating WebView: " + e.getMessage(), e);
      activity.finish();
    }
  }

  static void scheduleInitialLoadTimers(StashNativeCardPortraitActivity activity) {
    if (activity.loadTimersHandler == null) {
      activity.loadTimersHandler = new android.os.Handler(android.os.Looper.getMainLooper());
    }
    cancelLoadTimers(activity);
    activity.retryAfterStallRunnable = () -> {
      if (activity.networkErrorHandled || activity.isDismissing || activity.webView == null) {
        return;
      }
      if (activity.mainFrameNavigationCommitted) {
        return;
      }
      if (activity.webViewRetryCount >= 1) {
        return;
      }
      activity.webViewRetryCount = 1;
      // Cancel any in-flight reveal crossfade; otherwise onAnimationEnd can still remove the
      // loading overlay after we start the retry load.
      cancelLoadingRevealAnimation(activity);
      activity.webViewLoadingRevealComplete = false;
      activity.webView.setAlpha(0f);
      showLoading(activity);
      Log.w(TAG, "StashNative: no HTTP response in "
          + (CardConstants.WEBVIEW_RETRY_TIMEOUT_MS / 1000.0)
          + "s — retrying " + activity.webViewCommittedReloadUrl);
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
    activity.loadTimersHandler.postDelayed(
        activity.retryAfterStallRunnable, CardConstants.WEBVIEW_RETRY_TIMEOUT_MS);
    activity.loadTimersHandler.postDelayed(
        activity.networkDeadlineRunnable, CardConstants.WEBVIEW_NETWORK_DEADLINE_MS);
  }

  static void markMainFrameNavigationCommittedIfNeeded(StashNativeCardPortraitActivity activity) {
    if (activity.mainFrameNavigationCommitted || activity.networkErrorHandled) {
      return;
    }
    activity.mainFrameNavigationCommitted = true;
    cancelLoadTimers(activity);
  }

  /**
   * Reveals WebView only when both conditions are true:
   * - document lifecycle finished (onPageFinished)
   * - first frame committed/visible (onPageCommitVisible or progress fallback)
   * This avoids a dark/blank intermediate frame in some WebView implementations.
   */
  static void maybeRevealWhenReady(StashNativeCardPortraitActivity activity) {
    if (activity.networkErrorHandled || activity.mainFrameErrorReceived || activity.isDismissing) {
      return;
    }
    if (!activity.initialPageLoadComplete || !activity.mainFrameNavigationCommitted) {
      return;
    }
    revealWebViewAndRemoveLoading(activity);
  }

  static String appendCacheBuster(String url) {
    if (url == null || url.isEmpty()) {
      return url;
    }
    String sep = url.contains("?") ? "&" : "?";
    return url + sep + "_stash_nc=" + System.currentTimeMillis();
  }

  static void cancelLoadTimers(StashNativeCardPortraitActivity activity) {
    if (activity.loadTimersHandler == null) {
      return;
    }
    activity.loadTimersHandler.removeCallbacks(activity.pendingLandscapeFinishFallback);
    if (activity.retryAfterStallRunnable != null) {
      activity.loadTimersHandler.removeCallbacks(activity.retryAfterStallRunnable);
    }
    if (activity.networkDeadlineRunnable != null) {
      activity.loadTimersHandler.removeCallbacks(activity.networkDeadlineRunnable);
    }
  }

  /**
   * Non-web schemes never load in the card. stash-pay result paths run the standard JS-bridge
   * flows (success/failure/close); any other deeplink is handed to the OS with the card left
   * open. Returns true when the navigation was consumed.
   */
  static boolean handleDeeplinkNavigation(StashNativeCardPortraitActivity activity, String url) {
    if (url == null || StashWebViewUtils.isWebScheme(url)) {
      return false;
    }
    int result = StashWebViewUtils.classifyDeeplinkResult(url);
    StashCheckoutJsInterface bridge = new StashCheckoutJsInterface(activity);
    if (result == StashWebViewUtils.DEEPLINK_RESULT_SUCCESS) {
      bridge.onPaymentSuccess(null);
    } else if (result == StashWebViewUtils.DEEPLINK_RESULT_FAILURE) {
      bridge.onPaymentFailure();
    } else if (result == StashWebViewUtils.DEEPLINK_RESULT_CANCEL) {
      bridge.requestCloseFromPage();
    } else {
      openDeeplinkExternally(activity, url);
    }
    return true;
  }

  /** ACTION_VIEW for a non-stash deeplink; no browser-close tracking, card stays open. */
  static void openDeeplinkExternally(Activity activity, String url) {
    try {
      Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
      activity.startActivity(intent);
    } catch (Throwable t) {
      Log.w(TAG, "No handler for deeplink: " + t.getMessage());
    }
  }

  static void injectSDK(WebView view) {
    view.evaluateJavascript(StashWebViewUtils.JS_SDK_SCRIPT, null);
  }

  static void checkProvider(StashNativeCardPortraitActivity activity, String url) {
    if (activity.homeButton == null || url == null) {
      return;
    }
    String lower = url.toLowerCase();
    boolean show = lower.contains("klarna") || lower.contains("paypal") || lower.contains("stripe");
    activity.runOnUiThread(() -> activity.homeButton.setVisibility(show ? View.VISIBLE : View.GONE));
  }

  static void checkGooglePayRedirect(StashNativeCardPortraitActivity activity, String url) {
    if (url == null || activity.googlePayRedirectHandled || activity.initialURL == null || activity.initialURL.isEmpty()) {
      return;
    }

    String lower = url.toLowerCase();
    if (lower.contains(CardConstants.GOOGLE_PAY_DOMAIN)) {
      activity.googlePayRedirectHandled = true;
      openGooglePayInBrowser(activity, activity.initialURL);
    }
  }

  static void openGooglePayInBrowser(StashNativeCardPortraitActivity activity, String url) {
    try {
      String urlWithParam = url;
      if (url != null && !url.isEmpty()) {
        Uri uri = Uri.parse(url);
        String existingQuery = uri.getQuery();
        if (existingQuery != null && !existingQuery.isEmpty()) {
          urlWithParam = url + CardConstants.GOOGLE_PAY_PARAM_PREFIX_AMP;
        } else {
          urlWithParam = url + CardConstants.GOOGLE_PAY_PARAM_PREFIX_QUERY;
        }
      }

      StashNativeCardPlugin.getInstance()
          .openExternalBrowserFromCheckout(
              activity,
              urlWithParam,
              false,
              activity::hideCardSheetLeavingDimOverlay,
              activity::finishAfterExternalBrowserClose);
    } catch (Exception e) {
      Log.e(TAG, "Failed to open Google Pay URL: " + e.getMessage());
      StashNativeCardPlugin.getInstance().cancelBrowserCloseTrackingLaunch();
      activity.dismissWithAnimation();
    }
  }

  /**
   * Stops the loading/WebView crossfade and resets alpha so a new load can show the spinner until
   * {@link #revealWebViewAndRemoveLoading} runs again.
   */
  static void cancelLoadingRevealAnimation(StashNativeCardPortraitActivity activity) {
    // Clear this before cancel() so any onAnimationEnd from the crossfade treats this as cancelled.
    activity.webViewRevealAnimationRunning = false;
    activity.webViewRevealAnimationToken++;
    if (activity.loadingView != null) {
      activity.loadingView.animate().cancel();
      activity.loadingView.setAlpha(1f);
    }
    if (activity.webView != null) {
      activity.webView.animate().cancel();
      activity.webView.setAlpha(0f);
    }
  }

  static void showLoading(StashNativeCardPortraitActivity activity) {
    activity.runOnUiThread(() -> {
      if (activity.webViewLoadingRevealComplete || activity.webViewRevealAnimationRunning) {
        return;
      }
      if (activity.webView != null) {
        activity.webView.setAlpha(0f);
      }
      // Idempotent: if a loading view is already attached to the container (e.g. created eagerly
      // in addWebView before loadUrl), just ensure it is visible rather than removing+recreating
      // (which would cause the brief "loading flash" the user sees).
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

  static void emitPageLoadedIfNeeded(StashNativeCardPortraitActivity activity) {
    if (activity.pageLoadedCallbackSent || activity.pageLoadStartTime <= 0) {
      return;
    }
    activity.pageLoadedCallbackSent = true;
    long loadTimeMs = System.currentTimeMillis() - activity.pageLoadStartTime;
    activity.pageLoadStartTime = 0;
    StashCheckoutBridge.emitPageLoaded(activity, loadTimeMs);
  }

  /**
   * First load: crossfade loading overlay out and WebView in (aligned with iOS
   * {@code showWebViewAndRemoveLoading}). Later navigations: no-op if overlay already gone.
   */
  static void revealWebViewAndRemoveLoading(StashNativeCardPortraitActivity activity) {
    activity.runOnUiThread(() -> {
      if (activity.webView == null || activity.webViewRevealAnimationRunning) {
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
        crossfade.playTogether(
            ObjectAnimator.ofFloat(activity.webView, View.ALPHA, 0f, 1f),
            ObjectAnimator.ofFloat(activity.loadingView, View.ALPHA, 1f, 0f));
        crossfade.setDuration(CardConstants.LOADING_REVEAL_DURATION_MS);
        crossfade.setInterpolator(
            new android.view.animation.AccelerateDecelerateInterpolator());
        crossfade.addListener(new AnimatorListenerAdapter() {
          @Override
          public void onAnimationEnd(Animator animation) {
            // If cancelLoadingRevealAnimation() ran (e.g. stall retry), running was cleared first;
            // do not strip the overlay or mark the WebView revealed.
            if (!activity.webViewRevealAnimationRunning || revealToken != activity.webViewRevealAnimationToken) {
              return;
            }
            activity.webViewRevealAnimationRunning = false;
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

  static void removeLoadingViewFromParent(StashNativeCardPortraitActivity activity) {
    if (activity.loadingView != null && activity.loadingView.getParent() != null) {
      ((ViewGroup) activity.loadingView.getParent()).removeView(activity.loadingView);
    }
    activity.loadingView = null;
  }
}
