package com.stash.stashnative;

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
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Gravity;
import android.view.Surface;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewOutlineProvider;
import android.view.ViewTreeObserver;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.WebChromeClient;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import androidx.annotation.RequiresApi;
import java.lang.ref.WeakReference;

/**
 * Internal plugin that manages the WebView and dialog. {@link StashNativeCard} is the public API.
 *
 * <p>Holds the Activity through a WeakReference.
 */
public class StashNativeCardPlugin {
  private static final String TAG = "StashNativeCard";

  /** Thread-safe lazy singleton holder. */
  private static class Holder {
    static final StashNativeCardPlugin INSTANCE = new StashNativeCardPlugin();
  }
  
  private WeakReference<Activity> activityRef;
  /** Strong reference to the listener. */
  private volatile StashNativeCard.StashNativeCardListener listener;

  private Dialog currentDialog;
  private WebView webView;
  private FrameLayout currentContainer;
  private View loadingOverlayView;
  private ViewTreeObserver.OnGlobalLayoutListener orientationChangeListener;
  
  // Phone card: portrait height ratio (full width in portrait), plus landscape width and height ratios.
  private float cardHeightRatioPortrait = CardConstants.DEFAULT_CARD_HEIGHT_RATIO;
  private boolean forcePortraitOnCheckout = false;
  /** Card-presentation autoClose. Modal uses {@link #currentModalConfig}.autoClose. */
  private boolean cardAutoCloseOnPaymentEvent = true;
  private float cardWidthRatioLandscape = CardConstants.DEFAULT_CARD_WIDTH_RATIO_LANDSCAPE;
  private float cardHeightRatioLandscape = CardConstants.DEFAULT_CARD_HEIGHT_RATIO_LANDSCAPE;
  
  // Orientation-specific tablet card configuration
  private float tabletWidthRatioPortrait = CardConstants.DEFAULT_TABLET_WIDTH_RATIO_PORTRAIT;
  private float tabletHeightRatioPortrait = CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_PORTRAIT;
  private float tabletWidthRatioLandscape = CardConstants.DEFAULT_TABLET_WIDTH_RATIO_LANDSCAPE;
  private float tabletHeightRatioLandscape = CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_LANDSCAPE;
  
  /** Accessed from UI and JS threads; volatile for visibility. */
  private volatile boolean isCurrentlyPresented;
  /**
   * True only when checkout used a separate WebView OS process. With the default manifest,
   * {@link StashNativeCardPortraitActivity} runs in the host app process, this stays false, and
   * {@link #clearPresentationIfCheckoutProcessDied} is a no-op.
   */
  private volatile boolean presentationUsesIsolatedWebviewProcess;
  /** Accessed from UI and JS threads; volatile for visibility. */
  private volatile boolean paymentSuccessHandled;
  /** Accessed from UI and JS threads; volatile for visibility. */
  private volatile boolean isPurchaseProcessing;
  // Written by public open* on the caller thread, read inside openUrlInternal's runOnUiThread block.
  private volatile boolean usePopupPresentation;
  private volatile boolean useModalPresentation;
  private int lastOrientation = Configuration.ORIENTATION_UNDEFINED;
  
  // Modal configuration (used when useModalPresentation is true)
  private StashNativeCard.ModalConfig currentModalConfig;

  /** Normalized #hex from the last {@code openCard} config. Modal uses {@link #currentModalConfig}. */
  private String presentationBackgroundColorHex;
  
  private boolean useCustomSize;
  private float customPortraitWidthMultiplier = CardConstants.POPUP_PORTRAIT_WIDTH_MULTIPLIER;
  private float customPortraitHeightMultiplier = CardConstants.POPUP_PORTRAIT_HEIGHT_MULTIPLIER;
  private float customLandscapeWidthMultiplier = CardConstants.POPUP_LANDSCAPE_WIDTH_MULTIPLIER;
  private float customLandscapeHeightMultiplier = CardConstants.POPUP_LANDSCAPE_HEIGHT_MULTIPLIER;
  
  private long pageLoadStartTime;

  private BroadcastReceiver checkoutBridgeReceiver;
  private boolean checkoutBridgeReceiverRegistered;
  /** Application context captured at receiver registration; used by cleanup() to unregister. */
  private Context registeredAppContext;
  private boolean checkoutHostLifecycleRegistered;
  private Application.ActivityLifecycleCallbacks checkoutHostLifecycleCallbacks;
  private Runnable pendingHideLoadingRunnable;

  /** When true, a short foreground service may run while an external browser / Custom Tabs is open. */
  private volatile boolean keepAliveEnabled;
  private StashNativeCard.KeepAliveConfig keepAliveConfig;

  /** When true, host {@code onResume} fires {@link StashNativeCardListener#onBrowserClosed()}. */
  private boolean isBrowserSessionActive;
  /**
   * True while close-tracking is deferred after launching Custom Tabs / browser until the host is
   * paused by that UI or a short timeout elapses.
   */
  private boolean browserCloseTrackingPendingArm;
  private Runnable browserCloseTrackingArmRunnable;
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private static final long BROWSER_CLOSE_TRACK_ARM_DELAY_MS = 400L;
  /**
   * Posted on host {@code onResume}. Invokes {@link StashNativeCardListener#onBrowserClosed()} only
   * after the host stays resumed past this delay; cancelled if the host pauses again.
   */
  private Runnable browserClosedDebounceRunnable;
  private static final long BROWSER_CLOSED_RESUME_DEBOUNCE_MS = 500L;
  /**
   * True while {@link StashNativeBrowserProxyActivity} is awaiting a Custom Tabs result.
   * Dedup gate between proxy {@code onActivityResult} and the engagement-session-ended path.
   */
  private boolean browserCloseAwaitingCctResult;

  /**
   * Set for portrait checkout. Run on the main thread after {@code onBrowserClosed} to dismiss
   * checkout once the tab was started and closed.
   */
  private Runnable pendingCheckoutDismissAfterExternalBrowser;

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
      Log.w(TAG, "Error checking stash_webview process: " + e.getMessage(), e);
    }
    return false;
  }

  /**
   * If checkout used an isolated WebView process and that process died without sending a broadcast,
   * clears state and calls {@link StashNativeCard.StashNativeCardListener#onNetworkError()} once the
   * host activity resumes. No-op when {@link #presentationUsesIsolatedWebviewProcess} is false.
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
    StashNativeCard.StashNativeCardListener l = getListener();
    if (l != null) {
      try {
        l.onNetworkError();
      } catch (Exception e) {
        Log.w(TAG, "Error notifying checkout process death: " + e.getMessage(), e);
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
    checkoutHostLifecycleCallbacks = new Application.ActivityLifecycleCallbacks() {
      @Override
      public void onActivityResumed(Activity activity) {
        Activity host = getActivity();
        if (host != null && activity == host) {
          clearPresentationIfCheckoutProcessDied(activity);
          stopKeepAliveForegroundService(activity.getApplicationContext());
          if (isBrowserSessionActive && !browserCloseAwaitingCctResult) {
            scheduleBrowserClosedDebounce();
          }
        }
      }

      @Override public void onActivityCreated(Activity a, Bundle b) {}

      @Override public void onActivityStarted(Activity a) {}

      @Override
      public void onActivityPaused(Activity activity) {
        Activity host = getActivity();
        if (host == null || activity != host) {
          return;
        }
        if (browserCloseTrackingPendingArm) {
          if (browserCloseTrackingArmRunnable != null) {
            mainHandler.removeCallbacks(browserCloseTrackingArmRunnable);
            browserCloseTrackingArmRunnable = null;
          }
          browserCloseTrackingPendingArm = false;
          isBrowserSessionActive = true;
        }
        if (isBrowserSessionActive) {
          cancelBrowserClosedDebounce();
        }
      }

      @Override public void onActivityStopped(Activity a) {}

      @Override public void onActivitySaveInstanceState(Activity a, Bundle b) {}

      @Override public void onActivityDestroyed(Activity a) {}
    };
    app.registerActivityLifecycleCallbacks(checkoutHostLifecycleCallbacks);
    checkoutHostLifecycleRegistered = true;
  }

  /**
   * Registers a package-local receiver that delivers events from
   * {@link StashNativeCardPortraitActivity} to {@link StashNativeCard.StashNativeCardListener} on
   * the main thread.
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
        mainHandler.post(() -> dispatchCheckoutBridgeIntent(action, intentCopy));
      }
    };
    IntentFilter filter = new IntentFilter();
    filter.addAction(CardConstants.BROADCAST_CHECKOUT_PAYMENT_SUCCESS);
    filter.addAction(CardConstants.BROADCAST_CHECKOUT_PAYMENT_FAILURE);
    filter.addAction(CardConstants.BROADCAST_CHECKOUT_OPT_IN);
    filter.addAction(CardConstants.BROADCAST_CHECKOUT_NETWORK_ERROR);
    filter.addAction(CardConstants.BROADCAST_CHECKOUT_DIALOG_DISMISSED);
    try {
      // Registers via the platform API. RECEIVER_NOT_EXPORTED on API 33+, no flag below.
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        app.registerReceiver(checkoutBridgeReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
      } else {
        app.registerReceiver(checkoutBridgeReceiver, filter);
      }
      checkoutBridgeReceiverRegistered = true;
      registeredAppContext = app;
    } catch (Exception e) {
      Log.e(TAG, "Failed to register checkout bridge receiver: " + e.getMessage(), e);
    }
    ensureCheckoutHostLifecycle(context);
  }

  private void dispatchCheckoutBridgeIntent(String action, Intent intent) {
    StashNativeCard.StashNativeCardListener l = getListener();
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
        String order = intent.getStringExtra(CardConstants.BROADCAST_EXTRA_PAYMENT_ORDER);
        l.onPaymentSuccess(order);
      } else if (CardConstants.BROADCAST_CHECKOUT_PAYMENT_FAILURE.equals(action)) {
        l.onPaymentFailure();
      } else if (CardConstants.BROADCAST_CHECKOUT_NETWORK_ERROR.equals(action)) {
        l.onNetworkError();
      } else if (CardConstants.BROADCAST_CHECKOUT_DIALOG_DISMISSED.equals(action)) {
        l.onDialogDismissed();
      }
    } catch (Exception e) {
      Log.w(TAG, "Error dispatching checkout bridge: " + e.getMessage(), e);
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

  private StashNativeCard.StashNativeCardListener getListener() {
    return listener;
  }

  /**
   * Runs the given runnable on the main thread, then dismisses the current dialog.
   */
  private void runOnMainAndDismiss(Runnable beforeDismiss) {
    mainHandler.post(() -> {
      try {
        if (beforeDismiss != null) {
          beforeDismiss.run();
        }
        dismissCurrentDialog();
      } catch (Exception e) {
        Log.w(TAG, "Error in runOnMainAndDismiss: " + e.getMessage(), e);
        cleanupAllViews();
      }
    });
  }

  private class StashJavaScriptInterface implements StashCheckoutBridgeApi {
    @JavascriptInterface
    public void onPaymentSuccess(String order) {
      if (paymentSuccessHandled) {
        return;
      }
      paymentSuccessHandled = true;
      isPurchaseProcessing = false;
      final String orderPayload = order;
      runOnMainAndDismiss(() -> {
        StashNativeCard.StashNativeCardListener l = getListener();
        if (l != null) {
          l.onPaymentSuccess(orderPayload);
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
        StashNativeCard.StashNativeCardListener l = getListener();
        if (l != null) {
          l.onPaymentFailure();
        }
      });
    }

    @JavascriptInterface
    public void onPurchaseProcessing() {
      isPurchaseProcessing = true;
      mainHandler.post(() -> {
        try {
          if (currentDialog != null && currentDialog.isShowing()) {
            currentDialog.setCanceledOnTouchOutside(false);
            currentDialog.setCancelable(false);
          }
        } catch (Exception e) {
          Log.w(TAG, "Error updating dialog dismissibility: " + e.getMessage(), e);
        }
      });
    }
    
    @JavascriptInterface
    public void setPaymentChannel(String optinType) {
      runOnMainAndDismiss(() -> {
        StashNativeCard.StashNativeCardListener l = getListener();
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
      if (isPurchaseProcessing) {
        return;
      }
      mainHandler.post(() -> {
        try {
          dismissCurrentDialog();
        } catch (Exception e) {
          Log.w(TAG, "Error in requestCloseFromPage: " + e.getMessage(), e);
        }
      });
    }

    @JavascriptInterface
    public void openExternalBrowser(String url) {
      mainHandler.post(() -> {
        try {
          String normalized = StashWebViewUtils.normalizeExternalPaymentUrl(url);
          if (normalized == null) {
            return;
          }
          Activity activity = getActivity();
          if (activity == null) {
            return;
          }
          // URLs handed to an external browser carry no theme query parameter.
          paymentSuccessHandled = true;
          isPurchaseProcessing = false;
          StashNativeCard.StashNativeCardListener listener = getListener();
          if (listener != null) {
            listener.onExternalPayment(normalized);
          }
          dismissCurrentDialog();
          Activity act = getActivity();
          if (act == null || normalized.isEmpty()) {
            return;
          }
          startKeepAliveBeforeBrowser(act);
          launchExternalBrowser(act, normalized);
        } catch (Exception e) {
          cancelBrowserCloseTrackingLaunch();
          Log.w(TAG, "Error in openExternalBrowser: " + e.getMessage(), e);
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
   * Stores the Activity in a WeakReference and registers the checkout bridge receiver.
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

  void setKeepAliveEnabled(boolean enabled) {
    this.keepAliveEnabled = enabled;
  }

  boolean isKeepAliveEnabled() {
    return keepAliveEnabled;
  }

  void setKeepAliveConfig(StashNativeCard.KeepAliveConfig config) {
    this.keepAliveConfig = config;
  }

  /**
   * Starts the optional keep-alive foreground service before opening Custom Tabs / browser.
   */
  void startKeepAliveBeforeBrowser(Context context) {
    if (!keepAliveEnabled || context == null) {
      return;
    }
    try {
      Context app = context.getApplicationContext();
      StashKeepAliveService.start(
          app,
          resolveKeepAliveTitle(app),
          resolveKeepAliveText(app),
          resolveKeepAliveIconResId());
    } catch (Exception e) {
      Log.w(TAG, "Keep-alive start failed: " + e.getMessage(), e);
    }
  }

  void stopKeepAliveForegroundService(Context context) {
    StashKeepAliveService.stop(context);
  }

  void cancelBrowserCloseTrackingLaunch() {
    if (browserCloseTrackingArmRunnable != null) {
      mainHandler.removeCallbacks(browserCloseTrackingArmRunnable);
      browserCloseTrackingArmRunnable = null;
    }
    browserCloseTrackingPendingArm = false;
    browserCloseAwaitingCctResult = false;
    cancelBrowserClosedDebounce();
  }

  private void executePendingCheckoutDismiss() {
    Runnable r = pendingCheckoutDismissAfterExternalBrowser;
    pendingCheckoutDismissAfterExternalBrowser = null;
    if (r != null) {
      mainHandler.post(r);
    }
  }

  /**
   * Clears the pending external-browser checkout dismiss without running it, and cancels
   * browser-close tracking.
   */
  void abandonPendingExternalBrowserCheckoutDismiss() {
    pendingCheckoutDismissAfterExternalBrowser = null;
    cancelBrowserCloseTrackingLaunch();
  }

  private void invokeBrowserClosedListenerAndDismissCheckout() {
    StashNativeCard.StashNativeCardListener l = getListener();
    if (l != null) {
      try {
        l.onBrowserClosed();
      } catch (Exception e) {
        Log.w(TAG, "Error in onBrowserClosed: " + e.getMessage(), e);
      }
    }
    executePendingCheckoutDismiss();
  }

  /**
   * Opens Custom Tabs from portrait checkout using {@code checkoutActivity} for {@code
   * startActivityForResult}. {@code hideCheckoutChromeWhileBrowserOpen} runs on the main thread
   * after the URL launcher returns. {@code dismissAfterBrowserClosed} runs after
   * {@link StashNativeCardListener#onBrowserClosed()}, or immediately if the URL cannot be opened.
   */
  void openExternalBrowserFromCheckout(
      Activity checkoutActivity,
      String url,
      boolean notifyExternalPaymentListener,
      Runnable hideCheckoutChromeWhileBrowserOpen,
      Runnable dismissAfterBrowserClosed) {
    if (checkoutActivity == null || url == null || url.isEmpty()) {
      cancelBrowserCloseTrackingLaunch();
      if (dismissAfterBrowserClosed != null) {
        mainHandler.post(dismissAfterBrowserClosed);
      }
      return;
    }
    presentationUsesIsolatedWebviewProcess = false;
    isCurrentlyPresented = false;
    if (notifyExternalPaymentListener) {
      StashNativeCard.StashNativeCardListener l = getListener();
      if (l != null) {
        l.onExternalPayment(url);
      }
    }
    pendingCheckoutDismissAfterExternalBrowser = dismissAfterBrowserClosed;
    try {
      startKeepAliveBeforeBrowser(checkoutActivity);
      launchExternalBrowser(checkoutActivity, url);
      if (hideCheckoutChromeWhileBrowserOpen != null) {
        mainHandler.post(hideCheckoutChromeWhileBrowserOpen);
      }
    } catch (Exception e) {
      cancelBrowserCloseTrackingLaunch();
      executePendingCheckoutDismiss();
      Log.w(TAG, "Error opening external browser from checkout: " + e.getMessage(), e);
    }
  }

  private void cancelBrowserClosedDebounce() {
    if (browserClosedDebounceRunnable != null) {
      mainHandler.removeCallbacks(browserClosedDebounceRunnable);
      browserClosedDebounceRunnable = null;
    }
  }

  private void scheduleBrowserClosedDebounce() {
    cancelBrowserClosedDebounce();
    browserClosedDebounceRunnable = () -> {
      browserClosedDebounceRunnable = null;
      if (!isBrowserSessionActive) {
        return;
      }
      isBrowserSessionActive = false;
      invokeBrowserClosedListenerAndDismissCheckout();
    };
    mainHandler.postDelayed(browserClosedDebounceRunnable, BROWSER_CLOSED_RESUME_DEBOUNCE_MS);
  }

  /**
   * Arms host-resume close tracking after {@link StashUrlLauncher#openExternalUrl(Context, String,
   * int)} when Custom Tabs did not use {@code startActivityForResult}.
   */
  void beginBrowserCloseTrackingAfterExternalUrlLaunched() {
    cancelBrowserCloseTrackingLaunch();
    isBrowserSessionActive = false;
    browserCloseTrackingPendingArm = true;
    browserCloseTrackingArmRunnable = () -> {
      browserCloseTrackingArmRunnable = null;
      if (browserCloseTrackingPendingArm) {
        browserCloseTrackingPendingArm = false;
        isBrowserSessionActive = true;
      }
    };
    mainHandler.postDelayed(browserCloseTrackingArmRunnable, BROWSER_CLOSE_TRACK_ARM_DELAY_MS);
  }

  /**
   * Marks the plugin as awaiting a Custom Tabs close. Called before starting {@link
   * StashNativeBrowserProxyActivity}. The proxy's {@code onActivityResult} and the
   * engagement-session-ended path dedupe through this gate.
   */
  void beginBrowserCloseTrackingActivityResult() {
    cancelBrowserCloseTrackingLaunch();
    browserCloseAwaitingCctResult = true;
  }

  void applyBrowserCloseTrackingForLaunchMode(int launchMode) {
    if (launchMode == StashUrlLauncher.OPEN_EXTERNAL_CCT_ACTIVITY_FOR_RESULT) {
      beginBrowserCloseTrackingActivityResult();
    } else {
      beginBrowserCloseTrackingAfterExternalUrlLaunched();
    }
  }

  /**
   * Called when Chrome reports the Custom Tab session ended via engagement signals (including
   * dismiss from floating/minimized UI).
   */
  void onCustomTabsEngagementSessionEnded() {
    if (!browserCloseAwaitingCctResult) {
      return;
    }
    cancelBrowserCloseTrackingLaunch();
    invokeBrowserClosedListenerAndDismissCheckout();
  }

  /**
   * Called by {@link StashNativeBrowserProxyActivity} when Custom Tabs delivered its
   * activity result (or the orphan-resume fallback fired). Unbinds the engagement
   * service and dispatches {@link StashNativeCard.StashNativeCardListener#onBrowserClosed()}
   * via the shared close-tracking gate.
   */
  void notifyBrowserClosedFromProxyInternal() {
    Activity hostOrNull = getActivity();
    Context unbindCtx = hostOrNull != null ? hostOrNull : registeredAppContext;
    if (unbindCtx != null) {
      StashUrlLauncher.unbindCustomTabsEngagement(unbindCtx);
    }
    if (!browserCloseAwaitingCctResult) {
      return;
    }
    cancelBrowserCloseTrackingLaunch();
    invokeBrowserClosedListenerAndDismissCheckout();
  }

  /** Bridge from {@link StashNativeBrowserProxyActivity}'s engagement-session-ended callback. */
  void notifyBrowserEngagementSessionEndedFromProxyInternal() {
    onCustomTabsEngagementSessionEnded();
  }

  /**
   * Launches the URL in Chrome Custom Tabs via {@link StashNativeBrowserProxyActivity}
   * when {@code androidx.browser} is on the classpath, otherwise falls back to the
   * lifecycle-tracked ACTION_VIEW path on the host activity directly.
   */
  private void launchExternalBrowser(Activity activity, String url) {
    if (activity == null || url == null || url.isEmpty()) {
      return;
    }
    if (StashUrlLauncher.isCustomTabsClassAvailable()) {
      beginBrowserCloseTrackingActivityResult();
      Intent intent = new Intent(activity, StashNativeBrowserProxyActivity.class);
      intent.putExtra(StashNativeBrowserProxyActivity.EXTRA_URL, url);
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_ANIMATION);
      activity.startActivity(intent);
      return;
    }
    int mode = StashUrlLauncher.openExternalUrl(activity, url);
    applyBrowserCloseTrackingForLaunchMode(mode);
  }

  private String resolveKeepAliveTitle(Context ctx) {
    if (keepAliveConfig != null
        && keepAliveConfig.notificationTitle != null
        && !keepAliveConfig.notificationTitle.trim().isEmpty()) {
      return keepAliveConfig.notificationTitle.trim();
    }
    return ctx.getString(R.string.stash_keep_alive_title);
  }

  private String resolveKeepAliveText(Context ctx) {
    if (keepAliveConfig != null
        && keepAliveConfig.notificationText != null
        && !keepAliveConfig.notificationText.trim().isEmpty()) {
      return keepAliveConfig.notificationText.trim();
    }
    return ctx.getString(R.string.stash_keep_alive_text);
  }

  private int resolveKeepAliveIconResId() {
    if (keepAliveConfig != null && keepAliveConfig.notificationIconResId != 0) {
      return keepAliveConfig.notificationIconResId;
    }
    return R.drawable.ic_stash_keep_alive;
  }

  /**
   * Opens the given URL as a sliding bottom sheet rendered in {@link StashNativeCardPortraitActivity}.
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
        this.cardAutoCloseOnPaymentEvent = config.autoClose;
        this.presentationBackgroundColorHex =
            StashBackgroundColorUtils.normalizeHexOrNull(config.backgroundColor);
      } else {
        this.cardAutoCloseOnPaymentEvent = true;
        this.presentationBackgroundColorHex = null;
      }
      usePopupPresentation = false;
      useModalPresentation = false;
      openUrlInternal(url);
    } catch (Exception e) {
      Log.w(TAG, "Error in openCard: " + e.getMessage(), e);
      cleanupAllViews();
    }
  }

  /**
   * Opens the URL via {@link StashUrlLauncher#openExternalUrl(Context, String)} (Custom Tabs when
   * available, else system browser).
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
      // External browser URLs are opened as-is, with no theme query parameter.
      final String finalUrl = url;
      final Activity finalActivity = activity;
      activity.runOnUiThread(() -> {
        try {
          startKeepAliveBeforeBrowser(finalActivity);
          launchExternalBrowser(finalActivity, finalUrl);
        } catch (Exception e) {
          cancelBrowserCloseTrackingLaunch();
          Log.w(TAG, "Error in openBrowser: " + e.getMessage(), e);
        }
      });
    } catch (Exception e) {
      Log.w(TAG, "Error in openBrowser: " + e.getMessage(), e);
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
      Log.w(TAG, "Error in openPopup: " + e.getMessage(), e);
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
      // Popup multipliers are not clamped to [0.1,1.0] (defaults exceed 1.0), but a
      // degenerate <=0/NaN value would collapse the popup; fall back to the default instead.
      customPortraitWidthMultiplier = sanitizePopupMultiplier(
          portraitWidthMultiplier, CardConstants.POPUP_PORTRAIT_WIDTH_MULTIPLIER);
      customPortraitHeightMultiplier = sanitizePopupMultiplier(
          portraitHeightMultiplier, CardConstants.POPUP_PORTRAIT_HEIGHT_MULTIPLIER);
      customLandscapeWidthMultiplier = sanitizePopupMultiplier(
          landscapeWidthMultiplier, CardConstants.POPUP_LANDSCAPE_WIDTH_MULTIPLIER);
      customLandscapeHeightMultiplier = sanitizePopupMultiplier(
          landscapeHeightMultiplier, CardConstants.POPUP_LANDSCAPE_HEIGHT_MULTIPLIER);
      useCustomSize = true;
      openUrlInternal(url);
    } catch (Exception e) {
      Log.w(TAG, "Error in openPopupWithSize: " + e.getMessage(), e);
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
      StashNativeCard.ModalConfig mc = config != null ? config : new StashNativeCard.ModalConfig();
      mc.phoneWidthRatioPortrait = clampRatio(mc.phoneWidthRatioPortrait);
      mc.phoneHeightRatioPortrait = clampRatio(mc.phoneHeightRatioPortrait);
      mc.phoneWidthRatioLandscape = clampRatio(mc.phoneWidthRatioLandscape);
      mc.phoneHeightRatioLandscape = clampRatio(mc.phoneHeightRatioLandscape);
      mc.tabletWidthRatioPortrait = clampRatio(mc.tabletWidthRatioPortrait);
      mc.tabletHeightRatioPortrait = clampRatio(mc.tabletHeightRatioPortrait);
      mc.tabletWidthRatioLandscape = clampRatio(mc.tabletWidthRatioLandscape);
      mc.tabletHeightRatioLandscape = clampRatio(mc.tabletHeightRatioLandscape);
      currentModalConfig = mc;
      openUrlInternal(url);
    } catch (Exception e) {
      Log.w(TAG, "Error in openModal: " + e.getMessage(), e);
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
        Log.w(TAG, "Error dismissing dialog: " + e.getMessage());
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
      cleanup();
    } catch (Exception e) {
      Log.w(TAG, "Error in resetPresentationState: " + e.getMessage(), e);
      cleanupAllViews();
    }
  }

  public void cleanup() {
    cleanupAllViews();
    Context appContext = registeredAppContext;
    if (appContext == null) {
      Activity activity = getActivity();
      appContext = activity != null ? activity.getApplicationContext() : null;
    }
    if (checkoutBridgeReceiverRegistered && appContext != null && checkoutBridgeReceiver != null) {
      try {
        appContext.unregisterReceiver(checkoutBridgeReceiver);
      } catch (Exception e) {
        Log.w(TAG, "Error unregistering checkout bridge receiver: " + e.getMessage(), e);
      }
      checkoutBridgeReceiverRegistered = false;
      checkoutBridgeReceiver = null;
    }
    if (checkoutHostLifecycleRegistered && appContext instanceof Application
        && checkoutHostLifecycleCallbacks != null) {
      try {
        ((Application) appContext).unregisterActivityLifecycleCallbacks(checkoutHostLifecycleCallbacks);
      } catch (Exception e) {
        Log.w(TAG, "Error unregistering lifecycle callbacks: " + e.getMessage(), e);
      }
      checkoutHostLifecycleRegistered = false;
      checkoutHostLifecycleCallbacks = null;
    }
    registeredAppContext = null;
    pendingCheckoutDismissAfterExternalBrowser = null;
    cancelBrowserCloseTrackingLaunch();
    isBrowserSessionActive = false;
  }

  /**
   * Returns whether a checkout UI is currently presented.
   *
   * @return true if presented
   */
  public boolean isCurrentlyPresented() {
    return isCurrentlyPresented;
  }

  // ============================================================================
  // Orientation-Specific Phone Card Size Configuration
  // ============================================================================

  // Clamps a ratio to [0.1, 1.0].
  static float clampRatio(float ratio) {
    return Math.max(0.1f, Math.min(1.0f, ratio));
  }

  /** Returns {@code value}, or {@code fallback} when {@code value} is NaN or <= 0. */
  static float sanitizePopupMultiplier(float value, float fallback) {
    return (Float.isNaN(value) || value <= 0f) ? fallback : value;
  }

  /** Hex string for the upcoming portrait activity / theme query, or null for system default. */
  private String backgroundColorHexForPresentation() {
    if (useModalPresentation && currentModalConfig != null) {
      return StashBackgroundColorUtils.normalizeHexOrNull(currentModalConfig.backgroundColor);
    }
    return presentationBackgroundColorHex;
  }

  /**
   * Returns whether a purchase is currently being processed.
   *
   * @return true if processing
   */
  public boolean isPurchaseProcessing() {
    return isPurchaseProcessing;
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
        String bgHex = backgroundColorHexForPresentation();
        url = StashWebViewUtils.appendThemeQueryParameter(url,
            StashWebViewUtils.effectiveDarkThemeForCheckout(activity, bgHex));
      } catch (Exception e) {
        Log.d(TAG, "Error appending theme parameter: " + e.getMessage(), e);
      }

      final String finalUrl = url;
      final Activity finalActivity = activity;

      activity.runOnUiThread(() -> {
        try {
          if (usePopupPresentation) {
            createAndShowPopupDialog(finalUrl, finalActivity);
          } else {
            // Card and modal both launch PortraitActivity in the host app process. The Activity
            // reads the useModal flag from the Intent and calls createModal() or createCard().
            launchPortraitActivity(finalUrl, finalActivity);
          }
        } catch (Exception e) {
          Log.w(TAG, "Error in UI thread operation: " + e.getMessage(), e);
          cleanupAllViews();
        }
      });
    } catch (Exception e) {
      Log.w(TAG, "Error in openUrlInternal: " + e.getMessage(), e);
      cleanupAllViews();
    }
  }
  
  private void launchPortraitActivity(String url, Activity activity) {
    try {
      paymentSuccessHandled = false;
      int rotation;
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        android.view.Display display = activity.getDisplay();
        rotation = display != null ? display.getRotation() : Surface.ROTATION_0;
      } else {
        @SuppressWarnings("deprecation")
        android.view.Display display = activity.getWindowManager().getDefaultDisplay();
        rotation = display.getRotation();
      }
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
      String bgForIntent = backgroundColorHexForPresentation();
      if (bgForIntent != null) {
        intent.putExtra(CardConstants.INTENT_EXTRA_BACKGROUND_COLOR, bgForIntent);
      }

      boolean autoCloseForIntent = useModalPresentation && currentModalConfig != null
          ? currentModalConfig.autoClose
          : cardAutoCloseOnPaymentEvent;
      intent.putExtra(CardConstants.INTENT_EXTRA_AUTO_CLOSE, autoCloseForIntent);

      // Pass modal config if in modal mode
      intent.putExtra(CardConstants.INTENT_EXTRA_HOST_DISPLAY_ROTATION, rotation);

      if (useModalPresentation && currentModalConfig != null) {
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
      
      // Launched in the host app's task (no NEW_TASK / MULTIPLE_TASK flag).
      intent.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION);

      activity.startActivity(intent);
      activity.overridePendingTransition(0, 0);
      isCurrentlyPresented = true;
    } catch (Exception e) {
      Log.e(TAG, "Failed to launch Activity: " + e.getMessage());
      // Checkout did not start. Notify the host via onNetworkError().
      StashNativeCard.StashNativeCardListener l = getListener();
      if (l != null) {
        try {
          l.onNetworkError();
        } catch (Throwable t) {
          Log.w(TAG, "onNetworkError threw: " + t.getMessage());
        }
      }
    }
  }
  
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
                newDimensions = plugin.calculateModalDimensions(activity);
              } else {
                newDimensions = plugin.calculatePopupDimensions(activity);
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
        Log.d(TAG, "Error setting background color: " + e.getMessage(), e);
        mainFrame.setBackgroundColor(Color.parseColor(CardConstants.COLOR_BACKGROUND_DIM));
      }
      
      mainFrame.setOnClickListener(v -> {
        try {
          if (!isPurchaseProcessing && currentDialog != null && currentDialog.isShowing()
              && v == mainFrame) {
            currentDialog.dismiss();
          }
        } catch (Exception e) {
          Log.d(TAG, "Error in click handler: " + e.getMessage(), e);
        }
      });

      int[] dimensions;
      try {
        dimensions = calculatePopupDimensions(activity);
      } catch (Exception e) {
        Log.d(TAG, "Error calculating dimensions: " + e.getMessage(), e);
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
        Log.d(TAG, "Error getting orientation: " + e.getMessage(), e);
        lastOrientation = Configuration.ORIENTATION_PORTRAIT;
      }
      
      orientationChangeListener = new PopupOrientationListener(activity, this);
      try {
        mainFrame.getViewTreeObserver().addOnGlobalLayoutListener(orientationChangeListener);
      } catch (Exception e) {
        Log.d(TAG, "Error adding layout listener: " + e.getMessage(), e);
      }
      
      try {
        GradientDrawable popupBg = new GradientDrawable();
        popupBg.setColor(StashWebViewUtils.getThemeBackgroundColor(activity));
        float radius = StashWebViewUtils.dpToPx(activity, (int) CardConstants.CORNER_RADIUS_DP);
        popupBg.setCornerRadius(radius);
        currentContainer.setBackground(popupBg);
        
        currentContainer.setElevation(
            StashWebViewUtils.dpToPx(activity, (int) CardConstants.ELEVATION_DP));
        currentContainer.setOutlineProvider(new ViewOutlineProvider() {
          @Override
          public void getOutline(View view, Outline outline) {
            try {
              outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), radius);
            } catch (Exception e) {
              Log.d(TAG, "Error setting outline: " + e.getMessage(), e);
            }
          }
        });
        currentContainer.setClipToOutline(true);
      } catch (Exception e) {
        Log.d(TAG, "Error setting container background: " + e.getMessage(), e);
      }
      
      try {
        try {
          webView = new WebView(activity);
        } catch (Throwable t) {
          // WebView constructor can throw in separate processes or broken Chromium installs.
          Log.e(TAG, "WebView creation failed: " + t.getMessage(), t);
          StashNativeCard.StashNativeCardListener l = listener;
          if (l != null) l.onNetworkError();
          cleanupAllViews();
          return;
        }
        FrameLayout.LayoutParams webViewParams = new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
        webView.setLayoutParams(webViewParams);
        currentContainer.addView(webView);

        setupPopupWebView(webView, url, activity);
      } catch (Exception e) {
        Log.w(TAG, "Error creating WebView: " + e.getMessage(), e);
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
          // Resizes the popup window when the soft keyboard appears.
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

      currentContainer.setOnClickListener(v -> {});
      
      currentDialog.setCanceledOnTouchOutside(!isPurchaseProcessing);
      currentDialog.setCancelable(!isPurchaseProcessing);

      currentDialog.setOnDismissListener(dialog -> {
        try {
          StashNativeCard.StashNativeCardListener l = getListener();
          if (!paymentSuccessHandled && l != null) {
            l.onDialogDismissed();
          }
        } catch (Exception e) {
          Log.d(TAG, "Error in dismiss listener: " + e.getMessage(), e);
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
        Log.w(TAG, "Error showing dialog: " + e.getMessage(), e);
        cleanupAllViews();
      }
    } catch (Exception e) {
      Log.w(TAG, "Error creating popup: " + e.getMessage(), e);
      cleanupAllViews();
    }
  }
  
  private void animateFadeIn() {
    try {
      if (currentContainer != null) {
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
      Log.d(TAG, "Error in animateFadeIn: " + e.getMessage(), e);
    }
  }
  
  private void dismissPopupDialog() {
    try {
      if (currentDialog != null && currentContainer != null) {
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
                Log.d(TAG, "Error dismissing dialog in animation: " + e.getMessage(), e);
              }
            })
            .start();
      } else if (currentDialog != null) {
        currentDialog.dismiss();
      }
    } catch (Exception e) {
      Log.d(TAG, "Error in dismissPopupDialog: " + e.getMessage(), e);
      try {
        if (currentDialog != null) {
          currentDialog.dismiss();
        }
      } catch (Exception e2) {
        Log.d(TAG, "Error force dismissing dialog: " + e2.getMessage(), e2);
      }
    }
  }
  
  /**
   * Handles a crashed or killed WebView renderer: removes the UI and calls
   * {@link StashNativeCard.StashNativeCardListener#onNetworkError()}. Caller returns {@code true}
   * from {@link WebViewClient#onRenderProcessGone} (API 26+).
   */
  @RequiresApi(Build.VERSION_CODES.O)
  private void handleWebViewRenderProcessGone(RenderProcessGoneDetail detail) {
    Log.e(TAG, "WebView render process gone (didCrash=" + detail.didCrash() + ")");
    try {
      if (currentDialog != null) {
        try {
          currentDialog.setOnDismissListener(null);
        } catch (Exception e) {
          Log.d(TAG, "Error clearing dismiss listener: " + e.getMessage(), e);
        }
      }
      cleanupAllViews();
      presentationUsesIsolatedWebviewProcess = false;
      isCurrentlyPresented = false;
      StashNativeCard.StashNativeCardListener l = getListener();
      if (l != null) {
        l.onNetworkError();
      }
    } catch (Exception e) {
      Log.w(TAG, "Error recovering from render process gone: " + e.getMessage(), e);
    }
  }

  private int dialogSheetBackgroundArgb(Activity activity) {
    if (useModalPresentation && currentModalConfig != null) {
      Integer c = StashBackgroundColorUtils.parseSolidColorOrNull(currentModalConfig.backgroundColor);
      if (c != null) {
        return c;
      }
    }
    return StashWebViewUtils.getThemeBackgroundColor(activity);
  }

  private boolean dialogEffectiveDarkForWeb(Activity activity) {
    if (useModalPresentation && currentModalConfig != null) {
      Integer c = StashBackgroundColorUtils.parseSolidColorOrNull(currentModalConfig.backgroundColor);
      if (c != null) {
        return StashBackgroundColorUtils.isDarkBackground(c);
      }
    }
    return StashWebViewUtils.isDarkTheme(activity);
  }

  private void setupPopupWebView(WebView webView, String url, final Activity activity) {
    if (webView == null || activity == null || url == null || url.isEmpty()) {
      Log.e(TAG, "Invalid parameters in setupPopupWebView");
      return;
    }

    final int sheetBg = dialogSheetBackgroundArgb(activity);
    final boolean effDark = dialogEffectiveDarkForWeb(activity);

    try {
      StashWebViewUtils.configureWebViewSettings(webView, effDark);
    } catch (Exception e) {
      Log.d(TAG, "Error configuring WebView settings: " + e.getMessage(), e);
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
          Log.d(TAG, "Error in onPageStarted: " + e.getMessage(), e);
        }
      }
      
      @Override
      public void onPageFinished(WebView view, String url) {
        try {
          super.onPageFinished(view, url);
          
          if (pageLoadStartTime > 0) {
            long loadTimeMs = System.currentTimeMillis() - pageLoadStartTime;
            try {
              StashNativeCard.StashNativeCardListener l = getListener();
              if (l != null) {
                l.onPageLoaded(loadTimeMs);
              }
            } catch (Exception e) {
              Log.d(TAG, "Error sending page loaded message: " + e.getMessage(), e);
            }
            pageLoadStartTime = 0;
          }
          
          injectStashSDKFunctions();
          pendingHideLoadingRunnable = () -> {
            try {
              hideLoadingIndicator(activity);
              view.setVisibility(View.VISIBLE);
            } catch (Exception e) {
              Log.d(TAG, "Error in delayed page finished handler: " + e.getMessage(), e);
            }
          };
          view.postDelayed(pendingHideLoadingRunnable, CardConstants.HIDE_LOADING_DELAY_MS);
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
      webView.setBackgroundColor(sheetBg);
      // Shows the loading overlay before loadUrl(), ahead of the first onPageStarted callback.
      if (currentContainer != null && loadingOverlayView == null) {
        loadingOverlayView = StashWebViewUtils.createAndShowLoadingView(activity, currentContainer,
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
      Log.d(TAG, "Error injecting SDK functions: " + e.getMessage(), e);
    }
  }
  
  private void showLoadingIndicator(Activity activity) {
    if (currentContainer == null || activity == null) {
      return;
    }
    try {
      activity.runOnUiThread(() -> {
        try {
          // If the overlay is already attached, brings it to front instead of recreating it.
          if (loadingOverlayView != null && loadingOverlayView.getParent() != null) {
            loadingOverlayView.setVisibility(View.VISIBLE);
            loadingOverlayView.bringToFront();
            return;
          }
          int sheetBg = dialogSheetBackgroundArgb(activity);
          loadingOverlayView = StashWebViewUtils.createAndShowLoadingView(activity, currentContainer,
              sheetBg, StashBackgroundColorUtils.spinnerAccentFor(sheetBg));
        } catch (Exception e) {
          Log.d(TAG, "Error showing loading indicator: " + e.getMessage(), e);
        }
      });
    } catch (Exception e) {
      Log.d(TAG, "Error scheduling loading indicator: " + e.getMessage(), e);
    }
  }
  
  private void hideLoadingIndicator(Activity activity) {
    if (loadingOverlayView == null || activity == null) {
      return;
    }
    try {
      activity.runOnUiThread(() -> {
        try {
          StashWebViewUtils.hideLoadingOverlay(loadingOverlayView);
          loadingOverlayView = null;
        } catch (Exception e) {
          Log.d(TAG, "Error hiding loading indicator: " + e.getMessage(), e);
          loadingOverlayView = null;
        }
      });
    } catch (Exception e) {
      Log.d(TAG, "Error scheduling hide loading indicator: " + e.getMessage(), e);
    }
  }
  
  private void dismissCurrentDialog() {
    try {
      if (currentDialog != null) {
        dismissPopupDialog();
      }
    } catch (Exception e) {
      Log.w(TAG, "Error in dismissCurrentDialog: " + e.getMessage(), e);
      cleanupAllViews();
    }
  }
  
  private void cleanupAllViews() {
    try {
      if (pendingHideLoadingRunnable != null && webView != null) {
        webView.removeCallbacks(pendingHideLoadingRunnable);
      }
      pendingHideLoadingRunnable = null;

      if (loadingOverlayView != null) {
        try {
          if (loadingOverlayView.getParent() != null) {
            ((ViewGroup) loadingOverlayView.getParent()).removeView(loadingOverlayView);
          }
        } catch (Exception e) {
          Log.d(TAG, "Error cleaning up loading indicator: " + e.getMessage());
        }
        loadingOverlayView = null;
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
          webView.setWebViewClient(null);
          webView.setWebChromeClient(null);
          webView.removeJavascriptInterface(StashWebViewUtils.JS_INTERFACE_NAME);
          webView.destroy();
        } catch (Exception e) {
          Log.d(TAG, "Error cleaning up WebView: " + e.getMessage());
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
          Log.d(TAG, "Error cleaning up container: " + e.getMessage());
        }
        currentContainer = null;
      }
      
      orientationChangeListener = null;
    } catch (Exception e) {
      Log.d(TAG, "Error during cleanup: " + e.getMessage());
    }

    paymentSuccessHandled = false;
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

      int[] clamped = StashWebViewUtils.applyMinFloors(cardWidth, cardHeight, minWidthPx, minHeightPx);
      cardWidth = clamped[0];
      cardHeight = clamped[1];

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
