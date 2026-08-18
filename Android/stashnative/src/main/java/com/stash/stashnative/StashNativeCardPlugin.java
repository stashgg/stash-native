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
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Surface;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewTreeObserver;
import android.webkit.WebView;
import android.widget.FrameLayout;
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
  /** Live portrait checkout activity (card/modal path); set in its onCreate, cleared in onDestroy. */
  private volatile WeakReference<StashNativeCardPortraitActivity> portraitActivityRef;
  /** Strong reference: anonymous listeners are otherwise only weakly reachable and may be GC'd in background. */
  StashNativeCard.StashNativeCardListener listener;

  Dialog currentDialog;
  WebView webView;
  FrameLayout currentContainer;
  View loadingOverlayView;
  ViewTreeObserver.OnGlobalLayoutListener orientationChangeListener;
  
  // Phone card: only height is configurable in portrait (full width);
  // landscape ratios when not forcing portrait
  private float cardHeightRatioPortrait = CardConstants.DEFAULT_CARD_HEIGHT_RATIO;
  private boolean forcePortraitOnCheckout = false;
  /** Card-presentation autoClose; modal uses {@link #currentModalConfig}.autoClose. */
  private boolean cardAutoCloseOnPaymentEvent = true;
  private float cardWidthRatioLandscape = CardConstants.DEFAULT_CARD_WIDTH_RATIO_LANDSCAPE;
  private float cardHeightRatioLandscape = CardConstants.DEFAULT_CARD_HEIGHT_RATIO_LANDSCAPE;
  
  // Orientation-specific tablet card configuration
  private float tabletWidthRatioPortrait = CardConstants.DEFAULT_TABLET_WIDTH_RATIO_PORTRAIT;
  private float tabletHeightRatioPortrait = CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_PORTRAIT;
  private float tabletWidthRatioLandscape = CardConstants.DEFAULT_TABLET_WIDTH_RATIO_LANDSCAPE;
  private float tabletHeightRatioLandscape = CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_LANDSCAPE;
  
  /** Accessed from UI and JS threads; volatile for visibility. */
  volatile boolean isCurrentlyPresented;
  /**
   * True only when checkout used a separate WebView OS process. With the default manifest,
   * {@link StashNativeCardPortraitActivity} runs in the host app process (required for Unity and
   * similar engines), so this stays false and {@link #clearPresentationIfCheckoutProcessDied} is a
   * no-op.
   */
  volatile boolean presentationUsesIsolatedWebviewProcess;
  /** Accessed from UI and JS threads; volatile for visibility. */
  volatile boolean paymentSuccessHandled;
  /** Accessed from UI and JS threads; volatile for visibility. */
  volatile boolean isPurchaseProcessing;
  private boolean usePopupPresentation;
  boolean useModalPresentation;
  int lastOrientation = Configuration.ORIENTATION_UNDEFINED;
  
  // Modal configuration (used when useModalPresentation is true)
  StashNativeCard.ModalConfig currentModalConfig;

  /** Normalized #hex from last {@code openCard} config; modal uses {@link #currentModalConfig}. */
  private String presentationBackgroundColorHex;
  
  boolean useCustomSize;
  float customPortraitWidthMultiplier = CardConstants.POPUP_PORTRAIT_WIDTH_MULTIPLIER;
  float customPortraitHeightMultiplier = CardConstants.POPUP_PORTRAIT_HEIGHT_MULTIPLIER;
  float customLandscapeWidthMultiplier = CardConstants.POPUP_LANDSCAPE_WIDTH_MULTIPLIER;
  float customLandscapeHeightMultiplier = CardConstants.POPUP_LANDSCAPE_HEIGHT_MULTIPLIER;
  
  long pageLoadStartTime;

  private BroadcastReceiver checkoutBridgeReceiver;
  private boolean checkoutBridgeReceiverRegistered;
  /** Stashed at registration time so cleanup() can unregister even if the Activity has been GC'd. */
  private Context registeredAppContext;
  private boolean checkoutHostLifecycleRegistered;
  private Application.ActivityLifecycleCallbacks checkoutHostLifecycleCallbacks;
  Runnable pendingHideLoadingRunnable;
  /** Popup dialog path only: initial-load network deadline (card path uses activity timers). */
  boolean popupInitialLoadComplete;
  boolean popupNetworkErrorHandled;
  /** Pre-load main-frame error latch (parity with the card's mainFrameErrorReceived). */
  boolean popupMainFrameErrorReceived;
  Runnable popupNetworkDeadlineRunnable;
  final Handler popupLoadHandler = new Handler(Looper.getMainLooper());

  /** When true, a short foreground service may run while an external browser / Custom Tabs is open. */
  private volatile boolean keepAliveEnabled;
  private StashNativeCard.KeepAliveConfig keepAliveConfig;

  /** When true, host {@code onResume} should fire {@link StashNativeCardListener#onBrowserClosed()}. */
  private boolean isBrowserSessionActive;
  /**
   * After launching Custom Tabs / browser we defer arming until the host is paused by that UI or a
   * short timeout. Otherwise the host can resume when portrait checkout or a dialog dismisses
   * before the tab is shown, which incorrectly fired {@code onBrowserClosed}.
   */
  private boolean browserCloseTrackingPendingArm;
  private Runnable browserCloseTrackingArmRunnable;
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private static final long BROWSER_CLOSE_TRACK_ARM_DELAY_MS = 400L;
  /**
   * Custom Tabs can deliver a transient host {@code onResume} right after the tab opens. Only invoke
   * {@link StashNativeCardListener#onBrowserClosed()} after the host stays resumed past this delay;
   * cancel if the host pauses again (browser UI still on top).
   */
  private Runnable browserClosedDebounceRunnable;
  private static final long BROWSER_CLOSED_RESUME_DEBOUNCE_MS = 500L;
  /**
   * True while {@link StashNativeBrowserProxyActivity} is awaiting a Custom Tabs result.
   * Acts as the dedup gate between proxy {@code onActivityResult} and the
   * engagement-session-ended path.
   */
  private boolean browserCloseAwaitingCctResult;

  /**
   * When set (portrait checkout), run on the main thread after {@code onBrowserClosed} so checkout
   * can dismiss only after the tab was started and closed. Avoids finishing portrait before {@code
   * startActivityForResult} runs and losing / deferring the result.
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
   * If checkout used an isolated WebView process and that process died without sending a broadcast
   * (e.g. native Chromium abort), clear state and surface {@link
   * StashNativeCard.StashNativeCardListener#onNetworkError()} once the host activity resumes.
   * No-op when {@link #presentationUsesIsolatedWebviewProcess} is false (default: same process as host).
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
   * Registers a package-local receiver so events from {@link StashNativeCardPortraitActivity}
   * reach {@link StashNativeCard.StashNativeCardListener} on the main thread (same-process default;
   * broadcasts remain the activity-to-plugin contract).
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
    filter.addAction(CardConstants.BROADCAST_CHECKOUT_PAGE_LOADED);
    try {
      // Use platform API directly to avoid requiring androidx.core >= 1.9 (4-arg
      // ContextCompat.registerReceiver). Hosts with old androidx.core (e.g. Unity
      // EDM-resolved 1.2.x) would crash with NoSuchMethodError otherwise.
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
      if (CardConstants.BROADCAST_CHECKOUT_PAGE_LOADED.equals(action)) {
        if (l != null) {
          long loadTimeMs = intent.getLongExtra(CardConstants.BROADCAST_EXTRA_PAGE_LOAD_MS, 0L);
          l.onPageLoaded(loadTimeMs);
        }
        return;
      }
      // Payment events with autoClose off leave the card visible; do not clear presented then.
      boolean isPaymentEvent =
          CardConstants.BROADCAST_CHECKOUT_PAYMENT_SUCCESS.equals(action)
              || CardConstants.BROADCAST_CHECKOUT_PAYMENT_FAILURE.equals(action);
      boolean willClose = intent.getBooleanExtra(CardConstants.BROADCAST_EXTRA_WILL_CLOSE, true);
      if (!isPaymentEvent || willClose) {
        presentationUsesIsolatedWebviewProcess = false;
        isCurrentlyPresented = false;
      }
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

  StashNativeCard.StashNativeCardListener getListener() {
    return listener;
  }

  /**
   * Runs the given runnable on the main thread and then dismisses the current dialog.
   * Used by JS interface handlers to avoid duplicating post + listener + dismiss logic.
   */
  void runOnMainAndDismiss(Runnable beforeDismiss) {
    new Handler(Looper.getMainLooper()).post(() -> {
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
  Activity getActivity() {
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
   * Package-private for {@link StashNativeCardPortraitActivity}.
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
   * Drops portrait external-browser teardown without running the pending runnable (e.g. user
   * dismissed the dim overlay while Custom Tabs callbacks are missing).
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
   * after the URL launcher returns (e.g. hide the sheet while keeping the dim overlay).
   * {@code dismissAfterBrowserClosed} runs after {@link StashNativeCardListener#onBrowserClosed()},
   * or immediately if the URL cannot be opened.
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
      stopKeepAliveForegroundService(checkoutActivity.getApplicationContext());
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
   * Call after {@link StashUrlLauncher#openExternalUrl(Context, String, int)} when Custom Tabs did
   * not use {@code startActivityForResult}, so {@link StashNativeCardListener#onBrowserClosed()}
   * is not tied to checkout teardown (portrait / dialog).
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
   * Marks the plugin as awaiting a Custom Tabs close. Set before starting {@link
   * StashNativeBrowserProxyActivity} so dispatches from the proxy's {@code
   * onActivityResult} and the engagement-session-ended path dedupe via the same gate.
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
  void launchExternalBrowser(Activity activity, String url) {
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
        this.cardAutoCloseOnPaymentEvent = config.autoClose;
        this.presentationBackgroundColorHex =
            StashBackgroundColorUtils.normalizeHexOrNull(config.backgroundColor);
      } else {
        // null config means defaults: reset any values a previous openCard left on the singleton.
        this.forcePortraitOnCheckout = false;
        this.cardHeightRatioPortrait = CardConstants.DEFAULT_CARD_HEIGHT_RATIO;
        this.cardWidthRatioLandscape = CardConstants.DEFAULT_CARD_WIDTH_RATIO_LANDSCAPE;
        this.cardHeightRatioLandscape = CardConstants.DEFAULT_CARD_HEIGHT_RATIO_LANDSCAPE;
        this.tabletWidthRatioPortrait = CardConstants.DEFAULT_TABLET_WIDTH_RATIO_PORTRAIT;
        this.tabletHeightRatioPortrait = CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_PORTRAIT;
        this.tabletWidthRatioLandscape = CardConstants.DEFAULT_TABLET_WIDTH_RATIO_LANDSCAPE;
        this.tabletHeightRatioLandscape = CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_LANDSCAPE;
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
      try {
        url = StashWebViewUtils.appendThemeQueryParameter(url,
            StashWebViewUtils.isDarkTheme(activity));
      } catch (Exception e) {
        Log.d(TAG, "Error appending theme parameter: " + e.getMessage(), e);
      }
      final String finalUrl = url;
      final Activity finalActivity = activity;
      activity.runOnUiThread(() -> {
        try {
          startKeepAliveBeforeBrowser(finalActivity);
          launchExternalBrowser(finalActivity, finalUrl);
        } catch (Exception e) {
          cancelBrowserCloseTrackingLaunch();
          stopKeepAliveForegroundService(finalActivity.getApplicationContext());
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
      customPortraitWidthMultiplier = portraitWidthMultiplier;
      customPortraitHeightMultiplier = portraitHeightMultiplier;
      customLandscapeWidthMultiplier = landscapeWidthMultiplier;
      customLandscapeHeightMultiplier = landscapeHeightMultiplier;
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
    // Card/modal run in the portrait activity, which owns its own main-thread handle; dismiss it
    // directly so teardown does not depend on the host activity still being reachable (it may be
    // GC'd under memory pressure while the checkout is still up).
    StashNativeCardPortraitActivity portrait =
        portraitActivityRef != null ? portraitActivityRef.get() : null;
    if (portrait != null) {
      portrait.runOnUiThread(portrait::dismissWithAnimation);
    }
    runOnMainSafely(() -> {
      try {
        dismissCurrentDialog();
      } catch (Exception e) {
        Log.w(TAG, "Error dismissing dialog: " + e.getMessage());
        cleanupAllViews();
      }
    });
  }

  /** Package-private: the portrait activity registers/deregisters itself for programmatic dismiss. */
  void setPortraitActivity(StashNativeCardPortraitActivity activity) {
    portraitActivityRef = new WeakReference<>(activity);
  }

  void clearPortraitActivity(StashNativeCardPortraitActivity activity) {
    if (portraitActivityRef != null && portraitActivityRef.get() == activity) {
      portraitActivityRef = null;
    }
  }

  /**
   * Resets presentation state and dismisses any dialog.
   */
  public void resetPresentationState() {
    try {
      // Card/modal: finish the activity WITHOUT emitting onDialogDismissed (reset is silent).
      StashNativeCardPortraitActivity a =
          portraitActivityRef != null ? portraitActivityRef.get() : null;
      if (a != null) {
        a.runOnUiThread(a::finishForPluginResetWithoutCallbacks);
      }
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

  private float clampRatio(float ratio) {
    // NaN/Inf would flow through Math.min/max unclamped (parity with iOS stashClampRatio,
    // which rejects them too); fall back to a mid default rather than a boundary value.
    if (Float.isNaN(ratio) || Float.isInfinite(ratio)) {
      return 0.5f;
    }
    return Math.max(0.1f, Math.min(1.0f, ratio));
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
            StashPopupDialogSupport.createAndShowPopupDialog(this, finalUrl, finalActivity);
          } else {
            // Both card and modal use PortraitActivity in the host app process (avoids a second
            // process taking foreground, which breaks Unity and similar engines). Modal shares the
            // same retry/timeout/loading behaviour as card. The Activity reads the useModal flag
            // from the Intent and calls createModal() instead of createCard().
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
      
      // Same task as host app (no NEW_TASK / MULTIPLE_TASK): avoids a second entry in Recents.
      intent.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION);

      activity.startActivity(intent);
      activity.overridePendingTransition(0, 0);
      isCurrentlyPresented = true;
    } catch (Exception e) {
      Log.e(TAG, "Failed to launch Activity: " + e.getMessage());
    }
  }
  
  void dismissCurrentDialog() {
    try {
      if (currentDialog != null) {
        StashPopupDialogSupport.dismissPopupDialog(this);
      }
    } catch (Exception e) {
      Log.w(TAG, "Error in dismissCurrentDialog: " + e.getMessage(), e);
      cleanupAllViews();
    }
  }
  
  void cleanupAllViews() {
    StashPopupDialogSupport.cancelPopupNetworkDeadline(this);
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
    try {
      android.webkit.CookieManager.getInstance().flush();
    } catch (Throwable ignored) {
    }
  }
  
}
