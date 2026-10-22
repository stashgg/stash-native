package com.stash.stashnative;

import android.os.Build;
import android.util.Log;
import android.view.HapticFeedbackConstants;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;

/**
 * Dispatches WebView bridge calls to the checkout's UI thread.
 *
 * <p>WebView exposes this object to every frame. The main-frame bridge script passes the
 * document token issued by {@link StashCardActivity} as the first argument; calls without
 * the current token are ignored, so subframes cannot drive checkout. {@link #setContentHeight}
 * and {@link #getTelemetry} keep their own per-document tokens.
 */
final class StashCheckoutJsInterface {
  private static final String TAG = "StashNative";
  private final StashCardActivity activity;
  private final boolean nativeCaller;

  StashCheckoutJsInterface(StashCardActivity activity) {
    this(activity, false);
  }

  private StashCheckoutJsInterface(StashCardActivity activity, boolean nativeCaller) {
    this.activity = activity;
    this.nativeCaller = nativeCaller;
  }

  /** For stash-pay deeplink results: no page token, but the same session guards and dispatch. */
  static StashCheckoutJsInterface forNativeResults(StashCardActivity activity) {
    return new StashCheckoutJsInterface(activity, true);
  }

  @JavascriptInterface
  public void onPaymentSuccess(String token, String order) {
    dispatch("onPaymentSuccess", token, () -> activity.notifyPaymentResult(true, order));
  }

  @JavascriptInterface
  public void onPaymentFailure(String token) {
    dispatch("onPaymentFailure", token, () -> activity.notifyPaymentResult(false, null));
  }

  @JavascriptInterface
  public void onPurchaseProcessing(String token) {
    dispatch("onPurchaseProcessing", token, () -> setProcessing(true));
  }

  @JavascriptInterface
  public void onProcessingCompleted(String token) {
    dispatch("onProcessingCompleted", token, () -> setProcessing(false));
  }

  private void setProcessing(boolean processing) {
    activity.isPurchaseProcessing = processing;
    if (processing && activity.presentation != null) {
      activity.presentation.processingStarted();
    }
    activity.applyDragHandlePurchaseProcessingFade(processing);
  }

  @JavascriptInterface
  public void expand(String token) {
    dispatch("expand", token, activity::animateExpand);
  }

  @JavascriptInterface
  public void collapse(String token) {
    dispatch("collapse", token, activity::animateCollapse);
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
  public void triggerHaptic(String token) {
    triggerHaptic(token, "short");
  }

  /** {@code "long"} plays a heavier pulse; anything else is the short confirmation. */
  @JavascriptInterface
  public void triggerHaptic(String token, String type) {
    boolean heavy = "long".equals(type);
    dispatch("triggerHaptic", token, () -> {
      WebView web = activity.webView;
      if (activity.isDismissing || activity.isActivityPaused || web == null
          || !web.isShown() || !web.hasWindowFocus()) {
        return;
      }
      int feedback;
      if (heavy) {
        // A longer vibration needs the VIBRATE permission; the core SDK declares none.
        feedback = Build.VERSION.SDK_INT >= 30
            ? HapticFeedbackConstants.REJECT : HapticFeedbackConstants.LONG_PRESS;
      } else {
        feedback = Build.VERSION.SDK_INT >= 30
            ? HapticFeedbackConstants.CONFIRM : HapticFeedbackConstants.VIRTUAL_KEY;
      }
      web.performHapticFeedback(feedback);
    });
  }

  @JavascriptInterface
  public void requestCloseFromPage(String token) {
    dispatch("requestCloseFromPage", token, activity::requestCloseFromPage);
  }

  @JavascriptInterface
  public void openExternalBrowser(String token, String url) {
    externalBrowser(token, url, false);
  }

  /** With {@code keepOpen}, the browser opens over the card, which stays open for the return. */
  @JavascriptInterface
  public void externalBrowser(String token, String url, boolean keepOpen) {
    if (keepOpen) {
      dispatch("externalBrowser", token, () -> {
        String normalized = StashWebViewUtils.normalizeExternalPaymentUrl(url);
        if (normalized == null) {
          return;
        }
        StashNativePlugin.getInstance().openExternalBrowserOverCheckout(
            activity,
            StashWebViewUtils.appendThemeQueryParameter(
                normalized, activity.effectiveIsDarkForContent));
      });
      return;
    }
    dispatch("openExternalBrowser", token, () -> {
      String normalized = StashWebViewUtils.normalizeExternalPaymentUrl(url);
      if (normalized == null) {
        return;
      }
      String themed = StashWebViewUtils.appendThemeQueryParameter(
          normalized, activity.effectiveIsDarkForContent);
      StashNativePlugin.getInstance().openExternalBrowserFromCheckout(
          activity, themed, true,
          activity::hideCardSheetLeavingDimOverlay, activity::finishAfterExternalBrowserClose);
    });
  }

  /** Opens a link without payment callbacks or checkout dismissal. */
  @JavascriptInterface
  public void openLink(String token, String url) {
    dispatch("openLink", token, () -> {
      String normalized = StashWebViewUtils.normalizeExternalPaymentUrl(url);
      if (normalized != null) {
        StashWebViewUtils.openInSystemBrowser(activity, normalized);
      }
    });
  }

  private void dispatch(String operation, String token, Runnable action) {
    dispatch(operation, () -> {
      if (nativeCaller || activity.acceptsBridgeToken(token)) {
        action.run();
      }
    });
  }

  private void dispatch(String operation, Runnable action) {
    try {
      activity.runOnUiThread(() -> {
        try {
          StashNativePlugin plugin = StashNativePlugin.getInstance();
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
