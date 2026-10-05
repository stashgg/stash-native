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
  private final long session;

  private void onMain(Runnable action) {
    new Handler(Looper.getMainLooper()).post(() -> {
      if (plugin.presentationSessionId == session && plugin.isCurrentlyPresented) {
        action.run();
      }
    });
  }

  StashPopupJsInterface(StashNativeCardPlugin plugin) {
    this.plugin = plugin;
    this.session = plugin.presentationSessionId;
  }

  @JavascriptInterface
  public void onPaymentSuccess(String order) {
    onMain(() -> {
      if (plugin.paymentSuccessHandled) {
        return;
      }
      plugin.paymentSuccessHandled = true;
      plugin.popupProcessingSession.compareAndSet(session, 0);
      // Documented contract: no order argument surfaces as null (card path and iOS agree).
      final String orderPayload = (order != null && !order.isEmpty()) ? order : null;
      plugin.runOnMainAndDismiss(() -> {
        StashNativeCard.StashNativeCardListener l = plugin.getListener();
        if (l != null) {
          l.onPaymentSuccess(orderPayload);
        }
      });
    });
  }

  @JavascriptInterface
  public void onPaymentFailure() {
    onMain(() -> {
      if (plugin.paymentSuccessHandled) {
        return;
      }
      plugin.paymentSuccessHandled = true;
      plugin.popupProcessingSession.compareAndSet(session, 0);
      plugin.runOnMainAndDismiss(() -> {
        StashNativeCard.StashNativeCardListener l = plugin.getListener();
        if (l != null) {
          l.onPaymentFailure();
        }
      });
    });
  }

  @JavascriptInterface
  public void onPurchaseProcessing() {
    // Set on the bridge thread so a queued backdrop tap cannot win the race and the page's order of
    // start/complete is kept. Session ids only grow, so a stale bridge never replaces a newer lock.
    long held;
    do {
      held = plugin.popupProcessingSession.get();
      if (held > session) {
        break;
      }
    } while (!plugin.popupProcessingSession.compareAndSet(held, session));
    onMain(() -> {
      try {
        if (plugin.currentDialog != null && plugin.currentDialog.isShowing()) {
          boolean dismissible = !plugin.isPopupProcessing();
          plugin.currentDialog.setCanceledOnTouchOutside(dismissible);
          plugin.currentDialog.setCancelable(dismissible);
        }
      } catch (Exception e) {
        Log.w(TAG, "Error updating dialog dismissibility: " + e.getMessage(), e);
      }
    });
  }

  @JavascriptInterface
  public void onProcessingCompleted() {
    plugin.popupProcessingSession.compareAndSet(session, 0);
    onMain(() -> {
      try {
        if (plugin.currentDialog != null && plugin.currentDialog.isShowing()) {
          boolean dismissible = !plugin.isPopupProcessing();
          plugin.currentDialog.setCanceledOnTouchOutside(dismissible);
          plugin.currentDialog.setCancelable(dismissible);
        }
      } catch (Exception e) {
        Log.w(TAG, "Error updating dialog dismissibility: " + e.getMessage(), e);
      }
    });
  }

  @JavascriptInterface
  public void setPaymentChannel(String optinType) {
    onMain(() -> plugin.runOnMainAndDismiss(() -> {
      StashNativeCard.StashNativeCardListener l = plugin.getListener();
      if (l != null) {
        l.onOptInResponse(optinType != null ? optinType : "");
      }
    }));
  }

  @JavascriptInterface
  public void expand() {
  }

  @JavascriptInterface
  public void collapse() {
  }

  @JavascriptInterface
  public void requestCloseFromPage() {
    onMain(() -> {
      if (plugin.isPopupProcessing()) {
        return;
      }
      try {
        plugin.dismissCurrentDialog();
      } catch (Exception e) {
        Log.w(TAG, "Error in requestCloseFromPage: " + e.getMessage(), e);
      }
    });
  }

  @JavascriptInterface
  public void openExternalBrowser(String url) {
    onMain(() -> {
      Activity activity = null;
      try {
        String normalized = StashWebViewUtils.normalizeExternalPaymentUrl(url);
        if (normalized == null) {
          return;
        }
        activity = plugin.getActivity();
        if (activity == null) {
          return;
        }
        boolean effDark = StashPopupDialogSupport.dialogEffectiveDarkForWeb(plugin, activity);
        String themed = StashWebViewUtils.appendThemeQueryParameter(normalized, effDark);
        plugin.paymentSuccessHandled = true;
        plugin.popupProcessingSession.compareAndSet(session, 0);
        StashNativeCard.StashNativeCardListener listener = plugin.getListener();
        plugin.isCurrentlyPresented = false;
        // Dismissal starts while this popup is still current; a checkout the callback opens
        // cancels it and owns the singleton afterwards.
        plugin.dismissCurrentDialog();
        if (listener != null) {
          listener.onExternalPayment(themed);
        }
        if (themed.isEmpty()) {
          return;
        }
        plugin.startKeepAliveBeforeBrowser(activity);
        plugin.launchExternalBrowser(activity, themed);
      } catch (Exception e) {
        plugin.cancelBrowserCloseTrackingLaunch();
        if (activity != null) {
          plugin.stopKeepAliveForegroundService(activity.getApplicationContext());
        }
        Log.w(TAG, "Error in openExternalBrowser: " + e.getMessage(), e);
      }
    });
  }

  /** Opens the URL in the external browser. No callbacks, no dismissal (terms, misc links). */
  @JavascriptInterface
  public void openLink(String url) {
    onMain(() -> {
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
