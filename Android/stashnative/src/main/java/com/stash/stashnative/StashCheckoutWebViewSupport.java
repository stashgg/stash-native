package com.stash.stashnative;

import android.os.Build;
import android.util.Log;
import android.view.View;
import android.webkit.WebChromeClient;
import android.webkit.WebView;
import android.widget.FrameLayout;

/** Creates the checkout WebView and starts navigation after its first resolved layout. */
final class StashCheckoutWebViewSupport {
  private static final String TAG = "StashNative";

  private StashCheckoutWebViewSupport() {}

  static void addWebView(StashCardActivity activity) {
    if (activity.url == null || activity.url.isEmpty() || activity.cardContainer == null) {
      Log.e(TAG, "Invalid parameters in addWebView");
      return;
    }

    try {
      activity.webView = new WebView(activity);
      if (activity.contentRevealSupport != null) {
        activity.contentRevealSupport.dispose();
      }
      activity.contentRevealSupport = new StashContentRevealSupport(activity);
    } catch (Throwable t) {
      // Provider initialization failures must not crash the host app.
      Log.e(TAG, "WebView creation failed");
      activity.handleNetworkError();
      return;
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        try {
          activity.webView.setRendererPriorityPolicy(WebView.RENDERER_PRIORITY_IMPORTANT, true);
        } catch (Throwable ignored) {
          // Older providers may not support renderer priority changes.
        }
      }
      try {
        StashWebViewUtils.configureWebViewSettings(activity.webView);
      } catch (Exception e) {
        Log.w(TAG, "Error configuring WebView settings");
      }

      activity.webView.setWebViewClient(new StashCheckoutWebViewClient(activity));

      activity.webView.setWebChromeClient(new WebChromeClient() {
        @Override
        public void onProgressChanged(WebView view, int newProgress) {
          super.onProgressChanged(view, newProgress);
          // Older providers need a progress fallback for commit visibility.
          // The initial value of 10 does not indicate a received response.
          if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q && newProgress > 10) {
            StashCheckoutLoadingSupport.markMainFrameNavigationCommittedIfNeeded(activity);
            StashCheckoutLoadingSupport.maybeRevealWhenReady(activity);
          }
        }

        @Override
        public boolean onCreateWindow(
            WebView view, boolean isDialog, boolean isUserGesture, android.os.Message resultMsg) {
          return StashCheckoutNavigationSupport.openTargetBlankWindow(activity, view, resultMsg);
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
      // Renderer replacements must stay beneath the native controls.
      activity.cardContainer.addView(activity.webView, 0);
      if (activity.presentation != null) {
        activity.presentation.applyWebViewBottomInset();
      }

      // Cover the card before navigation starts to avoid an empty first frame.
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
        urlWithTheme = StashWebViewUtils.appendThemeQueryParameter(
            activity.url, activity.effectiveIsDarkForContent);
      } catch (Exception e) {
        Log.w(TAG, "Error appending theme parameter");
        urlWithTheme = activity.url;
      }
      activity.webViewCommittedReloadUrl = urlWithTheme;
      activity.issueBridgeDocumentToken();
      activity.webViewRetryCount = 0;
      activity.supersededInitialLoadUrl = null;
      activity.pageLoadStartTime = 0;
      activity.pageLoadedCallbackSent = false;
      activity.mainFrameNavigationCommitted = false;
      loadWhenLaidOut(activity, urlWithTheme);
    } catch (Exception e) {
      Log.w(TAG, "Error setting up WebView");
      activity.finish();
    }
  }

  private static void loadWhenLaidOut(StashCardActivity activity, String url) {
    final WebView webView = activity.webView;
    // Older providers lock the initial viewport scale to the first measured size.
    final class InitialPage implements View.OnLayoutChangeListener, Runnable {
      private boolean started;

      @Override
      public void run() {
        if (started) {
          return;
        }
        if (activity.webView != webView || activity.isDismissing || activity.isDestroyed()) {
          webView.removeOnLayoutChangeListener(this);
          return;
        }
        if (activity.presentation == null
            || !activity.presentation.contentHasResolvedSize(webView)) {
          return;
        }
        started = true;
        webView.removeOnLayoutChangeListener(this);
        webView.loadUrl(url);
        StashCheckoutLoadingSupport.scheduleInitialLoadTimers(activity);
      }

      @Override
      public void onLayoutChange(View view, int l, int t, int r, int b,
          int oldL, int oldT, int oldR, int oldB) {
        run();
      }
    }

    InitialPage initialPage = new InitialPage();
    webView.addOnLayoutChangeListener(initialPage);
    webView.post(initialPage);
  }

  /** Evaluates the bridge script in the main frame, bound to the current document token. */
  static void injectSDK(StashCardActivity activity, WebView view) {
    StashWebInteractionSupport.apply(view);
    String token = activity.bridgeDocumentToken;
    if (token == null) {
      token = activity.issueBridgeDocumentToken();
    }
    view.evaluateJavascript(StashWebViewUtils.bridgeScript(token), null);
  }

  static void checkProvider(StashCardActivity activity, String url) {
    if (activity.homeButton == null || url == null) {
      return;
    }
    String lower = url.toLowerCase(java.util.Locale.ROOT);
    boolean show = lower.contains("klarna") || lower.contains("paypal") || lower.contains("stripe");
    activity.runOnUiThread(() ->
        activity.homeButton.setVisibility(show ? View.VISIBLE : View.GONE));
  }
}
