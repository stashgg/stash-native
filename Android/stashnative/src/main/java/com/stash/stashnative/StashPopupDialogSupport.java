package com.stash.stashnative;

import android.app.Activity;
import android.app.Dialog;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Outline;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewOutlineProvider;
import android.view.ViewTreeObserver;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.WebChromeClient;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import androidx.annotation.RequiresApi;
import java.lang.ref.WeakReference;

/**
 * Popup/modal Dialog presentation for {@link StashNativeCardPlugin}: dialog + container
 * construction, WebView setup and clients, loading overlay, rotation resize, and size
 * computation. State lives on the plugin.
 */
final class StashPopupDialogSupport {
  private static final String TAG = "StashNativeCard";

  private StashPopupDialogSupport() {}

  private static class PopupOrientationListener implements ViewTreeObserver.OnGlobalLayoutListener {
    private final WeakReference<Activity> activityRef;
    private final StashNativeCardPlugin plugin;

    PopupOrientationListener(Activity activity, StashNativeCardPlugin plugin) {
      this.activityRef = new WeakReference<>(activity);
      this.plugin = plugin;
    }

    @Override
    public void onGlobalLayout() {
      try {
        Activity activity = activityRef.get();
        if (plugin.currentContainer != null && plugin.currentDialog != null && plugin.currentDialog.isShowing()
            && activity != null) {
          int currentOrientation = activity.getResources().getConfiguration().orientation;

          if (currentOrientation != plugin.lastOrientation
              && currentOrientation != Configuration.ORIENTATION_UNDEFINED) {
            plugin.lastOrientation = currentOrientation;

            try {
              int[] newDimensions;
              if (plugin.useModalPresentation) {
                newDimensions = calculateModalDimensions(plugin, activity);
              } else {
                newDimensions = calculatePopupDimensions(plugin, activity);
              }
              FrameLayout.LayoutParams params =
                  (FrameLayout.LayoutParams) plugin.currentContainer.getLayoutParams();

              plugin.currentContainer.animate()
                  .scaleX(0.95f)
                  .scaleY(0.95f)
                  .setDuration(100)
                  .withEndAction(() -> {
                    try {
                      params.width = newDimensions[0];
                      params.height = newDimensions[1];
                      plugin.currentContainer.setLayoutParams(params);
                      plugin.currentContainer.animate()
                          .scaleX(1.0f)
                          .scaleY(1.0f)
                          .setDuration(200)
                          .start();
                    } catch (Exception e) {
                      Log.d(TAG, "Error in animation end action: " + e.getMessage(), e);
                    }
                  })
                  .start();
            } catch (Exception e) {
              Log.d(TAG, "Error calculating or applying dimensions: " + e.getMessage(), e);
            }
          }
        }
      } catch (Exception e) {
        Log.d(TAG, "Error in onGlobalLayout: " + e.getMessage(), e);
      }
    }
  }

  static void createAndShowPopupDialog(StashNativeCardPlugin plugin, String url, final Activity activity) {
    if (activity == null || url == null || url.isEmpty()) {
      Log.e(TAG, "Invalid activity or URL in createAndShowPopupDialog");
      return;
    }

    boolean preserveUseCustomSize = plugin.useCustomSize;
    plugin.cleanupAllViews();
    plugin.useCustomSize = preserveUseCustomSize;
    plugin.paymentSuccessHandled = false;

    try {
      plugin.currentDialog = new Dialog(activity, android.R.style.Theme_Translucent_NoTitleBar_Fullscreen);
      plugin.currentDialog.requestWindowFeature(Window.FEATURE_NO_TITLE);

      FrameLayout mainFrame = new FrameLayout(activity);
      try {
        mainFrame.setBackgroundColor(Color.parseColor(StashWebViewUtils.COLOR_BACKGROUND_DIM));
      } catch (Exception e) {
        Log.d(TAG, "Error setting background color: " + e.getMessage(), e);
        mainFrame.setBackgroundColor(Color.parseColor(CardConstants.COLOR_BACKGROUND_DIM));
      }

      mainFrame.setOnClickListener(v -> {
        try {
          if (!plugin.isPurchaseProcessing && plugin.currentDialog != null && plugin.currentDialog.isShowing()
              && v == mainFrame) {
            plugin.currentDialog.dismiss();
          }
        } catch (Exception e) {
          Log.d(TAG, "Error in click handler: " + e.getMessage(), e);
        }
      });

      int[] dimensions;
      try {
        dimensions = calculatePopupDimensions(plugin, activity);
      } catch (Exception e) {
        Log.d(TAG, "Error calculating dimensions: " + e.getMessage(), e);
        DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
        dimensions = new int[]{
          (int) (metrics.widthPixels * 0.9f),
          (int) (metrics.heightPixels * 0.7f)
        };
      }

      plugin.currentContainer = new FrameLayout(activity);
      FrameLayout.LayoutParams containerParams = new FrameLayout.LayoutParams(
          dimensions[0], dimensions[1]);
      containerParams.gravity = Gravity.CENTER;
      plugin.currentContainer.setLayoutParams(containerParams);

      try {
        plugin.lastOrientation = activity.getResources().getConfiguration().orientation;
      } catch (Exception e) {
        Log.d(TAG, "Error getting orientation: " + e.getMessage(), e);
        plugin.lastOrientation = Configuration.ORIENTATION_PORTRAIT;
      }

      plugin.orientationChangeListener = new PopupOrientationListener(activity, plugin);
      try {
        mainFrame.getViewTreeObserver().addOnGlobalLayoutListener(plugin.orientationChangeListener);
      } catch (Exception e) {
        Log.d(TAG, "Error adding layout listener: " + e.getMessage(), e);
      }

      try {
        GradientDrawable popupBg = new GradientDrawable();
        popupBg.setColor(StashWebViewUtils.getThemeBackgroundColor(activity));
        float radius = StashWebViewUtils.dpToPx(activity, (int) CardConstants.CORNER_RADIUS_DP);
        popupBg.setCornerRadius(radius);
        plugin.currentContainer.setBackground(popupBg);

        plugin.currentContainer.setElevation(
            StashWebViewUtils.dpToPx(activity, (int) CardConstants.ELEVATION_DP));
        plugin.currentContainer.setOutlineProvider(new ViewOutlineProvider() {
          @Override
          public void getOutline(View view, Outline outline) {
            try {
              outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), radius);
            } catch (Exception e) {
              Log.d(TAG, "Error setting outline: " + e.getMessage(), e);
            }
          }
        });
        plugin.currentContainer.setClipToOutline(true);
      } catch (Exception e) {
        Log.d(TAG, "Error setting container background: " + e.getMessage(), e);
      }

      try {
        try {
          plugin.webView = new WebView(activity);
        } catch (Throwable t) {
          // WebView init can fail in separate processes or broken Chromium installs.
          Log.e(TAG, "WebView creation failed: " + t.getMessage(), t);
          StashNativeCard.StashNativeCardListener l = plugin.listener;
          if (l != null) l.onNetworkError();
          plugin.cleanupAllViews();
          return;
        }
        FrameLayout.LayoutParams webViewParams = new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
        plugin.webView.setLayoutParams(webViewParams);
        plugin.currentContainer.addView(plugin.webView);

        setupPopupWebView(plugin, plugin.webView, url, activity);
      } catch (Exception e) {
        Log.w(TAG, "Error creating WebView: " + e.getMessage(), e);
        plugin.cleanupAllViews();
        return;
      }

      mainFrame.addView(plugin.currentContainer);
      plugin.currentDialog.setContentView(mainFrame);

      Window window = plugin.currentDialog.getWindow();
      if (window != null) {
        try {
          window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT,
              ViewGroup.LayoutParams.MATCH_PARENT);
          window.setFlags(WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
              WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED);
          // Resize the centered popup when the soft keyboard appears so the focused field stays
          // visible. This Dialog is a normal (non edge-to-edge) window, so adjustResize works.
          window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
          window.setBackgroundDrawableResource(android.R.color.transparent);
          window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
          WindowManager.LayoutParams windowParams = window.getAttributes();
          windowParams.dimAmount = CardConstants.OVERLAY_ALPHA;
          window.setAttributes(windowParams);
          StashWebViewUtils.applySystemBarAppearance(
              window, window.getDecorView(), StashWebViewUtils.isDarkTheme(activity));
        } catch (Exception e) {
          Log.d(TAG, "Error configuring window: " + e.getMessage(), e);
        }
      }

      plugin.currentContainer.setOnClickListener(v -> {});

      plugin.currentDialog.setCanceledOnTouchOutside(!plugin.isPurchaseProcessing);
      plugin.currentDialog.setCancelable(!plugin.isPurchaseProcessing);

      plugin.currentDialog.setOnDismissListener(dialog -> {
        try {
          StashNativeCard.StashNativeCardListener l = plugin.getListener();
          if (!plugin.paymentSuccessHandled && l != null) {
            l.onDialogDismissed();
          }
        } catch (Exception e) {
          Log.d(TAG, "Error in dismiss listener: " + e.getMessage(), e);
        }
        plugin.cleanupAllViews();
        plugin.presentationUsesIsolatedWebviewProcess = false;
        plugin.isCurrentlyPresented = false;
      });

      try {
        plugin.currentDialog.show();
        animateFadeIn(plugin);
        plugin.presentationUsesIsolatedWebviewProcess = false;
        plugin.isCurrentlyPresented = true;
      } catch (Exception e) {
        Log.w(TAG, "Error showing dialog: " + e.getMessage(), e);
        plugin.cleanupAllViews();
      }
    } catch (Exception e) {
      Log.w(TAG, "Error creating popup: " + e.getMessage(), e);
      plugin.cleanupAllViews();
    }
  }

  static void animateFadeIn(StashNativeCardPlugin plugin) {
    try {
      if (plugin.currentContainer != null) {
        plugin.currentContainer.setAlpha(0.0f);
        plugin.currentContainer.setScaleX(0.9f);
        plugin.currentContainer.setScaleY(0.9f);
        plugin.currentContainer.animate()
            .alpha(1.0f)
            .scaleX(1.0f)
            .scaleY(1.0f)
            .setDuration(CardConstants.ANIMATION_DURATION_POPUP)
            .setInterpolator(new android.view.animation.AccelerateDecelerateInterpolator())
            .start();
      }
    } catch (Exception e) {
      Log.d(TAG, "Error in animateFadeIn: " + e.getMessage(), e);
    }
  }

  static void dismissPopupDialog(StashNativeCardPlugin plugin) {
    try {
      if (plugin.currentDialog != null && plugin.currentContainer != null) {
        plugin.currentContainer.animate()
            .alpha(0.0f)
            .scaleX(0.9f)
            .scaleY(0.9f)
            .setDuration(CardConstants.ANIMATION_DURATION_FAST)
            .setInterpolator(new SpringInterpolator())
            .withEndAction(() -> {
              try {
                if (plugin.currentDialog != null) {
                  plugin.currentDialog.dismiss();
                }
              } catch (Exception e) {
                Log.d(TAG, "Error dismissing dialog in animation: " + e.getMessage(), e);
              }
            })
            .start();
      } else if (plugin.currentDialog != null) {
        plugin.currentDialog.dismiss();
      }
    } catch (Exception e) {
      Log.d(TAG, "Error in dismissPopupDialog: " + e.getMessage(), e);
      try {
        if (plugin.currentDialog != null) {
          plugin.currentDialog.dismiss();
        }
      } catch (Exception e2) {
        Log.d(TAG, "Error force dismissing dialog: " + e2.getMessage(), e2);
      }
    }
  }

  /**
   * Chromium/WebView renderer crashed or was killed. Remove UI and notify the host; returning
   * {@code true} from {@link WebViewClient#onRenderProcessGone} prevents the default behavior of
   * tearing down the app process (API 26+).
   */
  @RequiresApi(Build.VERSION_CODES.O)
  static void handleWebViewRenderProcessGone(StashNativeCardPlugin plugin, RenderProcessGoneDetail detail) {
    Log.e(TAG, "WebView render process gone (didCrash=" + detail.didCrash() + ")");
    try {
      if (plugin.currentDialog != null) {
        try {
          plugin.currentDialog.setOnDismissListener(null);
        } catch (Exception e) {
          Log.d(TAG, "Error clearing dismiss listener: " + e.getMessage(), e);
        }
      }
      plugin.cleanupAllViews();
      plugin.presentationUsesIsolatedWebviewProcess = false;
      plugin.isCurrentlyPresented = false;
      StashNativeCard.StashNativeCardListener l = plugin.getListener();
      if (l != null) {
        l.onNetworkError();
      }
    } catch (Exception e) {
      Log.w(TAG, "Error recovering from render process gone: " + e.getMessage(), e);
    }
  }

  static int dialogSheetBackgroundArgb(StashNativeCardPlugin plugin, Activity activity) {
    if (plugin.useModalPresentation && plugin.currentModalConfig != null) {
      Integer c = StashBackgroundColorUtils.parseSolidColorOrNull(plugin.currentModalConfig.backgroundColor);
      if (c != null) {
        return c;
      }
    }
    return StashWebViewUtils.getThemeBackgroundColor(activity);
  }

  static boolean dialogEffectiveDarkForWeb(StashNativeCardPlugin plugin, Activity activity) {
    if (plugin.useModalPresentation && plugin.currentModalConfig != null) {
      Integer c = StashBackgroundColorUtils.parseSolidColorOrNull(plugin.currentModalConfig.backgroundColor);
      if (c != null) {
        return StashBackgroundColorUtils.isDarkBackground(c);
      }
    }
    return StashWebViewUtils.isDarkTheme(activity);
  }

  static void setupPopupWebView(StashNativeCardPlugin plugin, WebView webView, String url, final Activity activity) {
    if (webView == null || activity == null || url == null || url.isEmpty()) {
      Log.e(TAG, "Invalid parameters in setupPopupWebView");
      return;
    }

    final int sheetBg = dialogSheetBackgroundArgb(plugin, activity);
    final boolean effDark = dialogEffectiveDarkForWeb(plugin, activity);

    try {
      StashWebViewUtils.configureWebViewSettings(webView, effDark);
    } catch (Exception e) {
      Log.d(TAG, "Error configuring WebView settings: " + e.getMessage(), e);
    }

    webView.setWebViewClient(new WebViewClient() {
      @Override
      public boolean shouldOverrideUrlLoading(WebView view, android.webkit.WebResourceRequest request) {
        if (!request.isForMainFrame()) {
          return false;
        }
        return handleDeeplinkNavigation(
            plugin, activity, request.getUrl() != null ? request.getUrl().toString() : null);
      }

      @Override
      @SuppressWarnings("deprecation")
      public boolean shouldOverrideUrlLoading(WebView view, String url) {
        return handleDeeplinkNavigation(plugin, activity, url);
      }

      @Override
      public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
        try {
          super.onPageStarted(view, url, favicon);
          plugin.pageLoadStartTime = System.currentTimeMillis();
          showLoadingIndicator(plugin, activity);
          injectStashSDKFunctions(plugin);
        } catch (Exception e) {
          Log.d(TAG, "Error in onPageStarted: " + e.getMessage(), e);
        }
      }

      @Override
      public void onPageFinished(WebView view, String url) {
        try {
          super.onPageFinished(view, url);

          if (plugin.pageLoadStartTime > 0) {
            long loadTimeMs = System.currentTimeMillis() - plugin.pageLoadStartTime;
            try {
              StashNativeCard.StashNativeCardListener l = plugin.getListener();
              if (l != null) {
                l.onPageLoaded(loadTimeMs);
              }
            } catch (Exception e) {
              Log.d(TAG, "Error sending page loaded message: " + e.getMessage(), e);
            }
            plugin.pageLoadStartTime = 0;
          }

          injectStashSDKFunctions(plugin);
          plugin.pendingHideLoadingRunnable = () -> {
            try {
              hideLoadingIndicator(plugin, activity);
              view.setVisibility(View.VISIBLE);
            } catch (Exception e) {
              Log.d(TAG, "Error in delayed page finished handler: " + e.getMessage(), e);
            }
          };
          view.postDelayed(plugin.pendingHideLoadingRunnable, CardConstants.HIDE_LOADING_DELAY_MS);
        } catch (Exception e) {
          Log.d(TAG, "Error in onPageFinished: " + e.getMessage(), e);
        }
      }

      @Override
      public void onReceivedError(WebView view, android.webkit.WebResourceRequest request,
          android.webkit.WebResourceError error) {
        try {
          super.onReceivedError(view, request, error);
          if (error != null) {
            Log.e(TAG, "WebView error: " + error.getDescription());
          }
        } catch (Exception e) {
          Log.d(TAG, "Error in onReceivedError: " + e.getMessage(), e);
        }
      }

      @Override
      @RequiresApi(Build.VERSION_CODES.O)
      public boolean onRenderProcessGone(WebView view, RenderProcessGoneDetail detail) {
        handleWebViewRenderProcessGone(plugin, detail);
        return true;
      }
    });

    try {
      webView.setWebChromeClient(new WebChromeClient());
      webView.addJavascriptInterface(new StashPopupJsInterface(plugin),
          StashWebViewUtils.JS_INTERFACE_NAME);
      webView.setVerticalScrollBarEnabled(false);
      webView.setHorizontalScrollBarEnabled(false);
      webView.setBackgroundColor(sheetBg);
      // Show loading immediately before loadUrl() so there is never a blank-container window
      // between addView() and the first onPageStarted callback.
      if (plugin.currentContainer != null && plugin.loadingOverlayView == null) {
        plugin.loadingOverlayView = StashWebViewUtils.createAndShowLoadingView(activity, plugin.currentContainer,
            sheetBg, StashBackgroundColorUtils.spinnerAccentFor(sheetBg));
      }
      String urlThemed = url;
      try {
        urlThemed = StashWebViewUtils.appendThemeQueryParameter(url, effDark);
      } catch (Exception e) {
        Log.d(TAG, "Error appending theme parameter: " + e.getMessage(), e);
      }
      webView.loadUrl(urlThemed);
    } catch (Exception e) {
      Log.w(TAG, "Error setting up WebView: " + e.getMessage(), e);
      plugin.cleanupAllViews();
    }
  }

  /** Popup counterpart of StashCheckoutWebViewSupport.handleDeeplinkNavigation. */
  static boolean handleDeeplinkNavigation(
      StashNativeCardPlugin plugin, Activity activity, String url) {
    if (url == null || StashWebViewUtils.isWebScheme(url)) {
      return false;
    }
    int result = StashWebViewUtils.classifyDeeplinkResult(url);
    StashPopupJsInterface bridge = new StashPopupJsInterface(plugin);
    if (result == StashWebViewUtils.DEEPLINK_RESULT_SUCCESS) {
      bridge.onPaymentSuccess(null);
    } else if (result == StashWebViewUtils.DEEPLINK_RESULT_FAILURE) {
      bridge.onPaymentFailure();
    } else if (result == StashWebViewUtils.DEEPLINK_RESULT_CANCEL) {
      bridge.requestCloseFromPage();
    } else {
      StashCheckoutWebViewSupport.openDeeplinkExternally(activity, url);
    }
    return true;
  }

  static void injectStashSDKFunctions(StashNativeCardPlugin plugin) {
    if (plugin.webView == null) {
      return;
    }

    try {
      plugin.webView.evaluateJavascript(StashWebViewUtils.JS_SDK_SCRIPT, null);
    } catch (Exception e) {
      Log.d(TAG, "Error injecting SDK functions: " + e.getMessage(), e);
    }
  }

  static void showLoadingIndicator(StashNativeCardPlugin plugin, Activity activity) {
    if (plugin.currentContainer == null || activity == null) {
      return;
    }
    try {
      activity.runOnUiThread(() -> {
        try {
          // Idempotent: if already attached (pre-created before loadUrl) just bring to front.
          if (plugin.loadingOverlayView != null && plugin.loadingOverlayView.getParent() != null) {
            plugin.loadingOverlayView.setVisibility(View.VISIBLE);
            plugin.loadingOverlayView.bringToFront();
            return;
          }
          int sheetBg = dialogSheetBackgroundArgb(plugin, activity);
          plugin.loadingOverlayView = StashWebViewUtils.createAndShowLoadingView(activity, plugin.currentContainer,
              sheetBg, StashBackgroundColorUtils.spinnerAccentFor(sheetBg));
        } catch (Exception e) {
          Log.d(TAG, "Error showing loading indicator: " + e.getMessage(), e);
        }
      });
    } catch (Exception e) {
      Log.d(TAG, "Error scheduling loading indicator: " + e.getMessage(), e);
    }
  }

  static void hideLoadingIndicator(StashNativeCardPlugin plugin, Activity activity) {
    if (plugin.loadingOverlayView == null || activity == null) {
      return;
    }
    try {
      activity.runOnUiThread(() -> {
        try {
          StashWebViewUtils.hideLoadingOverlay(plugin.loadingOverlayView);
          plugin.loadingOverlayView = null;
        } catch (Exception e) {
          Log.d(TAG, "Error hiding loading indicator: " + e.getMessage(), e);
          plugin.loadingOverlayView = null;
        }
      });
    } catch (Exception e) {
      Log.d(TAG, "Error scheduling hide loading indicator: " + e.getMessage(), e);
    }
  }

  static int[] calculatePopupDimensions(StashNativeCardPlugin plugin, Activity activity) {
    if (activity == null) {
      Log.e(TAG, "Activity is null in calculatePopupDimensions");
      return new int[]{CardConstants.FALLBACK_POPUP_WIDTH, CardConstants.FALLBACK_POPUP_HEIGHT};
    }

    try {
      DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
      boolean isLandscape = activity.getResources().getConfiguration().orientation
          == Configuration.ORIENTATION_LANDSCAPE;

      int smallerDimension = Math.min(metrics.widthPixels, metrics.heightPixels);
      boolean isTablet = StashWebViewUtils.isTablet(activity);
      float sizeRatio = isTablet
          ? CardConstants.POPUP_SIZE_RATIO_TABLET
          : CardConstants.POPUP_SIZE_RATIO_PHONE;
      int minSize = isTablet
          ? StashWebViewUtils.dpToPx(activity, (int) CardConstants.MIN_TABLET_CARD_WIDTH_DP)
          : StashWebViewUtils.dpToPx(activity, (int) CardConstants.MIN_PHONE_CARD_WIDTH_DP);
      int maxSize = StashWebViewUtils.dpToPx(activity,
          (int) CardConstants.MIN_TABLET_CARD_HEIGHT_DP);
      int baseSize = Math.max(minSize, Math.min(maxSize, (int) (smallerDimension * sizeRatio)));

      float widthMultiplier = isLandscape
          ? (plugin.useCustomSize ? plugin.customLandscapeWidthMultiplier
              : CardConstants.POPUP_LANDSCAPE_WIDTH_MULTIPLIER)
          : (plugin.useCustomSize ? plugin.customPortraitWidthMultiplier
              : CardConstants.POPUP_PORTRAIT_WIDTH_MULTIPLIER);
      float heightMultiplier = isLandscape
          ? (plugin.useCustomSize ? plugin.customLandscapeHeightMultiplier
              : CardConstants.POPUP_LANDSCAPE_HEIGHT_MULTIPLIER)
          : (plugin.useCustomSize ? plugin.customPortraitHeightMultiplier
              : CardConstants.POPUP_PORTRAIT_HEIGHT_MULTIPLIER);

      int popupWidth = (int) (baseSize * widthMultiplier);
      int popupHeight = (int) (baseSize * heightMultiplier);

      return new int[]{popupWidth, popupHeight};
    } catch (Exception e) {
      Log.d(TAG, "Error calculating popup dimensions: " + e.getMessage(), e);
      try {
        DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
        return new int[]{
          (int) (metrics.widthPixels * 0.9f),
          (int) (metrics.heightPixels * 0.7f)
        };
      } catch (Exception e2) {
        Log.d(TAG, "Error getting fallback dimensions: " + e2.getMessage(), e2);
        return new int[]{CardConstants.FALLBACK_POPUP_WIDTH, CardConstants.FALLBACK_POPUP_HEIGHT};
      }
    }
  }

  static int[] calculateModalDimensions(StashNativeCardPlugin plugin, Activity activity) {
    if (activity == null || plugin.currentModalConfig == null) {
      Log.e(TAG, "Activity or modal config is null in calculateModalDimensions");
      return new int[]{CardConstants.FALLBACK_POPUP_WIDTH, CardConstants.FALLBACK_POPUP_HEIGHT};
    }

    try {
      DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
      int screenWidth = metrics.widthPixels;
      int screenHeight = metrics.heightPixels;
      boolean isLandscape = screenWidth > screenHeight;
      boolean isTablet = StashWebViewUtils.isTablet(activity);

      float widthRatio;
      float heightRatio;
      if (isTablet) {
        widthRatio = isLandscape
            ? plugin.currentModalConfig.tabletWidthRatioLandscape
            : plugin.currentModalConfig.tabletWidthRatioPortrait;
        heightRatio = isLandscape
            ? plugin.currentModalConfig.tabletHeightRatioLandscape
            : plugin.currentModalConfig.tabletHeightRatioPortrait;
      } else {
        widthRatio = isLandscape
            ? plugin.currentModalConfig.phoneWidthRatioLandscape
            : plugin.currentModalConfig.phoneWidthRatioPortrait;
        heightRatio = isLandscape
            ? plugin.currentModalConfig.phoneHeightRatioLandscape
            : plugin.currentModalConfig.phoneHeightRatioPortrait;
      }

      int cardWidth = (int) (screenWidth * widthRatio);
      int cardHeight = (int) (screenHeight * heightRatio);

      int minWidthPx = isTablet
          ? StashWebViewUtils.dpToPx(activity, (int) CardConstants.MIN_TABLET_CARD_WIDTH_DP)
          : StashWebViewUtils.dpToPx(activity, (int) CardConstants.MIN_PHONE_CARD_WIDTH_DP);
      int minHeightPx = isTablet
          ? StashWebViewUtils.dpToPx(activity, (int) CardConstants.MIN_TABLET_CARD_HEIGHT_DP)
          : StashWebViewUtils.dpToPx(activity, (int) CardConstants.MIN_PHONE_CARD_WIDTH_DP);

      if (cardWidth < minWidthPx) {
        cardWidth = minWidthPx;
      }
      if (cardHeight < minHeightPx) {
        cardHeight = minHeightPx;
      }

      return new int[]{cardWidth, cardHeight};
    } catch (Exception e) {
      Log.d(TAG, "Error calculating modal dimensions: " + e.getMessage(), e);
      try {
        DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
        return new int[]{
          (int) (metrics.widthPixels * 0.9f),
          (int) (metrics.heightPixels * 0.5f)
        };
      } catch (Exception e2) {
        Log.d(TAG, "Error getting fallback dimensions: " + e2.getMessage(), e2);
        return new int[]{CardConstants.FALLBACK_POPUP_WIDTH, CardConstants.FALLBACK_POPUP_HEIGHT};
      }
    }
  }
}
