package com.stash.stashnative;

import android.app.Activity;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.webkit.JavascriptInterface;

/**
 * window.stash_sdk bridge for the popup/modal Dialog WebView. Registered under
 * {@link StashWebViewUtils#JS_INTERFACE_NAME}; methods run on the WebView's JS thread.
 */
class StashPopupJsInterface {
  private static final String TAG = "StashNativeCard";

  private final StashNativeCardPlugin plugin;

  StashPopupJsInterface(StashNativeCardPlugin plugin) {
    this.plugin = plugin;
  }

  @JavascriptInterface
  public void onPaymentSuccess(String order) {
    if (plugin.paymentSuccessHandled) {
      return;
    }
    plugin.paymentSuccessHandled = true;
    plugin.isPurchaseProcessing = false;
    final String orderPayload = order;
    plugin.runOnMainAndDismiss(() -> {
      StashNativeCard.StashNativeCardListener l = plugin.getListener();
      if (l != null) {
        l.onPaymentSuccess(orderPayload);
      }
    });
  }

  @JavascriptInterface
  public void onPaymentFailure() {
    if (plugin.paymentSuccessHandled) {
      return;
    }
    plugin.paymentSuccessHandled = true;
    plugin.isPurchaseProcessing = false;
    plugin.runOnMainAndDismiss(() -> {
      StashNativeCard.StashNativeCardListener l = plugin.getListener();
      if (l != null) {
        l.onPaymentFailure();
      }
    });
  }

  @JavascriptInterface
  public void onPurchaseProcessing() {
    plugin.isPurchaseProcessing = true;
    new Handler(Looper.getMainLooper()).post(() -> {
      try {
        if (plugin.currentDialog != null && plugin.currentDialog.isShowing()) {
          plugin.currentDialog.setCanceledOnTouchOutside(false);
          plugin.currentDialog.setCancelable(false);
        }
      } catch (Exception e) {
        Log.w(TAG, "Error updating dialog dismissibility: " + e.getMessage(), e);
      }
    });
  }

  @JavascriptInterface
  public void onProcessingCompleted() {
    plugin.isPurchaseProcessing = false;
    new Handler(Looper.getMainLooper()).post(() -> {
      try {
        if (plugin.currentDialog != null && plugin.currentDialog.isShowing()) {
          plugin.currentDialog.setCanceledOnTouchOutside(true);
          plugin.currentDialog.setCancelable(true);
        }
      } catch (Exception e) {
        Log.w(TAG, "Error updating dialog dismissibility: " + e.getMessage(), e);
      }
    });
  }

  @JavascriptInterface
  public void setPaymentChannel(String optinType) {
    plugin.runOnMainAndDismiss(() -> {
      StashNativeCard.StashNativeCardListener l = plugin.getListener();
      if (l != null) {
        l.onOptInResponse(optinType != null ? optinType : "");
      }
    });
  }

  @JavascriptInterface
  public void expand() {
  }

  @JavascriptInterface
  public void collapse() {
  }

  @JavascriptInterface
  public void requestCloseFromPage() {
    if (plugin.isPurchaseProcessing) {
      return;
    }
    new Handler(Looper.getMainLooper()).post(() -> {
      try {
        plugin.dismissCurrentDialog();
      } catch (Exception e) {
        Log.w(TAG, "Error in requestCloseFromPage: " + e.getMessage(), e);
      }
    });
  }

  @JavascriptInterface
  public void openExternalBrowser(String url) {
    new Handler(Looper.getMainLooper()).post(() -> {
      try {
        String normalized = StashWebViewUtils.normalizeExternalPaymentUrl(url);
        if (normalized == null) {
          return;
        }
        Activity activity = plugin.getActivity();
        if (activity == null) {
          return;
        }
        boolean effDark = StashPopupDialogSupport.dialogEffectiveDarkForWeb(plugin, activity);
        String themed = StashWebViewUtils.appendThemeQueryParameter(normalized, effDark);
        plugin.paymentSuccessHandled = true;
        plugin.isPurchaseProcessing = false;
        StashNativeCard.StashNativeCardListener listener = plugin.getListener();
        if (listener != null) {
          listener.onExternalPayment(themed);
        }
        plugin.dismissCurrentDialog();
        Activity act = plugin.getActivity();
        if (act == null || themed.isEmpty()) {
          return;
        }
        plugin.startKeepAliveBeforeBrowser(act);
        plugin.launchExternalBrowser(act, themed);
      } catch (Exception e) {
        plugin.cancelBrowserCloseTrackingLaunch();
        Log.w(TAG, "Error in openExternalBrowser: " + e.getMessage(), e);
      }
    });
  }

  /** Opens the URL in the external browser. No callbacks, no dismissal (terms, misc links). */
  @JavascriptInterface
  public void openLink(String url) {
    new Handler(Looper.getMainLooper()).post(() -> {
      try {
        String normalized = StashWebViewUtils.normalizeExternalPaymentUrl(url);
        if (normalized == null) {
          return;
        }
        Activity activity = plugin.getActivity();
        if (activity == null) {
          return;
        }
        StashWebViewUtils.openInSystemBrowser(activity, normalized);
      } catch (Exception e) {
        Log.w(TAG, "Error in openLink: " + e.getMessage(), e);
      }
    });
  }
}
