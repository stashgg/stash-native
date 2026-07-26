package com.stash.stashnative;

import android.app.Activity;
import android.content.Context;
import android.content.res.Configuration;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.webkit.CookieManager;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.widget.FrameLayout;
import android.widget.ProgressBar;
import androidx.webkit.WebSettingsCompat;
import androidx.webkit.WebViewFeature;
import androidx.core.view.WindowInsetsControllerCompat;

/**
 * Utility class for WebView configuration and common operations.
 */
public class StashWebViewUtils {
  private static final String TAG = "StashWebViewUtils";

  /** JavaScript bridge name used by addJavascriptInterface and JS_SDK_SCRIPT. */
  public static final String JS_INTERFACE_NAME = "StashAndroid";
  
  /** Deeplink result classification (stash-pay result paths, any scheme). */
  public static final int DEEPLINK_RESULT_NONE = 0;
  public static final int DEEPLINK_RESULT_SUCCESS = 1;
  public static final int DEEPLINK_RESULT_FAILURE = 2;
  public static final int DEEPLINK_RESULT_CANCEL = 3;

  /** True when the URL loads inside the WebView (web schemes); false for deeplinks. */
  public static boolean isWebScheme(String url) {
    if (url == null) {
      return false;
    }
    String lower = url.trim().toLowerCase(java.util.Locale.US);
    return lower.startsWith("http://") || lower.startsWith("https://")
        || lower.startsWith("about:") || lower.startsWith("data:")
        || lower.startsWith("blob:") || lower.startsWith("file:")
        || lower.startsWith("javascript:");
  }

  /**
   * Classifies a deeplink as a stash-pay result. Matches the path anywhere in the URL so any
   * scheme works (spec: stash-pay/success, stash-pay/failure, stash-pay/cancel).
   */
  public static int classifyDeeplinkResult(String url) {
    if (url == null) {
      return DEEPLINK_RESULT_NONE;
    }
    String lower = url.toLowerCase(java.util.Locale.US);
    if (lower.contains("stash-pay/success")) {
      return DEEPLINK_RESULT_SUCCESS;
    }
    if (lower.contains("stash-pay/failure")) {
      return DEEPLINK_RESULT_FAILURE;
    }
    if (lower.contains("stash-pay/cancel")) {
      return DEEPLINK_RESULT_CANCEL;
    }
    return DEEPLINK_RESULT_NONE;
  }

  /** Query param name for theme. */
  public static final String QUERY_PARAM_THEME = "theme";
  public static final String THEME_DARK = "dark";
  public static final String THEME_LIGHT = "light";
  
  /** Overlay dim (40% alpha). */
  public static final String COLOR_BACKGROUND_DIM = CardConstants.COLOR_OVERLAY_DIM;
  public static final String COLOR_DARK_BG = CardConstants.COLOR_DARK_BG;
  
  // Canonical spec: docs/stash-sdk-js.md. Changes here MUST be mirrored on iOS (StashNativeCard.m).
  public static final String JS_SDK_SCRIPT = "(function() {"
      + "  window.stash_sdk = window.stash_sdk || {};"
      + "  window.stash_sdk.onPaymentSuccess = function(order) {"
      + "    try { var p=null;"
      + "      if(arguments.length>0&&order!==undefined&&order!==null){"
      + "        p=(typeof order==='string')?order:JSON.stringify(order);"
      + "      }"
      + JS_INTERFACE_NAME
      + ".onPaymentSuccess(p); } catch(e) {}"
      + "  };"
      + "  window.stash_sdk.onPaymentFailure = function(data) {"
      + "    try { "
      + JS_INTERFACE_NAME
      + ".onPaymentFailure(); } catch(e) {}"
      + "  };"
      + "  window.stash_sdk.onPurchaseProcessing = function(data) {"
      + "    try { "
      + JS_INTERFACE_NAME
      + ".onPurchaseProcessing(); } catch(e) {}"
      + "  };"
      + "  window.stash_sdk.onProcessingCompleted = function(data) {"
      + "    try { "
      + JS_INTERFACE_NAME
      + ".onProcessingCompleted(); } catch(e) {}"
      + "  };"
      + "  window.stash_sdk.setPaymentChannel = function(optinType) {"
      + "    try { "
      + JS_INTERFACE_NAME
      + ".setPaymentChannel(optinType || ''); } catch(e) {}"
      + "  };"
      + "  window.stash_sdk.expand = function() {"
      + "    try { "
      + JS_INTERFACE_NAME
      + ".expand(); } catch(e) {}"
      + "  };"
      + "  window.stash_sdk.collapse = function() {"
      + "    try { "
      + JS_INTERFACE_NAME
      + ".collapse(); } catch(e) {}"
      + "  };"
      + "  window.stash_sdk.openExternalBrowser = function(url) {"
      + "    try { "
      + JS_INTERFACE_NAME
      + ".openExternalBrowser((url !== undefined && url !== null) ? String(url) : ''); } catch(e) {}"
      + "  };"
      + "  window.stash_sdk.openLink = function(url) {"
      + "    try { "
      + JS_INTERFACE_NAME
      + ".openLink((url !== undefined && url !== null) ? String(url) : ''); } catch(e) {}"
      + "  };"
      + "  try { window.close = function() { try { "
      + JS_INTERFACE_NAME
      + ".requestCloseFromPage(); } catch(e2) {} }; } catch(e) {}"
      + "})();";

  /**
   * Returns true if the context is in dark theme (night mode).
   *
   * @param context context to check
   * @return true if dark theme
   */
  public static boolean isDarkTheme(Context context) {
    if (context == null) {
      return false;
    }
    int nightModeFlags = context.getResources().getConfiguration().uiMode
        & Configuration.UI_MODE_NIGHT_MASK;
    return nightModeFlags == Configuration.UI_MODE_NIGHT_YES;
  }

  /**
   * Dark vs light for URL {@code theme=} and WebView forcing: custom background luminance if set,
   * else system night mode.
   */
  public static boolean effectiveDarkThemeForCheckout(Context context, String backgroundHexOrNull) {
    Integer c = StashBackgroundColorUtils.parseSolidColorOrNull(backgroundHexOrNull);
    if (c != null) {
      return StashBackgroundColorUtils.isDarkBackground(c);
    }
    return isDarkTheme(context);
  }

  /**
   * Status/nav bars when the sheet uses a custom background color (nav bar matches sheet).
   */
  public static void applySystemBarAppearanceForSheet(Window window, View decorView, int sheetArgb) {
    if (window == null || decorView == null) {
      return;
    }
    try {
      boolean darkBg = StashBackgroundColorUtils.isDarkBackground(sheetArgb);
      WindowInsetsControllerCompat controller =
          StashWindowCompat.getInsetsController(window, decorView);
      window.setStatusBarColor(Color.TRANSPARENT);
      window.setNavigationBarColor(sheetArgb);
      if (controller != null) {
        controller.setAppearanceLightStatusBars(!darkBg);
        controller.setAppearanceLightNavigationBars(!darkBg);
      }
    } catch (Exception e) {
      Log.e(TAG, "applySystemBarAppearanceForSheet: " + e.getMessage(), e);
    }
  }

  /**
   * Keeps status/navigation bar icon contrast aligned with app night mode. Without this, a
   * translucent Stash window can reset the nav bar to light (light icons / wrong background).
   */
  public static void applySystemBarAppearance(Window window, View decorView, boolean darkTheme) {
    if (window == null || decorView == null) {
      return;
    }
    try {
      WindowInsetsControllerCompat controller =
          StashWindowCompat.getInsetsController(window, decorView);
      if (darkTheme) {
        window.setStatusBarColor(Color.TRANSPARENT);
        window.setNavigationBarColor(Color.parseColor(COLOR_DARK_BG));
        if (controller != null) {
          controller.setAppearanceLightStatusBars(false);
          controller.setAppearanceLightNavigationBars(false);
        }
      } else {
        window.setStatusBarColor(Color.TRANSPARENT);
        window.setNavigationBarColor(Color.WHITE);
        if (controller != null) {
          controller.setAppearanceLightStatusBars(true);
          controller.setAppearanceLightNavigationBars(true);
        }
      }
    } catch (Exception e) {
      Log.e(TAG, "applySystemBarAppearance: " + e.getMessage(), e);
    }
  }

  /**
   * Converts density-independent pixels to pixels.
   *
   * @param context context for density
   * @param dp density-independent pixels
   * @return pixels, or 0 if context is null
   */
  public static int dpToPx(Context context, int dp) {
    if (context == null) {
      return 0;
    }
    return Math.round(dp * context.getResources().getDisplayMetrics().density);
  }

  /**
   * Returns true if the activity is running on a tablet-sized device.
   *
   * @param activity activity to check
   * @return true if tablet
   */
  public static boolean isTablet(Activity activity) {
    if (activity == null) {
      return false;
    }
    DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
    int smallerDimension = Math.min(metrics.widthPixels, metrics.heightPixels);
    float smallerDp = smallerDimension / metrics.density;
    
    boolean isTabletBySize = smallerDp >= CardConstants.TABLET_SIZE_THRESHOLD_DP;
    
    int screenSize = activity.getResources().getConfiguration().screenLayout
        & Configuration.SCREENLAYOUT_SIZE_MASK;
    boolean isTabletByConfig = (screenSize == Configuration.SCREENLAYOUT_SIZE_LARGE
        || screenSize == Configuration.SCREENLAYOUT_SIZE_XLARGE);
    
    float aspectRatio = (float) Math.max(metrics.widthPixels, metrics.heightPixels)
        / Math.min(metrics.widthPixels, metrics.heightPixels);
    boolean isTabletByAspect = aspectRatio < 2.0f && smallerDp >= 500;
    
    return isTabletBySize || isTabletByConfig || isTabletByAspect;
  }

  /**
   * Configures WebView settings for checkout (JS, storage, theme).
   *
   * @param webView WebView to configure
   * @param isDarkTheme whether to force dark mode
   */
  public static void configureWebViewSettings(WebView webView, boolean isDarkTheme) {
    if (webView == null) {
      return;
    }
    if (StashNativeCard.isInspectableWebViewsEnabled()) {
      try {
        WebView.setWebContentsDebuggingEnabled(true);
      } catch (Throwable ignored) {
        // Never let inspection toggling crash checkout.
      }
    }
    webView.setOverScrollMode(View.OVER_SCROLL_NEVER);
    WebSettings settings = webView.getSettings();
    settings.setAllowFileAccess(false);
    settings.setAllowContentAccess(false);
    
    settings.setJavaScriptEnabled(true);
    settings.setDomStorageEnabled(true);
    settings.setLoadWithOverviewMode(true);
    settings.setUseWideViewPort(true);
    settings.setBuiltInZoomControls(false);
    settings.setDisplayZoomControls(false);
    settings.setSupportZoom(false);
    
    CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true);
    CookieManager.getInstance().setAcceptCookie(true);
    
    boolean algorithmicDarkeningApplied = false;
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      try {
        if (WebViewFeature.isFeatureSupported(WebViewFeature.ALGORITHMIC_DARKENING)) {
          WebSettingsCompat.setAlgorithmicDarkeningAllowed(settings, isDarkTheme);
          algorithmicDarkeningApplied = true;
        }
      } catch (NoClassDefFoundError unused) {
        // androidx.webkit not packaged (e.g. AAR-only Unity); fall back to WebSettings#setForceDark.
      }
    }
    if (!algorithmicDarkeningApplied && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      settings.setForceDark(isDarkTheme ? WebSettings.FORCE_DARK_ON : WebSettings.FORCE_DARK_OFF);
    }
  }

  /**
   * Validates and normalizes a URL for {@code window.stash_sdk.openExternalBrowser(url)}: {@code http} or
   * {@code https} only. Trims input; prepends {@code https://} when no scheme is present.
   *
   * @return canonical URL string, or {@code null} if invalid
   */
  public static String normalizeExternalPaymentUrl(String raw) {
    if (raw == null) {
      return null;
    }
    String s = raw.trim();
    if (s.isEmpty()) {
      return null;
    }
    String lower = s.toLowerCase();
    if (lower.startsWith("javascript:") || lower.startsWith("file:") || lower.startsWith("data:")) {
      return null;
    }
    if (!s.startsWith("http://") && !s.startsWith("https://")) {
      s = "https://" + s;
    }
    try {
      Uri uri = Uri.parse(s);
      String scheme = uri.getScheme();
      if (scheme == null) {
        return null;
      }
      scheme = scheme.toLowerCase();
      if (!"http".equals(scheme) && !"https".equals(scheme)) {
        return null;
      }
      if (uri.getHost() == null || uri.getHost().isEmpty()) {
        return null;
      }
      return uri.toString();
    } catch (Exception e) {
      Log.w(TAG, "normalizeExternalPaymentUrl: " + e.getMessage());
      return null;
    }
  }

  public static String appendThemeQueryParameter(String url, boolean isDarkTheme) {
    if (url == null || url.isEmpty()) {
      return url;
    }
    // Idempotent: drop any pre-existing theme param first so re-theming (or a merchant URL that
    // already carries theme=) yields exactly one value. Matches iOS replace semantics.
    String base = stripThemeQueryParameter(url);
    String theme = isDarkTheme ? THEME_DARK : THEME_LIGHT;
    try {
      Uri uri = Uri.parse(base);
      Uri.Builder builder = uri.buildUpon();
      builder.appendQueryParameter(QUERY_PARAM_THEME, theme);
      return builder.build().toString();
    } catch (Exception e) {
      Log.w(TAG, "Error appending theme parameter: " + e.getMessage());
      String fragment = "";
      String head = base;
      int hash = base.indexOf('#');
      if (hash >= 0) {
        fragment = base.substring(hash);
        head = base.substring(0, hash);
      }
      String separator = head.contains("?") ? "&" : "?";
      return head + separator + QUERY_PARAM_THEME + "=" + theme + fragment;
    }
  }

  /** Removes every theme=... query segment (exact key match), preserving order and fragment. */
  private static String stripThemeQueryParameter(String url) {
    int hash = url.indexOf('#');
    String fragment = hash >= 0 ? url.substring(hash) : "";
    String head = hash >= 0 ? url.substring(0, hash) : url;
    int q = head.indexOf('?');
    if (q < 0) {
      return url;
    }
    String path = head.substring(0, q);
    String query = head.substring(q + 1);
    StringBuilder kept = new StringBuilder();
    for (String seg : query.split("&")) {
      if (seg.isEmpty()) {
        continue;
      }
      int eq = seg.indexOf('=');
      String key = eq >= 0 ? seg.substring(0, eq) : seg;
      if (key.equals(QUERY_PARAM_THEME)) {
        continue;
      }
      if (kept.length() > 0) {
        kept.append('&');
      }
      kept.append(seg);
    }
    String rebuilt = kept.length() > 0 ? path + "?" + kept : path;
    return rebuilt + fragment;
  }

  /**
   * Returns the background color for the current theme.
   *
   * @param context context to check theme
   * @return color (white or dark)
   */
  public static int getThemeBackgroundColor(Context context) {
    if (context == null) {
      return Color.WHITE;
    }
    return isDarkTheme(context) ? Color.parseColor(COLOR_DARK_BG) : Color.WHITE;
  }

  /**
   * Creates and shows a loading view (full-cover container with spinner).
   *
   * @param context context
   * @param container parent to add the loading view to
   * @return the loading container view, or null on error
   */
  public static View createAndShowLoadingView(Context context, ViewGroup container) {
    if (context == null || container == null) {
      return null;
    }
    boolean isDark = isDarkTheme(context);
    int bg = isDark ? Color.parseColor(COLOR_DARK_BG) : Color.WHITE;
    int accent = isDark ? Color.WHITE : Color.DKGRAY;
    return createAndShowLoadingView(context, container, bg, accent);
  }

  /**
   * Full-card loading overlay with explicit background and spinner accent (e.g. custom Stash Pay).
   */
  public static View createAndShowLoadingView(Context context, ViewGroup container,
      int backgroundArgb, int spinnerAccentArgb) {
    if (context == null || container == null) {
      return null;
    }

    try {
      FrameLayout loadingContainer = new FrameLayout(context);
      loadingContainer.setBackgroundColor(backgroundArgb);
      FrameLayout.LayoutParams containerParams = new FrameLayout.LayoutParams(
          FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
      loadingContainer.setLayoutParams(containerParams);

      ProgressBar loadingIndicator = new ProgressBar(context);
      loadingIndicator.setIndeterminate(true);
      loadingIndicator.setIndeterminateTintList(
          android.content.res.ColorStateList.valueOf(spinnerAccentArgb));

      FrameLayout.LayoutParams spinnerParams = new FrameLayout.LayoutParams(
          dpToPx(context, CardConstants.LOADING_INDICATOR_SIZE_DP),
          dpToPx(context, CardConstants.LOADING_INDICATOR_SIZE_DP));
      spinnerParams.gravity = Gravity.CENTER;
      loadingIndicator.setLayoutParams(spinnerParams);

      loadingContainer.addView(loadingIndicator);
      container.addView(loadingContainer);
      loadingContainer.bringToFront();

      return loadingContainer;
    } catch (Exception e) {
      Log.w(TAG, "Error showing loading: " + e.getMessage());
      return null;
    }
  }

  /**
   * Hides and removes the loading indicator with optional animation.
   *
   * @param loadingIndicator the progress bar to hide
   */
  public static void hideLoading(final ProgressBar loadingIndicator) {
    if (loadingIndicator == null) {
      return;
    }
    
    loadingIndicator.animate()
        .alpha(0.0f)
        .setDuration(CardConstants.ANIMATION_DURATION_POPUP)
        .withEndAction(() -> {
          if (loadingIndicator.getParent() != null) {
            ((ViewGroup) loadingIndicator.getParent()).removeView(loadingIndicator);
          }
        })
        .start();
  }

  /** Removes full-screen loading container from {@link #createAndShowLoadingView} (modal/popup path). */
  public static void hideLoadingOverlay(final View loadingView) {
    if (loadingView == null) {
      return;
    }
    loadingView.animate()
        .alpha(0.0f)
        .setDuration(CardConstants.ANIMATION_DURATION_POPUP)
        .withEndAction(() -> {
          if (loadingView.getParent() != null) {
            ((ViewGroup) loadingView.getParent()).removeView(loadingView);
          }
        })
        .start();
  }

  /**
   * Opens the URL using Custom Tabs when possible, else system browser.
   * Uses request code 0 (no {@code startActivityForResult}); use {@link StashUrlLauncher#openExternalUrl}
   * with {@link CardConstants#REQUEST_CODE_STASH_CUSTOM_TAB} when integrating {@link
   * StashNativeCard#onActivityResult}.
   */
  public static void openInSystemBrowser(Activity activity, String url) {
    if (activity == null || url == null || url.isEmpty()) {
      return;
    }
    StashUrlLauncher.openExternalUrl(activity, url, 0);
  }
}
