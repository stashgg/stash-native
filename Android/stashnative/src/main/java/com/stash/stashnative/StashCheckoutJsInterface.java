package com.stash.stashnative;

import android.util.Log;
import android.webkit.JavascriptInterface;

/**
 * window.stash_sdk bridge for the checkout WebView. Registered under
 * {@link StashWebViewUtils#JS_INTERFACE_NAME}; methods run on the WebView's JS thread and
 * hop to the UI thread before touching views.
 */
class StashCheckoutJsInterface {
  private static final String TAG = "StashNativeCard";

  private final StashCheckoutActivity activity;

  StashCheckoutJsInterface(StashCheckoutActivity activity) {
    this.activity = activity;
  }

  @JavascriptInterface
  public void onPaymentSuccess(String order) {
    try {
      activity.notifyListenerAndDismiss(
          CardConstants.MESSAGE_TYPE_SUCCESS, order != null ? order : "", true);
    } catch (Exception e) {
      Log.w(TAG, "Error in onPaymentSuccess: " + e.getMessage(), e);
    }
  }

  @JavascriptInterface
  public void onPaymentFailure() {
    try {
      activity.notifyListenerAndDismiss(CardConstants.MESSAGE_TYPE_FAILURE, "", true);
    } catch (Exception e) {
      Log.w(TAG, "Error in onPaymentFailure: " + e.getMessage(), e);
    }
  }

  @JavascriptInterface
  public void onPurchaseProcessing() {
    try {
      activity.runOnUiThread(() -> {
        try {
          activity.isPurchaseProcessing = true;
          if (activity.presentation != null) {
            activity.presentation.processingStarted();
          }
          activity.applyDragHandlePurchaseProcessingFade(true);
        } catch (Exception e) {
          Log.w(TAG, "Error setting purchase processing: " + e.getMessage(), e);
        }
      });
    } catch (Exception e) {
      Log.w(TAG, "Error in onPurchaseProcessing: " + e.getMessage(), e);
    }
  }

  @JavascriptInterface
  public void onProcessingCompleted() {
    try {
      activity.runOnUiThread(() -> {
        try {
          activity.isPurchaseProcessing = false;
          activity.applyDragHandlePurchaseProcessingFade(false);
        } catch (Exception e) {
          Log.w(TAG, "Error clearing purchase processing: " + e.getMessage(), e);
        }
      });
    } catch (Exception e) {
      Log.w(TAG, "Error in onProcessingCompleted: " + e.getMessage(), e);
    }
  }

  @JavascriptInterface
  public void setPaymentChannel(String optinType) {
    try {
      activity.notifyListenerAndDismiss(
          CardConstants.MESSAGE_TYPE_OPTIN, optinType != null ? optinType : "", false);
    } catch (Exception e) {
      Log.w(TAG, "Error in setPaymentChannel: " + e.getMessage(), e);
    }
  }

  @JavascriptInterface public void expand() {
    activity.runOnUiThread(activity::animateExpand);
  }

  @JavascriptInterface public void collapse() {
    activity.runOnUiThread(activity::animateCollapse);
  }

  @JavascriptInterface public void setContentHeight(String payload) {
    activity.runOnUiThread(() -> {
      if (activity.contentSizeSupport != null) {
        activity.contentSizeSupport.accept(payload);
      }
    });
  }

  @JavascriptInterface
  public void requestCloseFromPage() {
    try {
      activity.runOnUiThread(() -> {
        try {
          activity.requestUserDismiss();
        } catch (Exception e) {
          Log.w(TAG, "Error in requestCloseFromPage: " + e.getMessage(), e);
        }
      });
    } catch (Exception e) {
      Log.w(TAG, "Error scheduling requestCloseFromPage: " + e.getMessage(), e);
    }
  }

  @JavascriptInterface
  public void openExternalBrowser(String url) {
    try {
      activity.runOnUiThread(() -> {
        try {
          String normalized = StashWebViewUtils.normalizeExternalPaymentUrl(url);
          if (normalized == null) {
            return;
          }
          String themed =
              StashWebViewUtils.appendThemeQueryParameter(
                  normalized, activity.effectiveIsDarkForContent);
          activity.callbackSent = true;
          activity.isPurchaseProcessing = false;
          StashNativeCardPlugin.getInstance()
              .openExternalBrowserFromCheckout(
                  activity,
                  themed,
                  true,
                  activity::hideCardSheetLeavingDimOverlay,
                  activity::finishAfterExternalBrowserClose);
        } catch (Exception e) {
          Log.w(TAG, "Error in openExternalBrowser: " + e.getMessage(), e);
        }
      });
    } catch (Exception e) {
      Log.w(TAG, "Error scheduling openExternalBrowser: " + e.getMessage(), e);
    }
  }

  /** Opens the URL in the external browser. No callbacks, no dismissal (terms, misc links). */
  @JavascriptInterface
  public void openLink(String url) {
    try {
      activity.runOnUiThread(() -> {
        try {
          String normalized = StashWebViewUtils.normalizeExternalPaymentUrl(url);
          if (normalized == null) {
            return;
          }
          StashWebViewUtils.openInSystemBrowser(activity, normalized);
        } catch (Exception e) {
          Log.w(TAG, "Error in openLink: " + e.getMessage(), e);
        }
      });
    } catch (Exception e) {
      Log.w(TAG, "Error scheduling openLink: " + e.getMessage(), e);
    }
  }
}
