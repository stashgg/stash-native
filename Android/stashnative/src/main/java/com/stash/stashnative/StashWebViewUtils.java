package com.stash.stashnative;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.res.Configuration;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.widget.FrameLayout;
import android.widget.ProgressBar;

/**
 * Utility class for WebView configuration and common operations.
 */
public class StashWebViewUtils {
  private static final String TAG = "StashWebViewUtils";

  /** JavaScript bridge name used by addJavascriptInterface and JS_SDK_SCRIPT. */
  public static final String JS_INTERFACE_NAME = "StashAndroid";
  
  /** Query param name for theme. */
  public static final String QUERY_PARAM_THEME = "theme";
  public static final String THEME_DARK = "dark";
  public static final String THEME_LIGHT = "light";
  
  /** Overlay dim (40% alpha). Must match CardConstants.COLOR_OVERLAY_DIM. */
  public static final String COLOR_BACKGROUND_DIM = CardConstants.COLOR_OVERLAY_DIM;
  public static final String COLOR_DARK_BG = "#1C1C1E";
  
  public static final String JS_SDK_SCRIPT = "(function() {"
      + "  window.stash_sdk = window.stash_sdk || {};"
      + "  window.stash_sdk.onPaymentSuccess = function(data) {"
      + "    try { "
      + JS_INTERFACE_NAME
      + ".onPaymentSuccess(); } catch(e) {}"
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
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      int nightModeFlags = context.getResources().getConfiguration().uiMode
          & Configuration.UI_MODE_NIGHT_MASK;
      return nightModeFlags == Configuration.UI_MODE_NIGHT_YES;
    }
    return false;
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
    
    boolean isTabletByConfig = false;
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB_MR2) {
      int screenSize = activity.getResources().getConfiguration().screenLayout
          & Configuration.SCREENLAYOUT_SIZE_MASK;
      isTabletByConfig = (screenSize == Configuration.SCREENLAYOUT_SIZE_LARGE
          || screenSize == Configuration.SCREENLAYOUT_SIZE_XLARGE);
    }
    
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
    
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
      CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true);
    }
    CookieManager.getInstance().setAcceptCookie(true);
    
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      settings.setForceDark(isDarkTheme ? WebSettings.FORCE_DARK_ON : WebSettings.FORCE_DARK_OFF);
    }
  }

  /**
   * Appends the theme query parameter to the URL.
   *
   * @param url URL to modify
   * @param isDarkTheme true for dark theme
   * @return URL with theme param, or original if null/empty
   */
  public static String appendThemeQueryParameter(String url, boolean isDarkTheme) {
    if (url == null || url.isEmpty()) {
      return url;
    }
    
    try {
      Uri uri = Uri.parse(url);
      Uri.Builder builder = uri.buildUpon();
      
      String theme = isDarkTheme ? THEME_DARK : THEME_LIGHT;
      builder.appendQueryParameter(QUERY_PARAM_THEME, theme);
      
      return builder.build().toString();
    } catch (Exception e) {
      Log.e(TAG, "Error appending theme parameter: " + e.getMessage());
      String separator = url.contains("?") ? "&" : "?";
      String theme = isDarkTheme ? THEME_DARK : THEME_LIGHT;
      return url + separator + QUERY_PARAM_THEME + "=" + theme;
    }
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
    
    try {
      boolean isDark = isDarkTheme(context);
      
      // Create background container that covers the entire card
      FrameLayout loadingContainer = new FrameLayout(context);
      loadingContainer.setBackgroundColor(isDark ? Color.parseColor(COLOR_DARK_BG) : Color.WHITE);
      FrameLayout.LayoutParams containerParams = new FrameLayout.LayoutParams(
          FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
      loadingContainer.setLayoutParams(containerParams);
      
      // Create spinner
      ProgressBar loadingIndicator = new ProgressBar(context);
      
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
        loadingIndicator.setLayerType(View.LAYER_TYPE_HARDWARE, null);
      }
      
      loadingIndicator.setIndeterminate(true);
      
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        loadingIndicator.setIndeterminateTintList(
            android.content.res.ColorStateList.valueOf(isDark ? Color.WHITE : Color.DKGRAY));
      }

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
      Log.e(TAG, "Error showing loading: " + e.getMessage());
      return null;
    }
  }
  
  /**
   * Creates and shows a loading spinner (deprecated; use createAndShowLoadingView).
   *
   * @param context context
   * @param container parent to add the spinner to
   * @return the progress bar, or null on error
   */
  @Deprecated
  public static ProgressBar createAndShowLoading(Context context, ViewGroup container) {
    if (context == null || container == null) {
      return null;
    }
    
    try {
      ProgressBar loadingIndicator = new ProgressBar(context);
      
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
        loadingIndicator.setLayerType(View.LAYER_TYPE_HARDWARE, null);
      }
      
      loadingIndicator.setIndeterminate(true);
      
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        loadingIndicator.setIndeterminateTintList(
            android.content.res.ColorStateList.valueOf(
                isDarkTheme(context) ? Color.WHITE : Color.DKGRAY));
      }
      
      int size = dpToPx(context, CardConstants.LOADING_INDICATOR_SIZE_DP);
      FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(size, size);
      params.gravity = Gravity.CENTER;
      loadingIndicator.setLayoutParams(params);
      
      container.addView(loadingIndicator);
      loadingIndicator.bringToFront();
      
      return loadingIndicator;
    } catch (Exception e) {
      Log.e(TAG, "Error showing loading: " + e.getMessage());
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
    
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
      loadingIndicator.animate()
          .alpha(0.0f)
          .setDuration(CardConstants.ANIMATION_DURATION_POPUP)
          .withEndAction(() -> {
            if (loadingIndicator.getParent() != null) {
              ((ViewGroup) loadingIndicator.getParent()).removeView(loadingIndicator);
            }
          })
          .start();
    } else {
      if (loadingIndicator.getParent() != null) {
        ((ViewGroup) loadingIndicator.getParent()).removeView(loadingIndicator);
      }
    }
  }

  // ============================================================================
  // Chrome Custom Tabs (reflection-based to avoid hard dependency)
  // ============================================================================

  private static final String CUSTOM_TABS_INTENT_CLASS =
      "androidx.browser.customtabs.CustomTabsIntent";
  private static final String CUSTOM_TABS_BUILDER_CLASS =
      "androidx.browser.customtabs.CustomTabsIntent$Builder";

  /**
   * Returns true if Chrome Custom Tabs is available on the device.
   */
  public static boolean isChromeCustomTabsAvailable(Context context) {
    if (context == null) {
      return false;
    }
    try {
      Class.forName(CUSTOM_TABS_INTENT_CLASS);
      return true;
    } catch (ClassNotFoundException e) {
      return false;
    }
  }

  /**
   * Opens the given URL in Chrome Custom Tabs using reflection.
   *
   * @throws Exception if Custom Tabs is not available or launch fails
   */
  public static void openWithChromeCustomTabs(Activity activity, String url) throws Exception {
    if (activity == null || url == null || url.isEmpty()) {
      throw new IllegalArgumentException("Invalid activity or URL");
    }

    Class<?> customTabsIntentClass = Class.forName(CUSTOM_TABS_INTENT_CLASS);
    Class<?> builderClass = Class.forName(CUSTOM_TABS_BUILDER_CLASS);

    Object builder = builderClass.getDeclaredConstructor().newInstance();
    java.lang.reflect.Method setToolbarColor = builderClass.getMethod("setToolbarColor", int.class);
    setToolbarColor.invoke(builder, Color.parseColor(CardConstants.COLOR_DARK_BG));

    java.lang.reflect.Method setShowTitle = builderClass.getMethod("setShowTitle", boolean.class);
    setShowTitle.invoke(builder, true);

    java.lang.reflect.Method build = builderClass.getMethod("build");
    Object customTabsIntent = build.invoke(builder);

    java.lang.reflect.Method launchUrl = customTabsIntentClass.getMethod("launchUrl",
        android.content.Context.class, Uri.class);
    launchUrl.invoke(customTabsIntent, activity, Uri.parse(url));
  }

  /**
   * Opens the given URL in the system default browser (fallback when Chrome Custom Tabs
   * is not available).
   */
  public static void openInSystemBrowser(Activity activity, String url) {
    if (activity == null || url == null || url.isEmpty()) {
      return;
    }
    try {
      Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
      activity.startActivity(intent);
    } catch (Exception e) {
      // Ignore if no browser can handle the URL
    }
  }
}
