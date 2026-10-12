package com.stash.stashnative;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.util.Log;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/** Routes checkout results, deeplinks, and new-window URLs without creating a second tab. */
final class StashCheckoutNavigationSupport {
  private static final String TAG = "StashNativeCard";

  private StashCheckoutNavigationSupport() {}

  /**
   * Non-web schemes never load in the card. stash-pay result paths run the standard JS-bridge
   * flows (success/failure/close); any other deeplink is handed to the OS with the card left
   * open. Returns true when the navigation was consumed.
   */
  static boolean handleDeeplinkNavigation(StashCheckoutActivity activity, String url) {
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

  /** Captures a new window's first navigation in a temporary WebView for external routing. */
  static boolean openTargetBlankWindow(
      Activity activity, WebView parent, android.os.Message resultMsg) {
    try {
      final WebView transport = new WebView(parent.getContext());
      transport.setWebViewClient(new WebViewClient() {
        @Override
        public boolean shouldOverrideUrlLoading(
            WebView view, android.webkit.WebResourceRequest request) {
          return route(request.getUrl() != null ? request.getUrl().toString() : null);
        }

        @Override
        @SuppressWarnings("deprecation")
        public boolean shouldOverrideUrlLoading(WebView view, String url) {
          return route(url);
        }

        private boolean route(String url) {
          openTargetBlankExternally(activity, url);
          transport.post(transport::destroy);
          return true;
        }
      });
      ((WebView.WebViewTransport) resultMsg.obj).setWebView(transport);
      resultMsg.sendToTarget();
      return true;
    } catch (Throwable t) {
      Log.w(TAG, "onCreateWindow handling failed");
      return false;
    }
  }

  /**
   * Opens a target=_blank / window.open destination outside the checkout. http/https go to the
   * system browser (openLink semantics: no theme, no dismissal, card stays presented); any other
   * scheme flows through the normal deeplink handling.
   */
  static void openTargetBlankExternally(Activity activity, String url) {
    if (activity == null || url == null || url.isEmpty()) {
      return;
    }
    if (StashWebViewUtils.isWebScheme(url)) {
      String normalized = StashWebViewUtils.normalizeExternalPaymentUrl(url);
      if (normalized != null) {
        StashWebViewUtils.openInSystemBrowser(activity, normalized);
      }
      return;
    }
    openDeeplinkExternally(activity, url);
  }

  /** ACTION_VIEW for a non-stash deeplink; no browser-close tracking, card stays open. */
  static void openDeeplinkExternally(Activity activity, String url) {
    if (activity == null || url == null || url.isEmpty()) {
      return;
    }
    if (url.regionMatches(true, 0, "intent:", 0, 7)) {
      openIntentUri(activity, url);
      return;
    }
    try {
      Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
      activity.startActivity(intent);
    } catch (Throwable t) {
      // App not installed / no handler: nothing more to try for a bare custom-scheme URL.
      Log.w(TAG, "No handler for deeplink");
    }
  }

  /**
   * Launches an {@code intent://} URI (Chrome intent syntax). Clears any component/selector to
   * stop the URI redirecting to an internal host component (WebView intent-redirection hardening),
   * then falls back to {@code browser_fallback_url} or the Play Store when the target app is
   * missing. Card stays open throughout.
   */
  private static void openIntentUri(Activity activity, String url) {
    Intent intent;
    try {
      intent = Intent.parseUri(url, Intent.URI_INTENT_SCHEME);
    } catch (Throwable t) {
      Log.w(TAG, "Malformed intent URI");
      return;
    }
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    intent.setComponent(null);
    intent.setSelector(null);
    try {
      activity.startActivity(intent);
      return;
    } catch (Throwable t) {
      Log.w(TAG, "No app for intent URI");
    }
    String fallback = intent.getStringExtra("browser_fallback_url");
    if (fallback != null && StashWebViewUtils.isWebScheme(fallback)) {
      openDeeplinkExternally(activity, fallback);
      return;
    }
    String pkg = intent.getPackage();
    if (pkg != null && !pkg.isEmpty()) {
      openPlayStoreForPackage(activity, pkg);
    }
  }

  /** Tries the Play Store app before its web listing. */
  private static void openPlayStoreForPackage(Activity activity, String pkg) {
    try {
      Intent market = new Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=" + pkg));
      market.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
      activity.startActivity(market);
      return;
    } catch (Throwable ignored) {
      // Devices without the Play Store can open the web listing.
    }
    try {
      Intent web = new Intent(Intent.ACTION_VIEW,
          Uri.parse("https://play.google.com/store/apps/details?id=" + pkg));
      web.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
      activity.startActivity(web);
    } catch (Throwable t) {
      Log.w(TAG, "No Play Store for package " + pkg);
    }
  }
}
