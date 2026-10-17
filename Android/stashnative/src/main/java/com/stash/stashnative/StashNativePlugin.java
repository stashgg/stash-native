package com.stash.stashnative;

import android.app.Activity;
import android.app.Application;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.graphics.Bitmap;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import java.lang.ref.WeakReference;

/** Coordinates checkout sessions and browser handoff for the public {@link StashNative} API. */
public class StashNativePlugin {
  private static final String TAG = "StashNative";

  /** Thread-safe lazy singleton holder. */
  private static class Holder {
    static final StashNativePlugin INSTANCE = new StashNativePlugin();
  }

  private WeakReference<Activity> activityRef;

  /** Live checkout activity (card path); set in its onCreate, cleared in onDestroy. */
  private volatile WeakReference<StashCheckoutActivity> checkoutActivityRef;

  /**
   * Strong reference: anonymous listeners are otherwise only weakly reachable and may be GC'd in
   * background.
   */
  private StashNative.StashNativeListener listener;

  StashPresentationOptions presentationOptions;

  private Bitmap pendingBackdropBitmap;
  private StashHostBackdropSupport launchingBackdrop;
  private long backdropSessionId;

  /** Accessed from UI and JS threads; volatile for visibility. */
  volatile boolean isCurrentlyPresented;

  /** Identifies callbacks and cleanup belonging to the admitted presentation. */
  volatile long presentationSessionId;

  private boolean presentationIsScanner;

  private BroadcastReceiver checkoutBridgeReceiver;
  private boolean checkoutBridgeReceiverRegistered;

  /**
   * Stashed at registration time so cleanup() can unregister even if the Activity has been GC'd.
   */
  private Context registeredAppContext;

  private boolean checkoutHostLifecycleRegistered;
  private Application.ActivityLifecycleCallbacks checkoutHostLifecycleCallbacks;

  /**
   * When true, a short foreground service may run while an external browser / Custom Tabs is open.
   */
  private volatile boolean keepAliveEnabled;

  private StashNative.KeepAliveConfig keepAliveConfig;

  /**
   * When true, host {@code onResume} should fire the browser-close callback.
   */
  private boolean isBrowserSessionActive;

  /**
   * After launching Custom Tabs / browser we defer arming until the host is paused by that UI or a
   * short timeout. Otherwise the host can resume when checkout or a dialog dismisses before the tab
   * is shown, which incorrectly fired a browser-dismissal callback.
   */
  private boolean browserCloseTrackingPendingArm;

  private Runnable browserCloseTrackingArmRunnable;
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private static final long BROWSER_CLOSE_TRACK_ARM_DELAY_MS = 400L;

  /**
   * Custom Tabs can deliver a transient host {@code onResume} right after the tab opens. Only
   * invoke the browser-close callback after the host stays resumed past this delay; cancel if
   * the host pauses again (browser UI still on top).
   */
  private Runnable browserClosedDebounceRunnable;

  private static final long BROWSER_CLOSED_RESUME_DEBOUNCE_MS = 500L;

  /**
   * True while {@link StashNativeBrowserProxyActivity} is awaiting a Custom Tabs result. Acts as
   * the dedup gate between proxy {@code onActivityResult} and the engagement-session-ended path.
   */
  private boolean browserCloseAwaitingCctResult;
  private long browserSessionId;

  /**
   * When set (checkout), run on the main thread after a browser-dismissal callback so checkout can
   * dismiss only after the tab was started and closed. Avoids finishing checkout before {@code
   * startActivityForResult} runs and losing / deferring the result.
   */
  private Runnable pendingCheckoutDismissAfterExternalBrowser;

  private void ensureCheckoutHostLifecycle(Context context) {
    if (checkoutHostLifecycleRegistered || context == null) {
      return;
    }
    Context appCtx = context.getApplicationContext();
    if (!(appCtx instanceof Application)) {
      return;
    }
    Application app = (Application) appCtx;
    checkoutHostLifecycleCallbacks =
        new Application.ActivityLifecycleCallbacks() {
          @Override
          public void onActivityResumed(Activity activity) {
            Activity host = getActivity();
            if (host != null && activity == host) {
              stopKeepAliveForegroundService(activity.getApplicationContext());
              if (isBrowserSessionActive && !browserCloseAwaitingCctResult) {
                scheduleBrowserClosedDebounce();
              }
            }
          }

          @Override
          public void onActivityCreated(Activity a, Bundle b) {}

          @Override
          public void onActivityStarted(Activity a) {}

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

          @Override
          public void onActivityStopped(Activity a) {}

          @Override
          public void onActivitySaveInstanceState(Activity a, Bundle b) {}

          @Override
          public void onActivityDestroyed(Activity a) {}
        };
    app.registerActivityLifecycleCallbacks(checkoutHostLifecycleCallbacks);
    checkoutHostLifecycleRegistered = true;
  }

  /**
   * Registers a package-local receiver so events from {@link StashCheckoutActivity} reach {@link
   * StashNative.StashNativeListener} on the main thread (same-process default; broadcasts
   * remain the activity-to-plugin contract).
   */
  private void ensureCheckoutBridgeReceiver(Context context) {
    if (checkoutBridgeReceiverRegistered || context == null) {
      return;
    }
    Context app = context.getApplicationContext();
    checkoutBridgeReceiver =
        new BroadcastReceiver() {
          @Override
          public void onReceive(Context receiverContext, Intent intent) {
            if (intent == null || intent.getAction() == null) {
              return;
            }
            final String action = intent.getAction();
            final Intent intentCopy = intent;
            new Handler(Looper.getMainLooper())
                .post(() -> dispatchCheckoutBridgeIntent(action, intentCopy));
          }
        };
    IntentFilter filter = new IntentFilter();
    filter.addAction(CardConstants.BROADCAST_CHECKOUT_PAYMENT_SUCCESS);
    filter.addAction(CardConstants.BROADCAST_CHECKOUT_PAYMENT_FAILURE);
    filter.addAction(CardConstants.BROADCAST_CHECKOUT_NETWORK_ERROR);
    filter.addAction(CardConstants.BROADCAST_CHECKOUT_DIALOG_DISMISSED);
    filter.addAction(CardConstants.BROADCAST_CHECKOUT_PAGE_LOADED);
    filter.addAction(CardConstants.BROADCAST_CODE_LINK_SCANNED);
    filter.addAction(CardConstants.BROADCAST_CODE_LINK_ERROR);
    try {
      // Use platform API directly to avoid requiring androidx.core >= 1.9 (4-arg
      // ContextCompat.registerReceiver). Hosts with old androidx.core (e.g. Unity
      // EDM-resolved 1.2.x) would crash with NoSuchMethodError otherwise.
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        app.registerReceiver(checkoutBridgeReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
      } else {
        app.registerReceiver(
            checkoutBridgeReceiver,
            filter,
            app.getPackageName() + ".permission.STASH_NATIVE_INTERNAL",
            null);
      }
      checkoutBridgeReceiverRegistered = true;
      registeredAppContext = app;
    } catch (Exception e) {
      Log.e(TAG, "Failed to register checkout bridge receiver: " + e.getMessage(), e);
    }
    ensureCheckoutHostLifecycle(context);
  }

  private void dispatchCheckoutBridgeIntent(String action, Intent intent) {
    if (!isCurrentlyPresented
        || intent.getLongExtra(StashCheckoutBridge.EXTRA_SESSION_ID, 0L) != presentationSessionId) {
      return;
    }
    StashNative.StashNativeListener l = getListener();
    boolean scanner = presentationIsScanner;
    try {
      if (CardConstants.BROADCAST_CODE_LINK_ERROR.equals(action)) {
        if (l != null) {
          l.onCodeLinkError(StashNative.CodeLinkError.valueOf(
              intent.getStringExtra(CardConstants.BROADCAST_EXTRA_CODE_LINK_ERROR)));
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
        isCurrentlyPresented = false;
        checkoutActivityRef = null;
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
        if (scanner) {
          l.onScanDismissed();
        } else {
          l.onCardDismissed();
        }
      } else if (CardConstants.BROADCAST_CODE_LINK_SCANNED.equals(action)) {
        l.onQrCodeScanned(intent.getStringExtra(CardConstants.BROADCAST_EXTRA_CODE_LINK_CONTENT));
      }
    } catch (Exception e) {
      Log.w(TAG, "Error dispatching checkout bridge: " + e.getMessage(), e);
    }
  }

  StashNative.StashNativeListener getListener() {
    return listener;
  }

  /** Returns the singleton plugin instance. */
  public static StashNativePlugin getInstance() {
    return Holder.INSTANCE;
  }

  private StashNativePlugin() {}

  /** Observes the current host without retaining it. */
  void setActivity(Activity activity) {
    this.activityRef = new WeakReference<>(activity);
    if (activity != null) {
      ensureCheckoutBridgeReceiver(activity);
    }
  }

  Activity getActivity() {
    return activityRef != null ? activityRef.get() : null;
  }

  void setListener(StashNative.StashNativeListener listener) {
    this.listener = listener;
  }

  void setKeepAliveEnabled(boolean enabled) {
    this.keepAliveEnabled = enabled;
  }

  boolean isKeepAliveEnabled() {
    return keepAliveEnabled;
  }

  void setKeepAliveConfig(StashNative.KeepAliveConfig config) {
    this.keepAliveConfig = config;
  }

  /**
   * Starts the optional keep-alive foreground service before opening Custom Tabs / browser.
   * Package-private for {@link StashCheckoutActivity}.
   */
  void startKeepAliveBeforeBrowser(Context context) {
    if (!keepAliveEnabled || context == null) {
      return;
    }
    try {
      Context app = context.getApplicationContext();
      StashKeepAliveService.start(
          app, resolveKeepAliveTitle(app), resolveKeepAliveText(app), resolveKeepAliveIconResId());
    } catch (Exception e) {
      Log.w(TAG, "Keep-alive start failed: " + e.getMessage(), e);
    }
  }

  void stopKeepAliveForegroundService(Context context) {
    StashKeepAliveService.stop(context);
  }

  void cancelBrowserCloseTrackingLaunch() {
    browserSessionId++;
    isBrowserSessionActive = false;
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
   * Drops checkout external-browser teardown without running the pending runnable (e.g. user
   * dismissed the dim overlay while Custom Tabs callbacks are missing).
   */
  void abandonPendingExternalBrowserCheckoutDismiss(StashCheckoutActivity checkout) {
    if (!ownsCheckout(checkout) || pendingCheckoutDismissAfterExternalBrowser == null) {
      return;
    }
    pendingCheckoutDismissAfterExternalBrowser = null;
    cancelBrowserCloseTrackingLaunch();
  }

  private void invokeBrowserDismissedListenerAndDismissCheckout() {
    Runnable dismiss = pendingCheckoutDismissAfterExternalBrowser;
    pendingCheckoutDismissAfterExternalBrowser = null;
    StashNative.StashNativeListener l = getListener();
    if (l != null) {
      try {
        l.onBrowserDismissed();
      } catch (Exception e) {
        Log.w(TAG, "Error in browser dismissal callback: " + e.getMessage(), e);
      }
    }
    if (dismiss != null) {
      mainHandler.post(dismiss);
    }
  }

  private boolean ownsCheckout(StashCheckoutActivity checkout) {
    return checkout != null && checkout == getCheckoutActivity()
        && checkout.getPresentationSessionId() == presentationSessionId
        && !checkout.isDismissing && !checkout.isFinishing() && !checkout.isDestroyed();
  }

  private Runnable forCheckout(StashCheckoutActivity checkout, Runnable action) {
    return () -> {
      if (ownsCheckout(checkout) && action != null) {
        action.run();
      }
    };
  }

  /**
   * Opens Custom Tabs from checkout using {@code checkoutActivity} for {@code
   * startActivityForResult}. {@code hideCheckoutChromeWhileBrowserOpen} runs on the main thread
   * after the URL launcher returns (e.g. hide the sheet while keeping the dim overlay). {@code
   * dismissAfterBrowserClosed} runs after the browser-close callback, or immediately if the URL
   * cannot be opened.
   */
  void openExternalBrowserFromCheckout(
      StashCheckoutActivity checkoutActivity,
      String url,
      boolean notifyExternalPaymentListener,
      Runnable hideCheckoutChromeWhileBrowserOpen,
      Runnable dismissAfterBrowserClosed) {
    if (!isCurrentlyPresented || !ownsCheckout(checkoutActivity)
        || url == null || url.isEmpty()) {
      return;
    }
    checkoutActivity.callbackSent = true;
    checkoutActivity.isPurchaseProcessing = false;
    isCurrentlyPresented = false;
    long browserBeforeCallback = browserSessionId;
    if (notifyExternalPaymentListener) {
      StashNative.StashNativeListener l = getListener();
      if (l != null) {
        try {
          l.onExternalPayment(url);
        } catch (Exception e) {
          Log.w(TAG, "Error in onExternalPayment: " + e.getMessage(), e);
        }
      }
    }
    // The host may reset or open another checkout from its callback.
    if (!ownsCheckout(checkoutActivity) || browserSessionId != browserBeforeCallback) {
      return;
    }
    pendingCheckoutDismissAfterExternalBrowser =
        forCheckout(checkoutActivity, dismissAfterBrowserClosed);
    try {
      startKeepAliveBeforeBrowser(checkoutActivity);
      launchExternalBrowser(checkoutActivity, url);
      if (hideCheckoutChromeWhileBrowserOpen != null) {
        mainHandler.post(forCheckout(checkoutActivity, hideCheckoutChromeWhileBrowserOpen));
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
    long sessionId = browserSessionId;
    browserClosedDebounceRunnable =
        () -> {
          if (!isBrowserSessionActive || sessionId != browserSessionId) {
            return;
          }
          browserClosedDebounceRunnable = null;
          cancelBrowserCloseTrackingLaunch();
          invokeBrowserDismissedListenerAndDismissCheckout();
        };
    mainHandler.postDelayed(browserClosedDebounceRunnable, BROWSER_CLOSED_RESUME_DEBOUNCE_MS);
  }

  /**
   * Call after {@link StashUrlLauncher#openExternalUrl(Context, String, int)} when Custom Tabs did
   * not use {@code startActivityForResult}, so the browser-close callback is not tied to card
   * teardown.
   */
  private void beginBrowserCloseTrackingAfterExternalUrlLaunched() {
    cancelBrowserCloseTrackingLaunch();
    long sessionId = browserSessionId;
    isBrowserSessionActive = false;
    browserCloseTrackingPendingArm = true;
    browserCloseTrackingArmRunnable =
        () -> {
          if (browserCloseTrackingPendingArm && sessionId == browserSessionId) {
            browserCloseTrackingArmRunnable = null;
            browserCloseTrackingPendingArm = false;
            isBrowserSessionActive = true;
          }
        };
    mainHandler.postDelayed(browserCloseTrackingArmRunnable, BROWSER_CLOSE_TRACK_ARM_DELAY_MS);
  }

  /**
   * Marks the plugin as awaiting a Custom Tabs close. Set before starting {@link
   * StashNativeBrowserProxyActivity} so dispatches from the proxy's {@code onActivityResult} and
   * the engagement-session-ended path dedupe via the same gate.
   */
  private void beginBrowserCloseTrackingActivityResult() {
    cancelBrowserCloseTrackingLaunch();
    browserCloseAwaitingCctResult = true;
  }

  private void applyBrowserCloseTrackingForLaunchMode(int launchMode) {
    if (launchMode == StashUrlLauncher.OPEN_EXTERNAL_CCT_ACTIVITY_FOR_RESULT) {
      beginBrowserCloseTrackingActivityResult();
    } else {
      beginBrowserCloseTrackingAfterExternalUrlLaunched();
    }
  }

  /** Correlates proxy results and engagement callbacks with the current browser launch. */
  boolean isCurrentBrowserSession(long sessionId) {
    return browserCloseAwaitingCctResult && sessionId == browserSessionId;
  }

  /**
   * Called by {@link StashNativeBrowserProxyActivity} when Custom Tabs delivered its activity
   * result (or the orphan-resume fallback fired). Unbinds the engagement service and dispatches
   * the browser-dismissal callback via the shared close-tracking gate.
   */
  void notifyBrowserClosedFromProxyInternal(long sessionId) {
    if (!isCurrentBrowserSession(sessionId)) {
      return;
    }
    Activity hostOrNull = getActivity();
    Context unbindCtx = hostOrNull != null ? hostOrNull : registeredAppContext;
    if (unbindCtx != null) {
      StashUrlLauncher.unbindCustomTabsEngagement(unbindCtx);
    }
    cancelBrowserCloseTrackingLaunch();
    invokeBrowserDismissedListenerAndDismissCheckout();
  }

  /** Bridge from {@link StashNativeBrowserProxyActivity}'s engagement-session-ended callback. */
  void notifyBrowserEngagementSessionEndedFromProxyInternal(long sessionId) {
    notifyBrowserClosedFromProxyInternal(sessionId);
  }

  /**
   * Launches the URL in Chrome Custom Tabs via {@link StashNativeBrowserProxyActivity} when {@code
   * androidx.browser} is on the classpath, otherwise falls back to the lifecycle-tracked
   * ACTION_VIEW path on the host activity directly.
   */
  private void launchExternalBrowser(Activity activity, String url) {
    if (activity == null || url == null || url.isEmpty()) {
      return;
    }
    if (StashUrlLauncher.isCustomTabsClassAvailable()) {
      beginBrowserCloseTrackingActivityResult();
      Intent intent = new Intent(activity, StashNativeBrowserProxyActivity.class);
      intent.putExtra(StashNativeBrowserProxyActivity.EXTRA_URL, url);
      intent.putExtra(StashNativeBrowserProxyActivity.EXTRA_SESSION_ID, browserSessionId);
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

  void openCard(Activity host, String url, StashNative.CardConfig config) {
    openPresentation(host, url, StashPresentationOptions.card(config), null);
  }

  synchronized void setBackdropBitmap(Bitmap bitmap) {
    if (pendingBackdropBitmap != bitmap) {
      StashHostBackdropSupport.recycle(pendingBackdropBitmap);
      pendingBackdropBitmap = bitmap != null && !bitmap.isRecycled() ? bitmap : null;
    }
  }

  private synchronized Bitmap takePendingBackdrop() {
    Bitmap bitmap = pendingBackdropBitmap;
    pendingBackdropBitmap = null;
    return bitmap;
  }

  StashHostBackdropSupport takeBackdrop(long sessionId) {
    if (sessionId != backdropSessionId) {
      return null;
    }
    StashHostBackdropSupport backdrop = launchingBackdrop;
    launchingBackdrop = null;
    return backdrop;
  }

  private void releaseLaunchingBackdrop() {
    if (launchingBackdrop != null) {
      launchingBackdrop.dispose();
      launchingBackdrop = null;
    }
  }

  void codeLink(Activity host) {
    codeLink(host, null);
  }

  void codeLink(Activity host, StashNative.CodeLinkConfig config) {
    openPresentation(host, null, StashPresentationOptions.card(null),
        StashCodeLinkOptions.from(config));
  }

  void codeLinkUnavailable(StashCheckoutActivity checkout) {
    if (checkout == null || checkout != getCheckoutActivity()
        || checkout.getPresentationSessionId() != presentationSessionId) {
      return;
    }
    isCurrentlyPresented = false;
    checkoutActivityRef = null;
    StashNative.StashNativeListener current = getListener();
    if (current != null) {
      try {
        current.onCodeLinkError(StashNative.CodeLinkError.SCANNER_UNAVAILABLE);
      } catch (Exception error) {
        Log.w(TAG, "Error delivering scanner unavailable failure", error);
      }
    }
  }

  private void openPresentation(
      Activity host, String url, StashPresentationOptions options, StashCodeLinkOptions codeLink) {
    if (Looper.myLooper() != Looper.getMainLooper()) {
      mainHandler.post(() -> openPresentation(host, url, options, codeLink));
      return;
    }
    if (isCurrentlyPresented || host == null || host.isFinishing() || host.isDestroyed()) {
      return;
    }
    setActivity(host);
    String normalized = codeLink != null ? null
        : StashWebViewUtils.normalizeExternalPaymentUrl(url);
    if (codeLink == null && normalized == null) {
      return;
    }
    // A terminal callback may reopen before the previous dismissal animation finishes.
    retireCheckoutWithoutCallbacks();
    cleanupAllViews();
    presentationSessionId++;
    presentationIsScanner = codeLink != null;
    isCurrentlyPresented = true;
    presentationOptions = options;
    if (codeLink == null) {
      Bitmap backdrop = takePendingBackdrop();
      if (options.orientation == StashNative.CardConfig.ORIENTATION_PORTRAIT) {
        launchingBackdrop = StashHostBackdropSupport.create(host, backdrop);
        backdropSessionId = presentationSessionId;
      } else {
        StashHostBackdropSupport.recycle(backdrop);
      }
      try {
        normalized = StashWebViewUtils.appendThemeQueryParameter(
            normalized, StashWebViewUtils.isDarkTheme(host));
      } catch (Exception error) {
        Log.w(TAG, "Cannot apply checkout theme", error);
      }
    }
    launchCheckoutActivity(normalized, host, codeLink);
  }

  /**
   * Opens the URL via {@link StashUrlLauncher#openExternalUrl(Context, String)} (Custom Tabs when
   * available, else system browser).
   *
   * @param url URL to open
   */
  public void openBrowser(Activity activity, String url) {
    if (Looper.myLooper() != Looper.getMainLooper()) {
      final String requestedUrl = url;
      mainHandler.post(() -> openBrowser(activity, requestedUrl));
      return;
    }
    try {
      if (activity == null || activity.isFinishing() || activity.isDestroyed()) {
        return;
      }
      setActivity(activity);
      url = StashWebViewUtils.normalizeExternalPaymentUrl(url);
      if (activity == null || url == null) {
        Log.e(TAG, "Invalid activity or URL for openBrowser");
        return;
      }
      if (!isCurrentlyPresented) {
        retireCheckoutWithoutCallbacks();
      }
      try {
        url =
            StashWebViewUtils.appendThemeQueryParameter(
                url, StashWebViewUtils.isDarkTheme(activity));
      } catch (Exception e) {
        Log.d(TAG, "Error appending theme parameter: " + e.getMessage(), e);
      }
      final String finalUrl = url;
      final Activity finalActivity = activity;
      activity.runOnUiThread(
          () -> {
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

  void dismissDialog() {
    StashCheckoutActivity checkout = getCheckoutActivity();
    if (checkout != null) {
      checkout.runOnUiThread(checkout::dismissWithAnimation);
    }
  }

  /**
   * Package-private: the checkout activity registers/deregisters itself for programmatic dismiss.
   */
  void setCheckoutActivity(StashCheckoutActivity activity) {
    checkoutActivityRef = new WeakReference<>(activity);
  }

  private StashCheckoutActivity getCheckoutActivity() {
    WeakReference<StashCheckoutActivity> reference = checkoutActivityRef;
    return reference != null ? reference.get() : null;
  }

  private void retireCheckoutWithoutCallbacks() {
    StashCheckoutActivity checkout = getCheckoutActivity();
    checkoutActivityRef = null;
    if (checkout != null) {
      checkout.finishForPluginResetWithoutCallbacks();
    }
  }

  void clearCheckoutActivity(StashCheckoutActivity activity) {
    if (activity.getPresentationSessionId() == backdropSessionId) {
      releaseLaunchingBackdrop();
    }
    if (checkoutActivityRef != null && checkoutActivityRef.get() == activity) {
      checkoutActivityRef = null;
    }
  }

  /** Resets presentation state and dismisses any dialog. */
  public void resetPresentationState() {
    if (Looper.myLooper() != Looper.getMainLooper()) {
      mainHandler.post(this::resetPresentationState);
      return;
    }
    try {
      presentationSessionId++;
      retireCheckoutWithoutCallbacks();
      isCurrentlyPresented = false;
      cleanup();
    } catch (Exception e) {
      Log.w(TAG, "Error in resetPresentationState: " + e.getMessage(), e);
      cleanupAllViews();
    }
  }

  /** Removes session observers and browser tracking, retaining the live listener. */
  public void cleanup() {
    cleanupAllViews();
    setBackdropBitmap(null);
    Context appContext = registeredAppContext;
    if (appContext == null) {
      Activity activity = getActivity();
      appContext = activity != null ? activity.getApplicationContext() : null;
    }
    if (appContext != null) {
      StashUrlLauncher.unbindCustomTabsEngagement(appContext);
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
    if (checkoutHostLifecycleRegistered
        && appContext instanceof Application
        && checkoutHostLifecycleCallbacks != null) {
      try {
        ((Application) appContext)
            .unregisterActivityLifecycleCallbacks(checkoutHostLifecycleCallbacks);
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

  /**
   * Returns whether a purchase is currently being processed.
   *
   * @return true if processing
   */
  public boolean isPurchaseProcessing() {
    StashCheckoutActivity checkout = getCheckoutActivity();
    if (!isCurrentlyPresented) {
      return false;
    }
    return checkout != null && checkout.getPresentationSessionId() == presentationSessionId
        && checkout.isPurchaseProcessing;
  }

  private void launchCheckoutActivity(
      String url, Activity activity, StashCodeLinkOptions codeLink) {
    try {
      Intent intent = new Intent(activity, StashCheckoutActivity.class);
      intent.putExtra(CardConstants.INTENT_EXTRA_URL, url);
      intent.putExtra(CardConstants.INTENT_EXTRA_CODE_LINK, codeLink != null);
      if (codeLink != null) {
        codeLink.put(intent);
      }
      intent.putExtra(StashCheckoutBridge.EXTRA_SESSION_ID, presentationSessionId);
      presentationOptions.put(intent);
      intent.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION);
      activity.startActivity(intent);
      activity.overridePendingTransition(0, 0);
    } catch (Exception e) {
      Log.e(TAG, "Failed to launch checkout", e);
      isCurrentlyPresented = false;
      releaseLaunchingBackdrop();
    }
  }

  void cleanupAllViews() {
    releaseLaunchingBackdrop();
    isCurrentlyPresented = false;
    presentationOptions = null;
  }
}
