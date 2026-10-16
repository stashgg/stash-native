package com.stash.stashnative;

import android.os.Build;
import android.util.Log;
import android.view.HapticFeedbackConstants;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;

/** Dispatches WebView bridge calls to the checkout's UI thread. */
final class StashCheckoutJsInterface {
  private static final String TAG = "StashNativeCard";
  private final StashCheckoutActivity activity;

  StashCheckoutJsInterface(StashCheckoutActivity activity) {
    this.activity = activity;
  }

  @JavascriptInterface
  public void onPaymentSuccess(String order) {
    dispatch("onPaymentSuccess", () -> activity.notifyPaymentResult(true, order));
  }

  @JavascriptInterface
  public void onPaymentFailure() {
    dispatch("onPaymentFailure", () -> activity.notifyPaymentResult(false, null));
  }

  @JavascriptInterface
  public void onPurchaseProcessing() {
    dispatch("onPurchaseProcessing", () -> setProcessing(true));
  }

  @JavascriptInterface
  public void onProcessingCompleted() {
    dispatch("onProcessingCompleted", () -> setProcessing(false));
  }

  private void setProcessing(boolean processing) {
    activity.isPurchaseProcessing = processing;
    if (processing && activity.presentation != null) {
      activity.presentation.processingStarted();
    }
    activity.applyDragHandlePurchaseProcessingFade(processing);
  }

  @JavascriptInterface
  public void expand() {
    dispatch("expand", activity::animateExpand);
  }

  @JavascriptInterface
  public void collapse() {
    dispatch("collapse", activity::animateCollapse);
  }

  @JavascriptInterface
  public void setContentHeight(String payload) {
    dispatch("setContentHeight", () -> {
      if (activity.contentSizeSupport != null) {
        activity.contentSizeSupport.accept(payload);
      }
    });
  }

  @JavascriptInterface
  public void getTelemetry(String documentToken, int requestId) {
    dispatch("getTelemetry", () -> {
      if (activity.telemetrySupport != null) {
        activity.telemetrySupport.request(documentToken, requestId);
      }
    });
  }

  @JavascriptInterface
  public void triggerHaptic() {
    dispatch("triggerHaptic", () -> {
      WebView web = activity.webView;
      if (activity.isDismissing || activity.isActivityPaused || web == null
          || !web.isShown() || !web.hasWindowFocus()) {
        return;
      }
      web.performHapticFeedback(Build.VERSION.SDK_INT >= 30
          ? HapticFeedbackConstants.CONFIRM : HapticFeedbackConstants.VIRTUAL_KEY);
    });
  }

  @JavascriptInterface
  public void requestCloseFromPage() {
    dispatch("requestCloseFromPage", activity::requestCloseFromPage);
  }

  @JavascriptInterface
  public void openExternalBrowser(String url) {
    dispatch("openExternalBrowser", () -> {
      String normalized = StashWebViewUtils.normalizeExternalPaymentUrl(url);
      if (normalized == null) {
        return;
      }
      String themed = StashWebViewUtils.appendThemeQueryParameter(
          normalized, activity.effectiveIsDarkForContent);
      StashNativeCardPlugin.getInstance().openExternalBrowserFromCheckout(
          activity, themed, true,
          activity::hideCardSheetLeavingDimOverlay, activity::finishAfterExternalBrowserClose);
    });
  }

  /** Opens a link without payment callbacks or checkout dismissal. */
  @JavascriptInterface
  public void openLink(String url) {
    dispatch("openLink", () -> {
      String normalized = StashWebViewUtils.normalizeExternalPaymentUrl(url);
      if (normalized != null) {
        StashWebViewUtils.openInSystemBrowser(activity, normalized);
      }
    });
  }

  private void dispatch(String operation, Runnable action) {
    try {
      activity.runOnUiThread(() -> {
        try {
          StashNativeCardPlugin plugin = StashNativeCardPlugin.getInstance();
          if (!plugin.isCurrentlyPresented || activity.isDismissing
              || activity.isFinishing() || activity.isDestroyed()
              || activity.getPresentationSessionId() != plugin.presentationSessionId) {
            return;
          }
          action.run();
        } catch (Exception error) {
          Log.w(TAG, "Bridge operation failed: " + operation, error);
        }
      });
    } catch (Exception error) {
      Log.w(TAG, "Cannot dispatch bridge operation: " + operation, error);
    }
  }
}
