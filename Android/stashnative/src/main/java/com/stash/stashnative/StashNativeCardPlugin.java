package com.stash.stashnative;

import android.animation.ValueAnimator;
import android.app.Activity;
import android.app.ActivityManager;
import android.app.Application;
import android.app.Dialog;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Outline;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.Surface;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewOutlineProvider;
import android.view.ViewTreeObserver;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.CookieManager;
import android.webkit.JavascriptInterface;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import androidx.annotation.RequiresApi;
import java.lang.ref.WeakReference;

/**
 * Internal plugin class that handles the WebView and dialog management.
 * Use {@link StashNativeCard} for the public API.
 *
 * <p>Memory optimization: Uses WeakReference for Activity to prevent leaks.
 */
public class StashNativeCardPlugin {
  private static final String TAG = "StashNativeCard";

  /** Thread-safe lazy singleton holder. */
  private static class Holder {
    static final StashNativeCardPlugin INSTANCE = new StashNativeCardPlugin();
  }
  
  // Use WeakReference to prevent Activity memory leaks
  private WeakReference<Activity> activityRef;
  private StashNativeCard.StashNativeCardListener listener;

  private Dialog currentDialog;
  private WebView webView;
  private FrameLayout currentContainer;
  private ProgressBar loadingIndicator;
  private ViewTreeObserver.OnGlobalLayoutListener orientationChangeListener;
  
  // Phone card: only height is configurable in portrait (full width);
  // landscape ratios when not forcing portrait
  private float cardHeightRatioPortrait = CardConstants.DEFAULT_CARD_HEIGHT_RATIO;
  private boolean forcePortraitOnCheckout = false;
  private float cardWidthRatioLandscape = CardConstants.DEFAULT_CARD_WIDTH_RATIO_LANDSCAPE;
  private float cardHeightRatioLandscape = CardConstants.DEFAULT_CARD_HEIGHT_RATIO_LANDSCAPE;
  
  // Orientation-specific tablet card configuration
  private float tabletWidthRatioPortrait = CardConstants.DEFAULT_TABLET_WIDTH_RATIO_PORTRAIT;
  private float tabletHeightRatioPortrait = CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_PORTRAIT;
  private float tabletWidthRatioLandscape = CardConstants.DEFAULT_TABLET_WIDTH_RATIO_LANDSCAPE;
  private float tabletHeightRatioLandscape = CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_LANDSCAPE;
  
  /** Accessed from UI and JS threads; volatile for visibility. */
  private volatile boolean isCurrentlyPresented;
  /** True while card checkout runs in {@link StashNativeCardPortraitActivity} ({@code :stash_webview}). */
  private volatile boolean presentationUsesIsolatedWebviewProcess;
  /** Accessed from UI and JS threads; volatile for visibility. */
  private volatile boolean paymentSuccessHandled;
  /** Accessed from UI and JS threads; volatile for visibility. */
  private volatile boolean isPurchaseProcessing;
  private boolean usePopupPresentation;
  private boolean useModalPresentation;
  private boolean useCheckoutOverlayPresentation;
  /** When true, checkout overlay (no force portrait) is expanded to ~95% height. */
  private boolean isCheckoutOverlayExpanded = false;
  private int lastOrientation = Configuration.ORIENTATION_UNDEFINED;
  
  // Modal configuration (used when useModalPresentation is true)
  private StashNativeCard.ModalConfig currentModalConfig;
  
  private boolean useCustomSize;
  private float customPortraitWidthMultiplier = CardConstants.POPUP_PORTRAIT_WIDTH_MULTIPLIER;
  private float customPortraitHeightMultiplier = CardConstants.POPUP_PORTRAIT_HEIGHT_MULTIPLIER;
  private float customLandscapeWidthMultiplier = CardConstants.POPUP_LANDSCAPE_WIDTH_MULTIPLIER;
  private float customLandscapeHeightMultiplier = CardConstants.POPUP_LANDSCAPE_HEIGHT_MULTIPLIER;
  
  private long pageLoadStartTime;

  private BroadcastReceiver checkoutBridgeReceiver;
  private boolean checkoutBridgeReceiverRegistered;
  private boolean checkoutHostLifecycleRegistered;

  private static boolean isStashWebviewProcessRunning(Context context) {
    try {
      ActivityManager am = (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
      if (am == null) {
        return false;
      }
      for (ActivityManager.RunningAppProcessInfo proc : am.getRunningAppProcesses()) {
        if (proc != null && proc.processName != null
            && proc.processName.endsWith(":stash_webview")) {
          return true;
        }
      }
    } catch (Exception e) {
      Log.e(TAG, "Error checking stash_webview process: " + e.getMessage(), e);
    }
    return false;
  }

  /**
   * If checkout ran in {@code :stash_webview} and that process died without sending a broadcast
   * (e.g. native Chromium abort), clear state and surface {@link
   * StashNativeCard.StashNativeCardListener#onNetworkError()} once the host activity resumes.
   */
  private void clearPresentationIfCheckoutProcessDied(Context context) {
    if (!presentationUsesIsolatedWebviewProcess || !isCurrentlyPresented || context == null) {
      return;
    }
    if (isStashWebviewProcessRunning(context)) {
      return;
    }
    presentationUsesIsolatedWebviewProcess = false;
    isCurrentlyPresented = false;
    StashNativeCard.StashNativeCardListener l = listener;
    if (l != null) {
      try {
        l.onNetworkError();
      } catch (Exception e) {
        Log.e(TAG, "Error notifying checkout process death: " + e.getMessage(), e);
      }
    }
  }

  private void ensureCheckoutHostLifecycle(Context context) {
    if (checkoutHostLifecycleRegistered || context == null) {
      return;
    }
    Context appCtx = context.getApplicationContext();
    if (!(appCtx instanceof Application)) {
      return;
    }
    Application app = (Application) appCtx;
    app.registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks() {
      @Override
      public void onActivityResumed(Activity activity) {
        Activity host = getActivity();
        if (host != null && activity == host) {
          clearPresentationIfCheckoutProcessDied(activity);
        }
      }

      @Override public void onActivityCreated(Activity a, Bundle b) {}

      @Override public void onActivityStarted(Activity a) {}

      @Override public void onActivityPaused(Activity a) {}

      @Override public void onActivityStopped(Activity a) {}

      @Override public void onActivitySaveInstanceState(Activity a, Bundle b) {}

      @Override public void onActivityDestroyed(Activity a) {}
    });
    checkoutHostLifecycleRegistered = true;
  }

  /**
   * Registers a package-local receiver so events from {@link StashNativeCardPortraitActivity}
   * (process {@code :stash_webview}) reach {@link StashNativeCard.StashNativeCardListener}.
   */
  private void ensureCheckoutBridgeReceiver(Context context) {
    if (checkoutBridgeReceiverRegistered || context == null) {
      return;
    }
    Context app = context.getApplicationContext();
    checkoutBridgeReceiver = new BroadcastReceiver() {
      @Override
      public void onReceive(Context receiverContext, Intent intent) {
        if (intent == null || intent.getAction() == null) {
          return;
        }
        final String action = intent.getAction();
        final Intent intentCopy = intent;
        new Handler(Looper.getMainLooper()).post(() -> dispatchCheckoutBridgeIntent(action, intentCopy));
      }
    };
    IntentFilter filter = new IntentFilter();
    filter.addAction(CardConstants.BROADCAST_CHECKOUT_PAYMENT_SUCCESS);
    filter.addAction(CardConstants.BROADCAST_CHECKOUT_PAYMENT_FAILURE);
    filter.addAction(CardConstants.BROADCAST_CHECKOUT_OPT_IN);
    filter.addAction(CardConstants.BROADCAST_CHECKOUT_NETWORK_ERROR);
    filter.addAction(CardConstants.BROADCAST_CHECKOUT_DIALOG_DISMISSED);
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        app.registerReceiver(checkoutBridgeReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
      } else {
        app.registerReceiver(checkoutBridgeReceiver, filter);
      }
      checkoutBridgeReceiverRegistered = true;
    } catch (Exception e) {
      Log.e(TAG, "Failed to register checkout bridge receiver: " + e.getMessage(), e);
    }
    ensureCheckoutHostLifecycle(context);
  }

  private void dispatchCheckoutBridgeIntent(String action, Intent intent) {
    StashNativeCard.StashNativeCardListener l = listener;
    try {
      if (CardConstants.BROADCAST_CHECKOUT_OPT_IN.equals(action)) {
        if (l != null) {
          String type = intent.getStringExtra(CardConstants.BROADCAST_EXTRA_OPTIN_TYPE);
          l.onOptInResponse(type != null ? type : "");
        }
        return;
      }
      presentationUsesIsolatedWebviewProcess = false;
      isCurrentlyPresented = false;
      if (l == null) {
        return;
      }
      if (CardConstants.BROADCAST_CHECKOUT_PAYMENT_SUCCESS.equals(action)) {
        l.onPaymentSuccess();
      } else if (CardConstants.BROADCAST_CHECKOUT_PAYMENT_FAILURE.equals(action)) {
        l.onPaymentFailure();
      } else if (CardConstants.BROADCAST_CHECKOUT_NETWORK_ERROR.equals(action)) {
        l.onNetworkError();
      } else if (CardConstants.BROADCAST_CHECKOUT_DIALOG_DISMISSED.equals(action)) {
        l.onDialogDismissed();
      }
    } catch (Exception e) {
      Log.e(TAG, "Error dispatching checkout bridge: " + e.getMessage(), e);
    }
  }
  
  /**
   * Runs the given runnable on the main thread if activity is available. No-op if activity is null.
   */
  private void runOnMainSafely(Runnable r) {
    Activity a = getActivity();
    if (a != null) {
      a.runOnUiThread(r);
    }
  }

  /**
   * Runs the given runnable on the main thread and then dismisses the current dialog.
   * Used by JS interface handlers to avoid duplicating post + listener + dismiss logic.
   */
  private void runOnMainAndDismiss(Runnable beforeDismiss) {
    new Handler(Looper.getMainLooper()).post(() -> {
      try {
        if (beforeDismiss != null) {
          beforeDismiss.run();
        }
        dismissCurrentDialog();
      } catch (Exception e) {
        Log.e(TAG, "Error in runOnMainAndDismiss: " + e.getMessage());
        cleanupAllViews();
      }
    });
  }

  private class StashJavaScriptInterface {
    @JavascriptInterface
    public void onPaymentSuccess() {
      if (paymentSuccessHandled) {
        return;
      }
      paymentSuccessHandled = true;
      isPurchaseProcessing = false;
      runOnMainAndDismiss(() -> {
        if (listener != null) {
          listener.onPaymentSuccess();
        }
      });
    }

    @JavascriptInterface
    public void onPaymentFailure() {
      if (paymentSuccessHandled) {
        return;
      }
      paymentSuccessHandled = true;
      isPurchaseProcessing = false;
      runOnMainAndDismiss(() -> {
        if (listener != null) {
          listener.onPaymentFailure();
        }
      });
    }

    @JavascriptInterface
    public void onPurchaseProcessing() {
      try {
        isPurchaseProcessing = true;
        new Handler(Looper.getMainLooper()).post(() -> {
          try {
            if (currentDialog != null && currentDialog.isShowing()) {
              currentDialog.setCanceledOnTouchOutside(false);
              currentDialog.setCancelable(false);
            }
          } catch (Exception e) {
            Log.e(TAG, "Error updating dialog dismissibility: " + e.getMessage(), e);
          }
        });
      } catch (Exception e) {
        Log.e(TAG, "Error in onPurchaseProcessing: " + e.getMessage(), e);
      }
    }
    
    @JavascriptInterface
    public void setPaymentChannel(String optinType) {
      runOnMainAndDismiss(() -> {
        if (listener != null) {
          listener.onOptInResponse(optinType != null ? optinType : "");
        }
      });
    }

    @JavascriptInterface
    public void expand() {
      runOnMainSafely(() -> {
        try {
          if (!useCheckoutOverlayPresentation) {
            return;
          }
          Activity a = getActivity();
          if (a == null || currentContainer == null || currentDialog == null
              || !currentDialog.isShowing()) {
            return;
          }
          if (!isCheckoutOverlayExpanded) {
            animateCheckoutOverlayExpand(a);
          }
        } catch (Exception e) {
          Log.e(TAG, "Error in expand from WebView: " + e.getMessage(), e);
        }
      });
    }

    @JavascriptInterface
    public void collapse() {
      runOnMainSafely(() -> {
        try {
          if (!useCheckoutOverlayPresentation) {
            return;
          }
          Activity a = getActivity();
          if (a == null || currentContainer == null || currentDialog == null
              || !currentDialog.isShowing()) {
            return;
          }
          if (isCheckoutOverlayExpanded) {
            animateCheckoutOverlayCollapse(a);
          }
        } catch (Exception e) {
          Log.e(TAG, "Error in collapse from WebView: " + e.getMessage(), e);
        }
      });
    }

    @JavascriptInterface
    public void requestCloseFromPage() {
      if (isPurchaseProcessing) {
        return;
      }
      new Handler(Looper.getMainLooper()).post(() -> {
        try {
          dismissCurrentDialog();
        } catch (Exception e) {
          Log.e(TAG, "Error in requestCloseFromPage: " + e.getMessage(), e);
        }
      });
    }
  }
  
  /**
   * Returns the singleton plugin instance.
   *
   * @return the plugin instance
   */
  public static StashNativeCardPlugin getInstance() {
    return Holder.INSTANCE;
  }

  private StashNativeCardPlugin() {
  }

  /**
   * Sets the Activity reference using WeakReference to prevent memory leaks.
   *
   * @param activity The activity to use for UI operations
   */
  void setActivity(Activity activity) {
    this.activityRef = new WeakReference<>(activity);
    if (activity != null) {
      ensureCheckoutBridgeReceiver(activity);
    }
  }
  
  /**
   * Gets the Activity if still available, or null if it was garbage collected.
   * Always check for null before using.
   *
   * @return The activity or null if no longer available
   */
  private Activity getActivity() {
    return activityRef != null ? activityRef.get() : null;
  }
  
  void setListener(StashNativeCard.StashNativeCardListener listener) {
    this.listener = listener;
    Activity a = getActivity();
    if (a != null) {
      ensureCheckoutBridgeReceiver(a);
    }
  }

  /**
   * Opens the given URL in card (sliding bottom sheet or portrait activity) presentation.
   *
   * @param url checkout URL to load
   * @param config card sizing config or null for defaults
   */
  public void openCard(String url, StashNativeCard.CardConfig config) {
    try {
      if (config != null) {
        this.forcePortraitOnCheckout = config.forcePortrait;
        this.cardHeightRatioPortrait = clampRatio(config.cardHeightRatioPortrait);
        this.cardWidthRatioLandscape = clampRatio(config.cardWidthRatioLandscape);
        this.cardHeightRatioLandscape = clampRatio(config.cardHeightRatioLandscape);
        this.tabletWidthRatioPortrait = clampRatio(config.tabletWidthRatioPortrait);
        this.tabletHeightRatioPortrait = clampRatio(config.tabletHeightRatioPortrait);
        this.tabletWidthRatioLandscape = clampRatio(config.tabletWidthRatioLandscape);
        this.tabletHeightRatioLandscape = clampRatio(config.tabletHeightRatioLandscape);
      }
      usePopupPresentation = false;
      useModalPresentation = false;
      openUrlInternal(url);
    } catch (Exception e) {
      Log.e(TAG, "Error in openCard: " + e.getMessage(), e);
      cleanupAllViews();
    }
  }

  /**
   * Opens the URL in Chrome Custom Tabs or system browser.
   *
   * @param url URL to open
   */
  public void openBrowser(String url) {
    try {
      Activity activity = getActivity();
      if (activity == null || url == null || url.isEmpty()) {
        Log.e(TAG, "Invalid activity or URL for openBrowser");
        return;
      }
      if (!url.startsWith("http://") && !url.startsWith("https://")) {
        url = "https://" + url;
      }
      try {
        url = StashWebViewUtils.appendThemeQueryParameter(url,
            StashWebViewUtils.isDarkTheme(activity));
      } catch (Exception e) {
        Log.e(TAG, "Error appending theme parameter: " + e.getMessage(), e);
      }
      final String finalUrl = url;
      final Activity finalActivity = activity;
      activity.runOnUiThread(() -> {
        try {
          if (StashWebViewUtils.isChromeCustomTabsAvailable(finalActivity)) {
            StashWebViewUtils.openWithChromeCustomTabs(finalActivity, finalUrl);
          } else {
            StashWebViewUtils.openInSystemBrowser(finalActivity, finalUrl);
          }
        } catch (Exception e) {
          Log.e(TAG, "Error in openBrowser: " + e.getMessage(), e);
        }
      });
    } catch (Exception e) {
      Log.e(TAG, "Error in openBrowser: " + e.getMessage(), e);
    }
  }

  /**
   * Opens the URL in a centered popup dialog with default size.
   *
   * @param url checkout URL to load
   */
  public void openPopup(String url) {
    try {
      usePopupPresentation = true;
      useModalPresentation = false;
      useCustomSize = false;
      openUrlInternal(url);
    } catch (Exception e) {
      Log.e(TAG, "Error in openPopup: " + e.getMessage(), e);
      cleanupAllViews();
    }
  }

  /**
   * Opens the URL in a centered popup with custom size multipliers.
   *
   * @param url checkout URL to load
   * @param portraitWidthMultiplier portrait width multiplier
   * @param portraitHeightMultiplier portrait height multiplier
   * @param landscapeWidthMultiplier landscape width multiplier
   * @param landscapeHeightMultiplier landscape height multiplier
   */
  public void openPopupWithSize(String url, float portraitWidthMultiplier,
      float portraitHeightMultiplier, float landscapeWidthMultiplier,
      float landscapeHeightMultiplier) {
    try {
      usePopupPresentation = true;
      useModalPresentation = false;
      customPortraitWidthMultiplier = portraitWidthMultiplier;
      customPortraitHeightMultiplier = portraitHeightMultiplier;
      customLandscapeWidthMultiplier = landscapeWidthMultiplier;
      customLandscapeHeightMultiplier = landscapeHeightMultiplier;
      useCustomSize = true;
      openUrlInternal(url);
    } catch (Exception e) {
      Log.e(TAG, "Error in openPopupWithSize: " + e.getMessage(), e);
      cleanupAllViews();
    }
  }

  /**
   * Opens the URL in a centered modal with optional config.
   *
   * @param url checkout URL to load
   * @param config modal config or null for defaults
   */
  public void openModal(String url, StashNativeCard.ModalConfig config) {
    try {
      usePopupPresentation = false;
      useModalPresentation = true;
      currentModalConfig = config != null ? config : new StashNativeCard.ModalConfig();
      openUrlInternal(url);
    } catch (Exception e) {
      Log.e(TAG, "Error in openModal: " + e.getMessage(), e);
      cleanupAllViews();
    }
  }

  /**
   * Dismisses the current checkout dialog if showing.
   */
  public void dismissDialog() {
    runOnMainSafely(() -> {
      try {
        dismissCurrentDialog();
      } catch (Exception e) {
        Log.e(TAG, "Error dismissing dialog: " + e.getMessage());
        cleanupAllViews();
      }
    });
  }

  /**
   * Resets presentation state and dismisses any dialog.
   */
  public void resetPresentationState() {
    try {
      dismissDialog();
      paymentSuccessHandled = false;
      presentationUsesIsolatedWebviewProcess = false;
      isCurrentlyPresented = false;
    } catch (Exception e) {
      Log.e(TAG, "Error in resetPresentationState: " + e.getMessage(), e);
      cleanupAllViews();
    }
  }

  /**
   * Returns whether a checkout UI is currently presented.
   *
   * @return true if presented
   */
  public boolean isCurrentlyPresented() {
    try {
      return isCurrentlyPresented;
    } catch (Exception e) {
      Log.e(TAG, "Error in isCurrentlyPresented: " + e.getMessage(), e);
      return false;
    }
  }

  // ============================================================================
  // Orientation-Specific Phone Card Size Configuration
  // ============================================================================

  private float clampRatio(float ratio) {
    return Math.max(0.1f, Math.min(1.0f, ratio));
  }

  /**
   * Returns whether a purchase is currently being processed.
   *
   * @return true if processing
   */
  public boolean isPurchaseProcessing() {
    try {
      return isPurchaseProcessing;
    } catch (Exception e) {
      Log.e(TAG, "Error in isPurchaseProcessing: " + e.getMessage(), e);
      return false;
    }
  }
  
  private void openUrlInternal(String url) {
    try {
      Activity activity = getActivity();
      if (activity == null || url == null || url.isEmpty()) {
        Log.e(TAG, "Invalid activity or URL");
        return;
      }

      ensureCheckoutBridgeReceiver(activity);

      if (!url.startsWith("http://") && !url.startsWith("https://")) {
        url = "https://" + url;
      }

      try {
        url = StashWebViewUtils.appendThemeQueryParameter(url,
            StashWebViewUtils.isDarkTheme(activity));
      } catch (Exception e) {
        Log.e(TAG, "Error appending theme parameter: " + e.getMessage(), e);
      }

      final String finalUrl = url;
      final Activity finalActivity = activity;

      activity.runOnUiThread(() -> {
        try {
          if (usePopupPresentation) {
            createAndShowPopupDialog(finalUrl, finalActivity);
          } else {
            // Both card and modal use PortraitActivity (process :stash_webview). This gives modal
            // the same retry/timeout/loading behaviour as the card and crash-isolates the WebView
            // renderer so a Chromium fault cannot kill the host app. The Activity reads the
            // useModal flag from the Intent and calls createModal() instead of createCard().
            launchPortraitActivity(finalUrl, finalActivity);
          }
        } catch (Exception e) {
          Log.e(TAG, "Error in UI thread operation: " + e.getMessage(), e);
          cleanupAllViews();
        }
      });
    } catch (Exception e) {
      Log.e(TAG, "Error in openUrlInternal: " + e.getMessage(), e);
      cleanupAllViews();
    }
  }
  
  private void launchPortraitActivity(String url, Activity activity) {
    try {
      int rotation;
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        android.view.Display display = activity.getDisplay();
        rotation = display != null ? display.getRotation() : Surface.ROTATION_0;
      } else {
        @SuppressWarnings("deprecation")
        android.view.Display display = activity.getWindowManager().getDefaultDisplay();
        rotation = display.getRotation();
      }
      boolean isLandscape = (rotation == Surface.ROTATION_90 || rotation == Surface.ROTATION_270);
      
      Intent intent = new Intent();
      intent.setClassName(activity, StashNativeCardPortraitActivity.class.getName());
      intent.putExtra(CardConstants.INTENT_EXTRA_URL, url);
      intent.putExtra(CardConstants.INTENT_EXTRA_INITIAL_URL, url);
      intent.putExtra(CardConstants.INTENT_EXTRA_CARD_HEIGHT_RATIO_PORTRAIT,
          cardHeightRatioPortrait);
      intent.putExtra(CardConstants.INTENT_EXTRA_FORCE_PORTRAIT_ON_CHECKOUT,
          forcePortraitOnCheckout);
      intent.putExtra(CardConstants.INTENT_EXTRA_CARD_WIDTH_RATIO_LANDSCAPE,
          cardWidthRatioLandscape);
      intent.putExtra(CardConstants.INTENT_EXTRA_CARD_HEIGHT_RATIO_LANDSCAPE,
          cardHeightRatioLandscape);
      intent.putExtra(CardConstants.INTENT_EXTRA_TABLET_WIDTH_RATIO_PORTRAIT,
          tabletWidthRatioPortrait);
      intent.putExtra(CardConstants.INTENT_EXTRA_TABLET_HEIGHT_RATIO_PORTRAIT,
          tabletHeightRatioPortrait);
      intent.putExtra(CardConstants.INTENT_EXTRA_TABLET_WIDTH_RATIO_LANDSCAPE,
          tabletWidthRatioLandscape);
      intent.putExtra(CardConstants.INTENT_EXTRA_TABLET_HEIGHT_RATIO_LANDSCAPE,
          tabletHeightRatioLandscape);
      intent.putExtra(CardConstants.INTENT_EXTRA_USE_POPUP, usePopupPresentation);
      intent.putExtra(CardConstants.INTENT_EXTRA_USE_MODAL, useModalPresentation);
      intent.putExtra(CardConstants.INTENT_EXTRA_WAS_LANDSCAPE, isLandscape);
      
      // Pass modal config if in modal mode
      if (useModalPresentation && currentModalConfig != null) {
        intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_SHOW_DRAG_BAR,
            currentModalConfig.showDragBar);
        intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_ALLOW_DISMISS,
            currentModalConfig.allowDismiss);
        intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_PHONE_WIDTH_RATIO_PORTRAIT,
            currentModalConfig.phoneWidthRatioPortrait);
        intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_PHONE_HEIGHT_RATIO_PORTRAIT,
            currentModalConfig.phoneHeightRatioPortrait);
        intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_PHONE_WIDTH_RATIO_LANDSCAPE,
            currentModalConfig.phoneWidthRatioLandscape);
        intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_PHONE_HEIGHT_RATIO_LANDSCAPE,
            currentModalConfig.phoneHeightRatioLandscape);
        intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_TABLET_WIDTH_RATIO_PORTRAIT,
            currentModalConfig.tabletWidthRatioPortrait);
        intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_TABLET_HEIGHT_RATIO_PORTRAIT,
            currentModalConfig.tabletHeightRatioPortrait);
        intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_TABLET_WIDTH_RATIO_LANDSCAPE,
            currentModalConfig.tabletWidthRatioLandscape);
        intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_TABLET_HEIGHT_RATIO_LANDSCAPE,
            currentModalConfig.tabletHeightRatioLandscape);
      }
      
      intent.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION | Intent.FLAG_ACTIVITY_NEW_TASK
          | Intent.FLAG_ACTIVITY_MULTIPLE_TASK);
      
      activity.startActivity(intent);
      activity.overridePendingTransition(0, 0);
      presentationUsesIsolatedWebviewProcess = true;
      isCurrentlyPresented = true;
    } catch (Exception e) {
      Log.e(TAG, "Failed to launch Activity: " + e.getMessage());
    }
  }
  
  private class PopupOrientationListener implements ViewTreeObserver.OnGlobalLayoutListener {
    private final Activity activity;

    PopupOrientationListener(Activity activity) {
      this.activity = activity;
    }

    @Override
    public void onGlobalLayout() {
      try {
        if (currentContainer != null && currentDialog != null && currentDialog.isShowing()
            && activity != null) {
          int currentOrientation = activity.getResources().getConfiguration().orientation;

          if (currentOrientation != lastOrientation
              && currentOrientation != Configuration.ORIENTATION_UNDEFINED) {
            lastOrientation = currentOrientation;
            
            try {
              int[] newDimensions;
              if (useCheckoutOverlayPresentation) {
                newDimensions = calculateCheckoutOverlayDimensions(activity);
              } else if (useModalPresentation) {
                newDimensions = calculateModalDimensions(activity);
              } else {
                newDimensions = calculatePopupDimensions(activity);
              }
              FrameLayout.LayoutParams params =
                  (FrameLayout.LayoutParams) currentContainer.getLayoutParams();

              if (useCheckoutOverlayPresentation) {
                isCheckoutOverlayExpanded = false;
                params.width = newDimensions[0];
                params.height = newDimensions[1];
                params.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
                currentContainer.setLayoutParams(params);
              } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
                currentContainer.animate()
                    .scaleX(0.95f)
                    .scaleY(0.95f)
                    .setDuration(100)
                    .withEndAction(() -> {
                      try {
                        params.width = newDimensions[0];
                        params.height = newDimensions[1];
                        currentContainer.setLayoutParams(params);
                        currentContainer.animate()
                            .scaleX(1.0f)
                            .scaleY(1.0f)
                            .setDuration(200)
                            .start();
                      } catch (Exception e) {
                        Log.e(TAG, "Error in animation end action: " + e.getMessage(), e);
                      }
                    })
                    .start();
              } else {
                params.width = newDimensions[0];
                params.height = newDimensions[1];
                currentContainer.setLayoutParams(params);
              }
            } catch (Exception e) {
              Log.e(TAG, "Error calculating or applying dimensions: " + e.getMessage(), e);
            }
          }
        }
      } catch (Exception e) {
        Log.e(TAG, "Error in onGlobalLayout: " + e.getMessage(), e);
      }
    }
  }

  /**
   * Touch listener for checkout overlay drag bar: expand (drag up), collapse (drag down when
   * expanded), dismiss (drag down when collapsed).
   */
  private class CheckoutOverlayDragTouchListener implements View.OnTouchListener {
    private final Activity activity;
    private float initialY;
    private int initialHeight;
    private boolean isDragging;
    private long lastMoveTime;
    private float lastMoveY;
    private float velocity;
    private DisplayMetrics displayMetrics;

    CheckoutOverlayDragTouchListener(Activity activity) {
      this.activity = activity;
    }

    @Override
    public boolean onTouch(View v, MotionEvent event) {
      if (currentContainer == null || currentDialog == null || !currentDialog.isShowing()
          || !useCheckoutOverlayPresentation) {
        return false;
      }
      if (isPurchaseProcessing) {
        return false;
      }

      switch (event.getAction()) {
        case MotionEvent.ACTION_DOWN:
          initialY = event.getRawY();
          FrameLayout.LayoutParams params =
              (FrameLayout.LayoutParams) currentContainer.getLayoutParams();
          initialHeight = params.height;
          isDragging = false;
          lastMoveTime = System.currentTimeMillis();
          lastMoveY = event.getRawY();
          velocity = 0;
          displayMetrics = activity.getResources().getDisplayMetrics();
          return true;

        case MotionEvent.ACTION_MOVE:
          long currentTime = System.currentTimeMillis();
          float timeDelta = (currentTime - lastMoveTime) / 1000f;
          if (timeDelta > 0) {
            velocity = (event.getRawY() - lastMoveY) / timeDelta;
          }
          lastMoveTime = currentTime;
          lastMoveY = event.getRawY();
          float deltaY = event.getRawY() - initialY;

          if (Math.abs(deltaY) > StashWebViewUtils.dpToPx(activity, 10)) {
            isDragging = true;
            if (deltaY > 0) {
              if (isCheckoutOverlayExpanded) {
                float cardHeight = currentContainer.getHeight();
                float collapseThreshold = cardHeight * CardConstants.COLLAPSE_DISTANCE_THRESHOLD;
                float progress = Math.min(deltaY / collapseThreshold, 1.0f);
                int[] collapsed = calculateCheckoutOverlayDimensions(activity);
                int expandedHeight = (int) (displayMetrics.heightPixels
                    * CardConstants.EXPANDED_CARD_HEIGHT_RATIO);
                int newHeight = (int) (expandedHeight - progress * (expandedHeight - collapsed[1]));
                params = (FrameLayout.LayoutParams) currentContainer.getLayoutParams();
                params.height = Math.max(newHeight, collapsed[1]);
                currentContainer.setLayoutParams(params);
              } else {
                float newTranslationY = deltaY;
                currentContainer.setTranslationY(newTranslationY);
                float progress = Math.min(deltaY / displayMetrics.heightPixels, 1.0f);
                currentContainer.setAlpha(1.0f - (progress * CardConstants.ALPHA_FADE_MULTIPLIER));
              }
            } else if (!isCheckoutOverlayExpanded) {
              float cardHeight = currentContainer.getHeight();
              float expandThreshold = cardHeight * CardConstants.EXPAND_DISTANCE_THRESHOLD;
              float dragProgress = Math.min(Math.abs(deltaY) / expandThreshold, 1.0f);
              if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
                currentContainer.setScaleX(1.0f + (dragProgress * 0.02f));
                currentContainer.setScaleY(1.0f + (dragProgress * 0.02f));
              }
            }
          }
          return true;

        case MotionEvent.ACTION_UP:
        case MotionEvent.ACTION_CANCEL:
          if (isDragging) {
            float finalDeltaY = event.getRawY() - initialY;
            DisplayMetrics metrics = displayMetrics != null
                ? activity.getResources().getDisplayMetrics()
                : activity.getResources().getDisplayMetrics();
            int cardHeight = currentContainer.getHeight();

            if (finalDeltaY > 0) {
              if (isCheckoutOverlayExpanded) {
                float dismissThreshold = metrics.heightPixels
                    * CardConstants.DISMISS_DISTANCE_THRESHOLD_TABLET;
                float collapseThreshold = cardHeight * CardConstants.COLLAPSE_DISTANCE_THRESHOLD;
                if (finalDeltaY > dismissThreshold
                    && velocity > CardConstants.DISMISS_VELOCITY_THRESHOLD) {
                  animateCheckoutOverlayDismiss();
                } else if (finalDeltaY > collapseThreshold
                    || velocity > CardConstants.COLLAPSE_VELOCITY_THRESHOLD) {
                  animateCheckoutOverlayCollapse(activity);
                } else {
                  animateCheckoutOverlaySnapBackExpand(activity);
                }
              } else {
                float dismissThreshold = metrics.heightPixels
                    * CardConstants.DISMISS_DISTANCE_THRESHOLD_PHONE;
                if (finalDeltaY > dismissThreshold
                    || velocity > CardConstants.DISMISS_VELOCITY_THRESHOLD) {
                  animateCheckoutOverlayDismiss();
                } else {
                  animateCheckoutOverlaySnapBackCollapsed(activity);
                }
              }
            } else if (finalDeltaY < 0 && !isCheckoutOverlayExpanded) {
              float expandThreshold = cardHeight * CardConstants.EXPAND_DISTANCE_THRESHOLD;
              if (Math.abs(finalDeltaY) > expandThreshold
                  || velocity < CardConstants.EXPAND_VELOCITY_THRESHOLD) {
                animateCheckoutOverlayExpand(activity);
              } else {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
                  currentContainer.animate()
                      .scaleX(1f)
                      .scaleY(1f)
                      .setDuration(CardConstants.ANIMATION_DURATION_SNAP_BACK)
                      .setInterpolator(new SpringInterpolator())
                      .start();
                }
              }
            } else {
              if (isCheckoutOverlayExpanded) {
                animateCheckoutOverlaySnapBackExpand(activity);
              } else {
                animateCheckoutOverlaySnapBackCollapsed(activity);
              }
            }
          }
          return true;
        default:
          return false;
      }
    }
  }

  private void animateCheckoutOverlayExpand(Activity activity) {
    if (currentContainer == null || activity == null) {
      return;
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
      currentContainer.animate().scaleX(1f).scaleY(1f).setDuration(100).start();
    }
    FrameLayout.LayoutParams params =
        (FrameLayout.LayoutParams) currentContainer.getLayoutParams();
    int expandedHeight = (int) (activity.getResources().getDisplayMetrics().heightPixels
        * CardConstants.EXPANDED_CARD_HEIGHT_RATIO);
    ValueAnimator heightAnimator = ValueAnimator.ofInt(params.height, expandedHeight);
    heightAnimator.setDuration(CardConstants.ANIMATION_DURATION_EXPAND);
    heightAnimator.setInterpolator(new SpringInterpolator());
    heightAnimator.addUpdateListener(animation -> {
      if (currentContainer != null) {
        FrameLayout.LayoutParams p =
            (FrameLayout.LayoutParams) currentContainer.getLayoutParams();
        p.height = (Integer) animation.getAnimatedValue();
        currentContainer.setLayoutParams(p);
      }
    });
    heightAnimator.start();
    currentContainer.setTranslationY(0);
    currentContainer.setAlpha(1f);
    isCheckoutOverlayExpanded = true;
  }

  private void animateCheckoutOverlayCollapse(Activity activity) {
    if (currentContainer == null || activity == null || !isCheckoutOverlayExpanded) {
      return;
    }
    int[] dims = calculateCheckoutOverlayDimensions(activity);
    FrameLayout.LayoutParams params =
        (FrameLayout.LayoutParams) currentContainer.getLayoutParams();
    ValueAnimator heightAnimator = ValueAnimator.ofInt(params.height, dims[1]);
    heightAnimator.setDuration(CardConstants.ANIMATION_DURATION_COLLAPSE);
    heightAnimator.setInterpolator(new SpringInterpolator());
    heightAnimator.addUpdateListener(animation -> {
      if (currentContainer != null) {
        FrameLayout.LayoutParams p =
            (FrameLayout.LayoutParams) currentContainer.getLayoutParams();
        p.height = (Integer) animation.getAnimatedValue();
        currentContainer.setLayoutParams(p);
      }
    });
    heightAnimator.start();
    currentContainer.setTranslationY(0);
    currentContainer.setAlpha(1f);
    isCheckoutOverlayExpanded = false;
  }

  private void animateCheckoutOverlaySnapBackExpand(Activity activity) {
    if (currentContainer == null) {
      return;
    }
    int expandedHeight = (int) (activity.getResources().getDisplayMetrics().heightPixels
        * CardConstants.EXPANDED_CARD_HEIGHT_RATIO);
    FrameLayout.LayoutParams params =
        (FrameLayout.LayoutParams) currentContainer.getLayoutParams();
    ValueAnimator heightAnimator = ValueAnimator.ofInt(params.height, expandedHeight);
    heightAnimator.setDuration(CardConstants.ANIMATION_DURATION_SNAP_BACK);
    heightAnimator.setInterpolator(new SpringInterpolator());
    heightAnimator.addUpdateListener(animation -> {
      if (currentContainer != null) {
        FrameLayout.LayoutParams p =
            (FrameLayout.LayoutParams) currentContainer.getLayoutParams();
        p.height = (Integer) animation.getAnimatedValue();
        currentContainer.setLayoutParams(p);
      }
    });
    heightAnimator.start();
    currentContainer.setTranslationY(0);
    currentContainer.setAlpha(1f);
  }

  private void animateCheckoutOverlaySnapBackCollapsed(Activity activity) {
    if (currentContainer == null || activity == null) {
      return;
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
      currentContainer.animate()
          .scaleX(1f)
          .scaleY(1f)
          .setDuration(CardConstants.ANIMATION_DURATION_SNAP_BACK)
          .setInterpolator(new SpringInterpolator())
          .start();
    }
    currentContainer.setTranslationY(0);
    currentContainer.setAlpha(1f);
  }

  private void animateCheckoutOverlayDismiss() {
    if (currentDialog == null || currentContainer == null) {
      return;
    }
    Activity a = getActivity();
    int height = currentContainer.getHeight();
    if (height <= 0 && a != null) {
      height = (int) (a.getResources().getDisplayMetrics().heightPixels * cardHeightRatioPortrait);
    }
    if (height <= 0) {
      height = 800;
    }
    final int finalHeight = height;
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
      currentContainer.animate()
        .translationY(finalHeight)
        .setDuration(CardConstants.ANIMATION_DURATION_ENTRY)
        .setInterpolator(new android.view.animation.AccelerateInterpolator())
        .withEndAction(() -> {
          if (currentDialog != null) {
            currentDialog.dismiss();
          }
        })
          .start();
    } else {
      currentDialog.dismiss();
    }
    isCheckoutOverlayExpanded = false;
  }

  private void createAndShowPopupDialog(String url, final Activity activity) {
    if (activity == null || url == null || url.isEmpty()) {
      Log.e(TAG, "Invalid activity or URL in createAndShowPopupDialog");
      return;
    }

    boolean preserveUseCustomSize = useCustomSize;
    cleanupAllViews();
    useCustomSize = preserveUseCustomSize;
    paymentSuccessHandled = false;

    try {
      currentDialog = new Dialog(activity, android.R.style.Theme_Translucent_NoTitleBar_Fullscreen);
      currentDialog.requestWindowFeature(Window.FEATURE_NO_TITLE);

      FrameLayout mainFrame = new FrameLayout(activity);
      try {
        mainFrame.setBackgroundColor(Color.parseColor(StashWebViewUtils.COLOR_BACKGROUND_DIM));
      } catch (Exception e) {
        Log.e(TAG, "Error setting background color: " + e.getMessage(), e);
        mainFrame.setBackgroundColor(Color.parseColor(CardConstants.COLOR_BACKGROUND_DIM));
      }
      
      mainFrame.setOnClickListener(v -> {
        try {
          if (!isPurchaseProcessing && currentDialog != null && currentDialog.isShowing()
              && v == mainFrame) {
            currentDialog.dismiss();
          }
        } catch (Exception e) {
          Log.e(TAG, "Error in click handler: " + e.getMessage(), e);
        }
      });

      int[] dimensions;
      try {
        dimensions = calculatePopupDimensions(activity);
      } catch (Exception e) {
        Log.e(TAG, "Error calculating dimensions: " + e.getMessage(), e);
        DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
        dimensions = new int[]{
          (int) (metrics.widthPixels * 0.9f),
          (int) (metrics.heightPixels * 0.7f)
        };
      }
      
      currentContainer = new FrameLayout(activity);
      FrameLayout.LayoutParams containerParams = new FrameLayout.LayoutParams(
          dimensions[0], dimensions[1]);
      containerParams.gravity = Gravity.CENTER;
      currentContainer.setLayoutParams(containerParams);

      try {
        lastOrientation = activity.getResources().getConfiguration().orientation;
      } catch (Exception e) {
        Log.e(TAG, "Error getting orientation: " + e.getMessage(), e);
        lastOrientation = Configuration.ORIENTATION_PORTRAIT;
      }
      
      orientationChangeListener = new PopupOrientationListener(activity);
      try {
        mainFrame.getViewTreeObserver().addOnGlobalLayoutListener(orientationChangeListener);
      } catch (Exception e) {
        Log.e(TAG, "Error adding layout listener: " + e.getMessage(), e);
      }
      
      try {
        GradientDrawable popupBg = new GradientDrawable();
        popupBg.setColor(StashWebViewUtils.getThemeBackgroundColor(activity));
        float radius = StashWebViewUtils.dpToPx(activity, (int) CardConstants.CORNER_RADIUS_DP);
        popupBg.setCornerRadius(radius);
        currentContainer.setBackground(popupBg);
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
          currentContainer.setElevation(
              StashWebViewUtils.dpToPx(activity, (int) CardConstants.ELEVATION_DP));
          currentContainer.setOutlineProvider(new ViewOutlineProvider() {
            @Override
            public void getOutline(View view, Outline outline) {
              try {
                outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), radius);
              } catch (Exception e) {
                Log.e(TAG, "Error setting outline: " + e.getMessage(), e);
              }
            }
          });
          currentContainer.setClipToOutline(true);
        }
      } catch (Exception e) {
        Log.e(TAG, "Error setting container background: " + e.getMessage(), e);
      }
      
      try {
        webView = new WebView(activity);
        FrameLayout.LayoutParams webViewParams = new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
        webView.setLayoutParams(webViewParams);
        currentContainer.addView(webView);

        setupPopupWebView(webView, url, activity);
      } catch (Exception e) {
        Log.e(TAG, "Error creating WebView: " + e.getMessage(), e);
        cleanupAllViews();
        return;
      }

      mainFrame.addView(currentContainer);
      currentDialog.setContentView(mainFrame);

      Window window = currentDialog.getWindow();
      if (window != null) {
        try {
          window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT,
              ViewGroup.LayoutParams.MATCH_PARENT);
          window.setFlags(WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
              WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED);
          window.setBackgroundDrawableResource(android.R.color.transparent);
          window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
          WindowManager.LayoutParams windowParams = window.getAttributes();
          windowParams.dimAmount = CardConstants.OVERLAY_ALPHA;
          window.setAttributes(windowParams);
        } catch (Exception e) {
          Log.e(TAG, "Error configuring window: " + e.getMessage(), e);
        }
      }

      currentContainer.setOnClickListener(v -> {});
      
      currentDialog.setCanceledOnTouchOutside(!isPurchaseProcessing);
      currentDialog.setCancelable(!isPurchaseProcessing);

      currentDialog.setOnDismissListener(dialog -> {
        try {
          if (!paymentSuccessHandled && listener != null) {
            listener.onDialogDismissed();
          }
        } catch (Exception e) {
          Log.e(TAG, "Error in dismiss listener: " + e.getMessage(), e);
        }
        cleanupAllViews();
        presentationUsesIsolatedWebviewProcess = false;
        isCurrentlyPresented = false;
      });
      
      try {
        currentDialog.show();
        animateFadeIn();
        presentationUsesIsolatedWebviewProcess = false;
        isCurrentlyPresented = true;
      } catch (Exception e) {
        Log.e(TAG, "Error showing dialog: " + e.getMessage(), e);
        cleanupAllViews();
      }
    } catch (Exception e) {
      Log.e(TAG, "Error creating popup: " + e.getMessage(), e);
      cleanupAllViews();
    }
  }
  
  private void createAndShowModalDialog(String url, final Activity activity) {
    if (activity == null || url == null || url.isEmpty()) {
      Log.e(TAG, "Invalid activity or URL in createAndShowModalDialog");
      return;
    }
    if (currentModalConfig == null) {
      currentModalConfig = new StashNativeCard.ModalConfig();
    }

    cleanupAllViews();
    useModalPresentation = true;
    paymentSuccessHandled = false;

    try {
      currentDialog = new Dialog(activity, android.R.style.Theme_Translucent_NoTitleBar_Fullscreen);
      currentDialog.requestWindowFeature(Window.FEATURE_NO_TITLE);

      FrameLayout mainFrame = new FrameLayout(activity);
      try {
        mainFrame.setBackgroundColor(Color.parseColor(StashWebViewUtils.COLOR_BACKGROUND_DIM));
      } catch (Exception e) {
        Log.e(TAG, "Error setting background color: " + e.getMessage(), e);
        mainFrame.setBackgroundColor(Color.parseColor(CardConstants.COLOR_BACKGROUND_DIM));
      }

      mainFrame.setOnClickListener(v -> {
        try {
          if (currentModalConfig.allowDismiss && !isPurchaseProcessing && currentDialog != null
              && currentDialog.isShowing() && v == mainFrame) {
            currentDialog.dismiss();
          }
        } catch (Exception e) {
          Log.e(TAG, "Error in click handler: " + e.getMessage(), e);
        }
      });

      int[] dimensions;
      try {
        dimensions = calculateModalDimensions(activity);
      } catch (Exception e) {
        Log.e(TAG, "Error calculating modal dimensions: " + e.getMessage(), e);
        DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
        dimensions = new int[]{
          (int) (metrics.widthPixels * 0.9f),
          (int) (metrics.heightPixels * 0.5f)
        };
      }

      currentContainer = new FrameLayout(activity);
      FrameLayout.LayoutParams containerParams = new FrameLayout.LayoutParams(
          dimensions[0], dimensions[1]);
      containerParams.gravity = Gravity.CENTER;
      currentContainer.setLayoutParams(containerParams);

      try {
        lastOrientation = activity.getResources().getConfiguration().orientation;
      } catch (Exception e) {
        Log.e(TAG, "Error getting orientation: " + e.getMessage(), e);
        lastOrientation = Configuration.ORIENTATION_PORTRAIT;
      }

      orientationChangeListener = new PopupOrientationListener(activity);
      try {
        mainFrame.getViewTreeObserver().addOnGlobalLayoutListener(orientationChangeListener);
      } catch (Exception e) {
        Log.e(TAG, "Error adding layout listener: " + e.getMessage(), e);
      }

      try {
        GradientDrawable popupBg = new GradientDrawable();
        popupBg.setColor(StashWebViewUtils.getThemeBackgroundColor(activity));
        float radius = StashWebViewUtils.dpToPx(activity, (int) CardConstants.CORNER_RADIUS_DP);
        popupBg.setCornerRadius(radius);
        currentContainer.setBackground(popupBg);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
          currentContainer.setElevation(
              StashWebViewUtils.dpToPx(activity, (int) CardConstants.ELEVATION_DP));
          currentContainer.setOutlineProvider(new ViewOutlineProvider() {
            @Override
            public void getOutline(View view, Outline outline) {
              try {
                outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), radius);
              } catch (Exception e) {
                Log.e(TAG, "Error setting outline: " + e.getMessage(), e);
              }
            }
          });
          currentContainer.setClipToOutline(true);
        }
      } catch (Exception e) {
        Log.e(TAG, "Error setting container background: " + e.getMessage(), e);
      }

      try {
        webView = new WebView(activity);
        FrameLayout.LayoutParams webViewParams = new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
        webView.setLayoutParams(webViewParams);
        currentContainer.addView(webView);
        if (currentModalConfig.showDragBar) {
          addVisualDragBarToContainer(activity, currentContainer);
        }
        setupPopupWebView(webView, url, activity);
      } catch (Exception e) {
        Log.e(TAG, "Error creating WebView: " + e.getMessage(), e);
        cleanupAllViews();
        return;
      }

      mainFrame.addView(currentContainer);
      currentDialog.setContentView(mainFrame);

      Window window = currentDialog.getWindow();
      if (window != null) {
        try {
          window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT,
              ViewGroup.LayoutParams.MATCH_PARENT);
          window.setFlags(WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
              WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED);
          window.setBackgroundDrawableResource(android.R.color.transparent);
          window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
          WindowManager.LayoutParams windowParams = window.getAttributes();
          windowParams.dimAmount = CardConstants.OVERLAY_ALPHA;
          window.setAttributes(windowParams);
        } catch (Exception e) {
          Log.e(TAG, "Error configuring window: " + e.getMessage(), e);
        }
      }

      currentContainer.setOnClickListener(v -> {});

      currentDialog.setCanceledOnTouchOutside(
          currentModalConfig.allowDismiss && !isPurchaseProcessing);
      currentDialog.setCancelable(!isPurchaseProcessing);

      currentDialog.setOnDismissListener(dialog -> {
        try {
          if (!paymentSuccessHandled && listener != null) {
            listener.onDialogDismissed();
          }
        } catch (Exception e) {
          Log.e(TAG, "Error in dismiss listener: " + e.getMessage(), e);
        }
        cleanupAllViews();
        presentationUsesIsolatedWebviewProcess = false;
        isCurrentlyPresented = false;
      });

      try {
        currentDialog.show();
        animateFadeIn();
        presentationUsesIsolatedWebviewProcess = false;
        isCurrentlyPresented = true;
      } catch (Exception e) {
        Log.e(TAG, "Error showing modal dialog: " + e.getMessage(), e);
        cleanupAllViews();
      }
    } catch (Exception e) {
      Log.e(TAG, "Error creating modal: " + e.getMessage(), e);
      cleanupAllViews();
    }
  }

  private void animateFadeIn() {
    try {
      if (currentContainer != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
        currentContainer.setAlpha(0.0f);
        currentContainer.setScaleX(0.9f);
        currentContainer.setScaleY(0.9f);
        currentContainer.animate()
            .alpha(1.0f)
            .scaleX(1.0f)
            .scaleY(1.0f)
            .setDuration(CardConstants.ANIMATION_DURATION_POPUP)
            .setInterpolator(new android.view.animation.AccelerateDecelerateInterpolator())
            .start();
      }
    } catch (Exception e) {
      Log.e(TAG, "Error in animateFadeIn: " + e.getMessage(), e);
    }
  }
  
  private void dismissPopupDialog() {
    try {
      if (currentDialog != null && currentContainer != null) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
          currentContainer.animate()
              .alpha(0.0f)
              .scaleX(0.9f)
              .scaleY(0.9f)
              .setDuration(CardConstants.ANIMATION_DURATION_FAST)
              .setInterpolator(new SpringInterpolator())
              .withEndAction(() -> {
                try {
                  if (currentDialog != null) {
                    currentDialog.dismiss();
                  }
                } catch (Exception e) {
                  Log.e(TAG, "Error dismissing dialog in animation: " + e.getMessage(), e);
                }
              })
              .start();
        } else {
          currentDialog.dismiss();
        }
      } else if (currentDialog != null) {
        currentDialog.dismiss();
      }
    } catch (Exception e) {
      Log.e(TAG, "Error in dismissPopupDialog: " + e.getMessage(), e);
      try {
        if (currentDialog != null) {
          currentDialog.dismiss();
        }
      } catch (Exception e2) {
        Log.e(TAG, "Error force dismissing dialog: " + e2.getMessage(), e2);
      }
    }
  }
  
  /**
   * Chromium/WebView renderer crashed or was killed. Remove UI and notify the host; returning
   * {@code true} from {@link WebViewClient#onRenderProcessGone} prevents the default behavior of
   * tearing down the app process (API 26+).
   */
  @RequiresApi(Build.VERSION_CODES.O)
  private void handleWebViewRenderProcessGone(RenderProcessGoneDetail detail) {
    Log.e(TAG, "WebView render process gone (didCrash=" + detail.didCrash() + ")");
    try {
      if (currentDialog != null) {
        try {
          currentDialog.setOnDismissListener(null);
        } catch (Exception e) {
          Log.e(TAG, "Error clearing dismiss listener: " + e.getMessage(), e);
        }
      }
      cleanupAllViews();
      presentationUsesIsolatedWebviewProcess = false;
      isCurrentlyPresented = false;
      if (listener != null) {
        listener.onNetworkError();
      }
    } catch (Exception e) {
      Log.e(TAG, "Error recovering from render process gone: " + e.getMessage(), e);
    }
  }

  private void setupPopupWebView(WebView webView, String url, final Activity activity) {
    if (webView == null || activity == null || url == null || url.isEmpty()) {
      Log.e(TAG, "Invalid parameters in setupPopupWebView");
      return;
    }

    try {
      StashWebViewUtils.configureWebViewSettings(webView, StashWebViewUtils.isDarkTheme(activity));
    } catch (Exception e) {
      Log.e(TAG, "Error configuring WebView settings: " + e.getMessage(), e);
    }
    
    webView.setWebViewClient(new WebViewClient() {
      @Override
      public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
        try {
          super.onPageStarted(view, url, favicon);
          pageLoadStartTime = System.currentTimeMillis();
          showLoadingIndicator(activity);
          injectStashSDKFunctions();
        } catch (Exception e) {
          Log.e(TAG, "Error in onPageStarted: " + e.getMessage(), e);
        }
      }
      
      @Override
      public void onPageFinished(WebView view, String url) {
        try {
          super.onPageFinished(view, url);
          
          if (pageLoadStartTime > 0) {
            long loadTimeMs = System.currentTimeMillis() - pageLoadStartTime;
            try {
              if (listener != null) {
                listener.onPageLoaded(loadTimeMs);
              }
            } catch (Exception e) {
              Log.e(TAG, "Error sending page loaded message: " + e.getMessage(), e);
            }
            pageLoadStartTime = 0;
          }
          
          injectStashSDKFunctions();
          view.postDelayed(() -> {
            try {
              hideLoadingIndicator(activity);
              view.setVisibility(View.VISIBLE);
            } catch (Exception e) {
              Log.e(TAG, "Error in delayed page finished handler: " + e.getMessage(), e);
            }
          }, CardConstants.HIDE_LOADING_DELAY_MS);
        } catch (Exception e) {
          Log.e(TAG, "Error in onPageFinished: " + e.getMessage(), e);
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
          Log.e(TAG, "Error in onReceivedError: " + e.getMessage(), e);
        }
      }

      @Override
      @RequiresApi(Build.VERSION_CODES.O)
      public boolean onRenderProcessGone(WebView view, RenderProcessGoneDetail detail) {
        handleWebViewRenderProcessGone(detail);
        return true;
      }
    });
    
    try {
      webView.setWebChromeClient(new WebChromeClient());
      webView.addJavascriptInterface(new StashJavaScriptInterface(),
          StashWebViewUtils.JS_INTERFACE_NAME);
      webView.setVerticalScrollBarEnabled(false);
      webView.setHorizontalScrollBarEnabled(false);
      webView.setBackgroundColor(Color.TRANSPARENT);
      webView.loadUrl(url);
    } catch (Exception e) {
      Log.e(TAG, "Error setting up WebView: " + e.getMessage(), e);
      cleanupAllViews();
    }
  }
  
  private void injectStashSDKFunctions() {
    if (webView == null) {
      return;
    }
    
    try {
      webView.evaluateJavascript(StashWebViewUtils.JS_SDK_SCRIPT, null);
    } catch (Exception e) {
      Log.e(TAG, "Error injecting SDK functions: " + e.getMessage(), e);
    }
  }
  
  private void showLoadingIndicator(Activity activity) {
    if (currentContainer == null || activity == null) {
      return;
    }
    try {
      activity.runOnUiThread(() -> {
        try {
          if (loadingIndicator != null && loadingIndicator.getParent() != null) {
            ((ViewGroup) loadingIndicator.getParent()).removeView(loadingIndicator);
          }
          loadingIndicator = StashWebViewUtils.createAndShowLoading(activity, currentContainer);
        } catch (Exception e) {
          Log.e(TAG, "Error showing loading indicator: " + e.getMessage(), e);
        }
      });
    } catch (Exception e) {
      Log.e(TAG, "Error scheduling loading indicator: " + e.getMessage(), e);
    }
  }
  
  private void hideLoadingIndicator(Activity activity) {
    if (loadingIndicator == null || activity == null) {
      return;
    }
    try {
      activity.runOnUiThread(() -> {
        try {
          StashWebViewUtils.hideLoading(loadingIndicator);
          loadingIndicator = null;
        } catch (Exception e) {
          Log.e(TAG, "Error hiding loading indicator: " + e.getMessage(), e);
          loadingIndicator = null;
        }
      });
    } catch (Exception e) {
      Log.e(TAG, "Error scheduling hide loading indicator: " + e.getMessage(), e);
    }
  }
  
  private void openWithChromeCustomTabs(String url, Activity activity) {
    try {
      if (StashWebViewUtils.isChromeCustomTabsAvailable(activity)) {
        Log.d(TAG, "Opening URL with Chrome Custom Tabs");
        StashWebViewUtils.openWithChromeCustomTabs(activity, url);
        presentationUsesIsolatedWebviewProcess = false;
        isCurrentlyPresented = true;
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
          try {
            if (listener != null) {
              listener.onDialogDismissed();
            }
          } catch (Exception e) {
            Log.e(TAG, "Error sending dialog dismissed: " + e.getMessage(), e);
          }
        }, CardConstants.DIALOG_DISMISS_DELAY_MS);
      } else {
        Log.w(TAG, "Chrome Custom Tabs not available. Falling back to default browser.");
        openWithDefaultBrowser(url, activity);
      }
    } catch (Exception e) {
      Log.e(TAG, "Failed to open browser: " + e.getMessage());
      try {
        openWithDefaultBrowser(url, activity);
      } catch (Exception fallbackException) {
        Log.e(TAG, "Failed to open default browser: " + fallbackException.getMessage());
      }
    }
  }
  
  private void openWithDefaultBrowser(String url, Activity activity) {
    if (activity == null || url == null || url.isEmpty()) {
      Log.e(TAG, "Invalid activity or URL in openWithDefaultBrowser");
      return;
    }

    try {
      Intent browserIntent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
      browserIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
      activity.startActivity(browserIntent);
      presentationUsesIsolatedWebviewProcess = false;
      isCurrentlyPresented = true;

      new Handler(Looper.getMainLooper()).postDelayed(() -> {
        try {
          if (listener != null) {
            listener.onDialogDismissed();
          }
        } catch (Exception e) {
          Log.e(TAG, "Error sending dialog dismissed: " + e.getMessage(), e);
        }
      }, CardConstants.DIALOG_DISMISS_DELAY_MS);
    } catch (Exception e) {
      Log.e(TAG, "Error opening default browser: " + e.getMessage(), e);
      presentationUsesIsolatedWebviewProcess = false;
      isCurrentlyPresented = false;
    }
  }
  
  private void dismissCurrentDialog() {
    try {
      if (currentDialog != null) {
        dismissPopupDialog();
      }
    } catch (Exception e) {
      Log.e(TAG, "Error in dismissCurrentDialog: " + e.getMessage(), e);
      cleanupAllViews();
    }
  }
  
  private void cleanupAllViews() {
    try {
      useCheckoutOverlayPresentation = false;
      if (loadingIndicator != null) {
        try {
          if (loadingIndicator.getParent() != null) {
            ((ViewGroup) loadingIndicator.getParent()).removeView(loadingIndicator);
          }
        } catch (Exception e) {
          Log.e(TAG, "Error cleaning up loading indicator: " + e.getMessage());
        }
        loadingIndicator = null;
      }
      
      if (currentDialog != null) {
        if (currentDialog.isShowing()) {
          currentDialog.dismiss();
        }
        currentDialog = null;
      }
      
      if (webView != null) {
        try {
          if (webView.getParent() != null) {
            ((ViewGroup) webView.getParent()).removeView(webView);
          }
          webView.stopLoading();
          webView.destroy();
        } catch (Exception e) {
          Log.e(TAG, "Error cleaning up WebView: " + e.getMessage());
        }
        webView = null;
      }
      
      if (currentContainer != null) {
        try {
          if (orientationChangeListener != null && currentContainer.getParent() != null) {
            View parent = (View) currentContainer.getParent();
            if (parent.getViewTreeObserver().isAlive()) {
              parent.getViewTreeObserver().removeOnGlobalLayoutListener(orientationChangeListener);
            }
          }
          if (currentContainer.getParent() != null) {
            ((ViewGroup) currentContainer.getParent()).removeView(currentContainer);
          }
          currentContainer.removeAllViews();
        } catch (Exception e) {
          Log.e(TAG, "Error cleaning up container: " + e.getMessage());
        }
        currentContainer = null;
      }
      
      orientationChangeListener = null;
    } catch (Exception e) {
      Log.e(TAG, "Error during cleanup: " + e.getMessage());
    }
    
    isPurchaseProcessing = false;
    usePopupPresentation = false;
    useModalPresentation = false;
  }
  
  private int[] calculatePopupDimensions(Activity activity) {
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
          ? (useCustomSize ? customLandscapeWidthMultiplier
              : CardConstants.POPUP_LANDSCAPE_WIDTH_MULTIPLIER)
          : (useCustomSize ? customPortraitWidthMultiplier
              : CardConstants.POPUP_PORTRAIT_WIDTH_MULTIPLIER);
      float heightMultiplier = isLandscape
          ? (useCustomSize ? customLandscapeHeightMultiplier
              : CardConstants.POPUP_LANDSCAPE_HEIGHT_MULTIPLIER)
          : (useCustomSize ? customPortraitHeightMultiplier
              : CardConstants.POPUP_PORTRAIT_HEIGHT_MULTIPLIER);

      int popupWidth = (int) (baseSize * widthMultiplier);
      int popupHeight = (int) (baseSize * heightMultiplier);

      return new int[]{popupWidth, popupHeight};
    } catch (Exception e) {
      Log.e(TAG, "Error calculating popup dimensions: " + e.getMessage(), e);
      try {
        DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
        return new int[]{
          (int) (metrics.widthPixels * 0.9f),
          (int) (metrics.heightPixels * 0.7f)
        };
      } catch (Exception e2) {
        Log.e(TAG, "Error getting fallback dimensions: " + e2.getMessage(), e2);
        return new int[]{CardConstants.FALLBACK_POPUP_WIDTH, CardConstants.FALLBACK_POPUP_HEIGHT};
      }
    }
  }

  private int[] calculateModalDimensions(Activity activity) {
    if (activity == null || currentModalConfig == null) {
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
            ? currentModalConfig.tabletWidthRatioLandscape
            : currentModalConfig.tabletWidthRatioPortrait;
        heightRatio = isLandscape
            ? currentModalConfig.tabletHeightRatioLandscape
            : currentModalConfig.tabletHeightRatioPortrait;
      } else {
        widthRatio = isLandscape
            ? currentModalConfig.phoneWidthRatioLandscape
            : currentModalConfig.phoneWidthRatioPortrait;
        heightRatio = isLandscape
            ? currentModalConfig.phoneHeightRatioLandscape
            : currentModalConfig.phoneHeightRatioPortrait;
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
      Log.e(TAG, "Error calculating modal dimensions: " + e.getMessage(), e);
      try {
        DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
        return new int[]{
          (int) (metrics.widthPixels * 0.9f),
          (int) (metrics.heightPixels * 0.5f)
        };
      } catch (Exception e2) {
        Log.e(TAG, "Error getting fallback dimensions: " + e2.getMessage(), e2);
        return new int[]{CardConstants.FALLBACK_POPUP_WIDTH, CardConstants.FALLBACK_POPUP_HEIGHT};
      }
    }
  }
  
  private int[] calculateCheckoutOverlayDimensions(Activity activity) {
    if (activity == null) {
      return new int[]{CardConstants.FALLBACK_POPUP_WIDTH, CardConstants.FALLBACK_POPUP_HEIGHT};
    }
    try {
      DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
      int screenWidth = metrics.widthPixels;
      int screenHeight = metrics.heightPixels;
      boolean isLandscape = activity.getResources().getConfiguration().orientation
          == Configuration.ORIENTATION_LANDSCAPE;
      int cardWidth;
      int cardHeight;
      if (isLandscape) {
        int w = (int) (screenWidth * cardWidthRatioLandscape);
        int h = (int) (screenHeight * cardHeightRatioLandscape);
        int minPx = StashWebViewUtils.dpToPx(activity, (int) CardConstants.MIN_PHONE_CARD_WIDTH_DP);
        if (w < minPx) {
          w = minPx;
        }
        if (h < minPx) {
          h = minPx;
        }
        cardWidth = w;
        cardHeight = h;
      } else {
        cardWidth = screenWidth;
        cardHeight = (int) (screenHeight * cardHeightRatioPortrait);
      }
      return new int[]{cardWidth, cardHeight};
    } catch (Exception e) {
      Log.e(TAG, "Error calculating checkout overlay dimensions: " + e.getMessage(), e);
      try {
        DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
        return new int[]{
          metrics.widthPixels,
          (int) (metrics.heightPixels * CardConstants.DEFAULT_CARD_HEIGHT_RATIO)
        };
      } catch (Exception e2) {
        return new int[]{CardConstants.FALLBACK_POPUP_WIDTH, CardConstants.FALLBACK_POPUP_HEIGHT};
      }
    }
  }
  
  private void createAndShowCheckoutOverlay(String url, final Activity activity) {
    if (activity == null || url == null || url.isEmpty()) {
      Log.e(TAG, "Invalid activity or URL in createAndShowCheckoutOverlay");
      return;
    }
    cleanupAllViews();
    useCheckoutOverlayPresentation = true;
    paymentSuccessHandled = false;
    try {
      currentDialog = new Dialog(activity, android.R.style.Theme_Translucent_NoTitleBar_Fullscreen);
      currentDialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
      FrameLayout mainFrame = new FrameLayout(activity);
      try {
        mainFrame.setBackgroundColor(Color.parseColor(StashWebViewUtils.COLOR_BACKGROUND_DIM));
      } catch (Exception e) {
        mainFrame.setBackgroundColor(Color.parseColor(CardConstants.COLOR_BACKGROUND_DIM));
      }
      mainFrame.setOnClickListener(v -> {
        try {
          if (!isPurchaseProcessing && currentDialog != null && currentDialog.isShowing()
              && v == mainFrame) {
            currentDialog.dismiss();
          }
        } catch (Exception e) {
          Log.e(TAG, "Error in checkout overlay click handler: " + e.getMessage(), e);
        }
      });
      int[] dimensions;
      try {
        dimensions = calculateCheckoutOverlayDimensions(activity);
      } catch (Exception e) {
        Log.e(TAG, "Error calculating checkout overlay dimensions: " + e.getMessage(), e);
        DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
        dimensions = new int[]{
          metrics.widthPixels,
          (int) (metrics.heightPixels * cardHeightRatioPortrait)
        };
      }
      currentContainer = new FrameLayout(activity);
      FrameLayout.LayoutParams containerParams = new FrameLayout.LayoutParams(
          dimensions[0], dimensions[1]);
      containerParams.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
      currentContainer.setLayoutParams(containerParams);
      try {
        lastOrientation = activity.getResources().getConfiguration().orientation;
      } catch (Exception e) {
        lastOrientation = Configuration.ORIENTATION_PORTRAIT;
      }
      orientationChangeListener = new PopupOrientationListener(activity);
      try {
        mainFrame.getViewTreeObserver().addOnGlobalLayoutListener(orientationChangeListener);
      } catch (Exception e) {
        Log.e(TAG, "Error adding orientation listener: " + e.getMessage(), e);
      }
      try {
        GradientDrawable popupBg = new GradientDrawable();
        popupBg.setColor(StashWebViewUtils.getThemeBackgroundColor(activity));
        float radius = StashWebViewUtils.dpToPx(activity, (int) CardConstants.CORNER_RADIUS_DP);
        popupBg.setCornerRadius(radius);
        currentContainer.setBackground(popupBg);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
          currentContainer.setElevation(
              StashWebViewUtils.dpToPx(activity, (int) CardConstants.ELEVATION_DP));
          currentContainer.setOutlineProvider(new ViewOutlineProvider() {
            @Override
            public void getOutline(View view, Outline outline) {
              try {
                outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), radius);
              } catch (Exception e) {
                Log.e(TAG, "Error setting outline: " + e.getMessage(), e);
              }
            }
          });
          currentContainer.setClipToOutline(true);
        }
      } catch (Exception e) {
        Log.e(TAG, "Error setting container background: " + e.getMessage(), e);
      }
      try {
        webView = new WebView(activity);
        FrameLayout.LayoutParams webViewParams = new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
        webView.setLayoutParams(webViewParams);
        currentContainer.addView(webView);
        addCheckoutOverlayDragBar(activity);
        int childCount = currentContainer.getChildCount();
        View dragArea = childCount > 0 ? currentContainer.getChildAt(childCount - 1) : null;
        if (dragArea != null) {
          dragArea.setOnTouchListener(new CheckoutOverlayDragTouchListener(activity));
        }
        setupPopupWebView(webView, url, activity);
      } catch (Exception e) {
        Log.e(TAG, "Error creating WebView in checkout overlay: " + e.getMessage(), e);
        cleanupAllViews();
        return;
      }
      mainFrame.addView(currentContainer);
      currentDialog.setContentView(mainFrame);
      Window window = currentDialog.getWindow();
      if (window != null) {
        try {
          window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT,
              ViewGroup.LayoutParams.MATCH_PARENT);
          window.setFlags(WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
              WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED);
          window.setBackgroundDrawableResource(android.R.color.transparent);
          window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
          WindowManager.LayoutParams windowParams = window.getAttributes();
          windowParams.dimAmount = CardConstants.OVERLAY_ALPHA;
          window.setAttributes(windowParams);
        } catch (Exception e) {
          Log.e(TAG, "Error configuring checkout overlay window: " + e.getMessage(), e);
        }
      }
      currentContainer.setOnClickListener(v -> {});
      currentDialog.setCanceledOnTouchOutside(!isPurchaseProcessing);
      currentDialog.setCancelable(!isPurchaseProcessing);
      currentDialog.setOnDismissListener(dialog -> {
        try {
          if (!paymentSuccessHandled && listener != null) {
            listener.onDialogDismissed();
          }
        } catch (Exception e) {
          Log.e(TAG, "Error in checkout overlay dismiss listener: " + e.getMessage(), e);
        }
        cleanupAllViews();
        presentationUsesIsolatedWebviewProcess = false;
        isCurrentlyPresented = false;
      });
      currentDialog.show();
      DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
      currentContainer.setTranslationY(metrics.heightPixels);
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
        currentContainer.animate()
            .translationY(0)
            .setDuration(CardConstants.ANIMATION_DURATION_DEFAULT)
            .setInterpolator(new android.view.animation.DecelerateInterpolator())
            .start();
      } else {
        currentContainer.setTranslationY(0);
      }
      presentationUsesIsolatedWebviewProcess = false;
      isCurrentlyPresented = true;
    } catch (Exception e) {
      Log.e(TAG, "Error creating checkout overlay: " + e.getMessage(), e);
      cleanupAllViews();
    }
  }
  
  /**
   * Adds the same visual drag bar as Activity cards (no touch handling).
   */
  private void addCheckoutOverlayDragBar(Activity activity) {
    addVisualDragBarToContainer(activity, currentContainer);
  }

  /** Adds a visual-only drag bar to the given container (modal or overlay). No touch handling. */
  private void addVisualDragBarToContainer(Activity activity, FrameLayout container) {
    if (container == null || activity == null) {
      return;
    }
    try {
      LinearLayout dragArea = new LinearLayout(activity);
      dragArea.setOrientation(LinearLayout.VERTICAL);
      dragArea.setGravity(Gravity.CENTER_HORIZONTAL);
      int padH = StashWebViewUtils.dpToPx(activity, 20);
      int padTop =
          StashWebViewUtils.dpToPx(activity, Math.round(CardConstants.DRAG_HANDLE_TOP_INSET_DP));
      int padBottom =
          StashWebViewUtils.dpToPx(activity, Math.round(CardConstants.DRAG_TRAY_PADDING_BOTTOM_DP));
      dragArea.setPadding(padH, padTop, padH, padBottom);
      View handle = new View(activity);
      GradientDrawable handleBg = new GradientDrawable();
      handleBg.setColor(Color.parseColor(CardConstants.COLOR_DRAG_HANDLE));
      handleBg.setCornerRadius(
          StashWebViewUtils.dpToPx(activity, Math.round(CardConstants.DRAG_HANDLE_CORNER_RADIUS_DP)));
      handle.setBackground(handleBg);
      handle.setLayoutParams(new LinearLayout.LayoutParams(
          StashWebViewUtils.dpToPx(activity, (int) CardConstants.DRAG_HANDLE_WIDTH_DP),
          StashWebViewUtils.dpToPx(activity, (int) CardConstants.DRAG_HANDLE_HEIGHT_DP)));
      dragArea.addView(handle);
      FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
          StashWebViewUtils.dpToPx(activity, 120), FrameLayout.LayoutParams.WRAP_CONTENT);
      params.gravity = Gravity.TOP | Gravity.CENTER_HORIZONTAL;
      dragArea.setLayoutParams(params);
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        dragArea.setElevation(StashWebViewUtils.dpToPx(activity, 8));
      }
      container.addView(dragArea);
    } catch (Exception e) {
      Log.e(TAG, "Error adding visual drag bar: " + e.getMessage(), e);
    }
  }
}
