package com.stash.stashnative;

import android.os.Build;
import android.util.Log;
import android.view.ViewGroup;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import androidx.annotation.RequiresApi;

/** Translates WebView navigation and renderer events into checkout lifecycle updates. */
final class StashCheckoutWebViewClient extends WebViewClient {
  private static final String TAG = "StashNative";
  private final StashCardActivity activity;

  StashCheckoutWebViewClient(StashCardActivity activity) {
    this.activity = activity;
  }

  @Override
  public boolean shouldOverrideUrlLoading(WebView view, android.webkit.WebResourceRequest request) {
    String target = request.getUrl() != null ? request.getUrl().toString() : null;
    // Web subframes load in place; their deeplinks still need an external handler.
    if (!request.isForMainFrame() && StashWebViewUtils.isWebScheme(target)) {
      return false;
    }
    return StashCheckoutNavigationSupport.handleDeeplinkNavigation(activity, target);
  }

  @Override
  @SuppressWarnings("deprecation")
  public boolean shouldOverrideUrlLoading(WebView view, String url) {
    return StashCheckoutNavigationSupport.handleDeeplinkNavigation(activity, url);
  }

  @Override
  public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
    try {
      super.onPageStarted(view, url, favicon);
      if (view == activity.webView) {
        // The retry has started, so the first attempt can no longer report events.
        activity.supersededInitialLoadUrl = null;
        // A new main-frame document gets a new bridge token; earlier wrappers stop working.
        activity.issueBridgeDocumentToken();
        if (activity.telemetrySupport != null) {
          activity.telemetrySupport.navigationStarted();
        }
      }
      activity.pageLoadStartTime = System.currentTimeMillis();
      activity.contentRevealSupport.navigationStarted();
      StashCheckoutLoadingSupport.showLoading(activity);
      StashCheckoutWebViewSupport.injectSDK(activity, view);
      StashCheckoutWebViewSupport.checkProvider(activity, url);
    } catch (Exception e) {
      Log.w(TAG, "Error in onPageStarted");
    }
  }

  @Override
  public void onPageFinished(WebView view, String url) {
    try {
      super.onPageFinished(view, url);

      if (activity.networkErrorHandled || activity.mainFrameErrorReceived
          || StashCheckoutLoadingSupport.isSupersededAttempt(activity, url)) {
        return;
      }

      if (activity.telemetrySupport != null) {
        activity.telemetrySupport.documentFinished(view, url);
      }

      activity.initialPageLoadComplete = true;

      activity.contentRevealSupport.documentFinished();
      StashCheckoutLoadingSupport.maybeRevealWhenReady(activity);
      StashCheckoutWebViewSupport.injectSDK(activity, view);
      StashCheckoutWebViewSupport.checkProvider(activity, url);
    } catch (Exception e) {
      Log.w(TAG, "Error in onPageFinished");
    }
  }

  @Override
  @SuppressWarnings("deprecation")
  public void onReceivedError(
      WebView view, int errorCode, String description, String failingUrl) {
    // This overload reports main-resource errors, including on API 21 and 22.
    handleMainFrameError(activity, view, errorCode, failingUrl);
  }

  @RequiresApi(Build.VERSION_CODES.M)
  @Override
  public void onReceivedError(WebView view, android.webkit.WebResourceRequest request,
      android.webkit.WebResourceError error) {
    try {
      // Do not call super: it forwards main-resource errors to the legacy overload.
      if (request != null && request.isForMainFrame()) {
        handleMainFrameError(activity, view,
            error != null ? error.getErrorCode() : WebViewClient.ERROR_UNKNOWN,
            request.getUrl() != null ? request.getUrl().toString() : null);
      }
    } catch (Exception e) {
      Log.w(TAG, "Error in onReceivedError");
    }
  }

  @Override
  public void onReceivedHttpError(WebView view, android.webkit.WebResourceRequest request,
      android.webkit.WebResourceResponse errorResponse) {
    try {
      super.onReceivedHttpError(view, request, errorResponse);

      if (request != null && request.isForMainFrame() && !activity.initialPageLoadComplete
          && !StashCheckoutLoadingSupport.isSupersededAttempt(activity,
              request.getUrl() != null ? request.getUrl().toString() : null)) {
        int statusCode = errorResponse != null ? errorResponse.getStatusCode() : 0;
        Log.e(TAG, "HTTP error on main frame during initial load: " + statusCode);
        activity.mainFrameErrorReceived = true;
        activity.handleNetworkError();
      }
    } catch (Exception e) {
      Log.w(TAG, "Error in onReceivedHttpError");
    }
  }

  @Override
  @RequiresApi(Build.VERSION_CODES.Q)
  public void onPageCommitVisible(WebView view, String pageUrl) {
    super.onPageCommitVisible(view, pageUrl);
    if (activity.telemetrySupport != null) {
      activity.telemetrySupport.documentCommitted(view, pageUrl);
    }
    StashCheckoutWebViewSupport.injectSDK(activity, view);
    StashCheckoutLoadingSupport.markMainFrameNavigationCommittedIfNeeded(activity);
    StashCheckoutLoadingSupport.maybeRevealWhenReady(activity);
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
      Log.w(TAG, "Error removing dead WebView");
    }
    activity.webView = null;
    // Recover one OS renderer kill; crashes and repeated kills remain terminal.
    if (!detail.didCrash() && !activity.rendererGoneReloadAttempted
        && !activity.isDismissing && !activity.isPurchaseProcessing) {
      activity.rendererGoneReloadAttempted = true;
      activity.initialPageLoadComplete = false;
      activity.mainFrameErrorReceived = false;
      activity.mainFrameNavigationCommitted = false;
      // Renderer recovery starts a fresh load budget.
      activity.networkDeadlineTargetUptime = 0L;
      activity.networkDeadlineRemainingMs = -1L;
      activity.webViewRetryCount = 0;
      // Remove the old overlay before creating the replacement WebView.
      StashCheckoutLoadingSupport.removeLoadingViewFromParent(activity);
      // onPageLoaded fires once per card, as on iOS; the reload is not a new presentation.
      boolean pageLoadedSent = activity.pageLoadedCallbackSent;
      StashCheckoutWebViewSupport.addWebView(activity);
      activity.pageLoadedCallbackSent = pageLoadedSent;
      activity.presentation.environmentChanged();
      if (activity.homeButton != null) {
        activity.homeButton.bringToFront();
      }
      if (activity.isActivityPaused) {
        // Background time must not consume the replacement load's deadline.
        StashCheckoutLoadingSupport.cancelLoadTimers(activity);
        activity.networkDeadlineTargetUptime = 0L;
        activity.networkDeadlineRemainingMs = CardConstants.WEBVIEW_NETWORK_DEADLINE_MS;
      }
      return true;
    }
    activity.handleNetworkError();
    return true;
  }

  private static void handleMainFrameError(
      StashCardActivity activity, WebView view, int code, String url) {
    if (view != activity.webView || activity.isDismissing || activity.networkErrorHandled
        || activity.mainFrameErrorReceived
        || StashCheckoutLoadingSupport.isSupersededAttempt(activity, url)) {
      return;
    }
    if (!activity.initialPageLoadComplete) {
      Log.e(TAG, "Network error on main frame during initial load: " + code);
      activity.mainFrameErrorReceived = true;
      activity.handleNetworkError();
    } else if (code == WebViewClient.ERROR_HOST_LOOKUP || code == WebViewClient.ERROR_CONNECT
        || code == WebViewClient.ERROR_TIMEOUT || code == WebViewClient.ERROR_IO) {
      // ERROR_UNKNOWN also represents cancelled navigations; keep those pages open.
      // A lost connection after load ends checkout as a network error, even while processing,
      // so the host never mistakes it for a user dismissal.
      Log.e(TAG, "Network error on main frame after load: " + code);
      activity.mainFrameErrorReceived = true;
      activity.handleNetworkError();
    }
  }
}
