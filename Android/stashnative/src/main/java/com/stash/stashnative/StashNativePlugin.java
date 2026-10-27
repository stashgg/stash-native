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

/** Coordinates card sessions, the scanner, and browser handoff for {@link StashNative}. */
public class StashNativePlugin {
  private static final String TAG = "StashNative";

  /** Thread-safe lazy singleton holder. */
  private static class Holder {
    static final StashNativePlugin INSTANCE = new StashNativePlugin();
  }

  private WeakReference<Activity> activityRef;

  /** Live checkout activity (card path); set in its onCreate, cleared in onDestroy. */
  private volatile WeakReference<StashCardActivity> checkoutActivityRef;

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

  /** Session of the last activity that registered; differs while a launch is still queued. */
  private long registeredSessionId;

  private boolean presentationIsScanner;

  private BroadcastReceiver checkoutBridgeReceiver;
  private boolean checkoutBridgeReceiverRegistered;

  /**
   * Stashed at registration time so cleanup() can unregister even if the Activity has been GC'd.
   */
  private Context registeredAppContext;
  private Class<?> hostActivityClass;
  private int hostTaskId = -1;

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
            if (!isBrowserBoundaryActivity(activity)) {
              return;
            }
            stopKeepAliveForegroundService(activity.getApplicationContext());
            if (isBrowserSessionActive && !browserCloseAwaitingCctResult) {
              scheduleBrowserClosedDebounce();
            }
          }

          @Override
          public void onActivityCreated(Activity a, Bundle b) {}

          @Override
          public void onActivityStarted(Activity a) {}

          @Override
          public void onActivityPaused(Activity activity) {
            if (!isBrowserBoundaryActivity(activity)) {
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
   * The activity whose pause and resume bracket an ACTION_VIEW browser: the host for {@link
   * #openBrowser}, and the checkout activity while a checkout handoff waits for the browser to
   * close. The host stays paused beneath the translucent checkout, so only the checkout resumes
   * when the browser goes away.
   */
  private boolean isBrowserBoundaryActivity(Activity activity) {
    Activity host = getActivity();
    if (host != null && activity == host) {
      return true;
    }
    // A configuration change can recreate the host while the browser is open. The replacement
    // has the same class and stays in the same task; another instance of the class elsewhere
    // does not count.
    if ((host == null || host.isFinishing() || host.isDestroyed()) && hostActivityClass != null
        && activity.getClass() == hostActivityClass && activity.getTaskId() == hostTaskId) {
      setActivity(activity);
      return true;
    }
    return pendingCheckoutDismissAfterExternalBrowser != null
        && activity == getCheckoutActivity();
  }

  /**
   * Registers a package-local receiver so events from {@link StashCardActivity} reach {@link
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
    filter.addAction(CardConstants.BROADCAST_SCANNER_SCANNED);
    filter.addAction(CardConstants.BROADCAST_SCANNER_ERROR);
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
      if (CardConstants.BROADCAST_SCANNER_ERROR.equals(action)) {
        if (l != null) {
          l.onScannerError(StashNative.ScannerError.valueOf(
              intent.getStringExtra(CardConstants.BROADCAST_EXTRA_SCANNER_ERROR)));
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
          l.onScannerDismissed();
        } else {
          l.onCardDismissed();
        }
      } else if (CardConstants.BROADCAST_SCANNER_SCANNED.equals(action)) {
        l.onQrCodeScanned(intent.getStringExtra(CardConstants.BROADCAST_EXTRA_SCANNER_CONTENT));
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
    this.hostActivityClass = activity != null ? activity.getClass() : null;
    this.hostTaskId = activity != null ? activity.getTaskId() : -1;
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
   * Starts the optional keep-alive foreground service once a browser has opened, while the
   * launching activity is still in the foreground.
   */
  void startKeepAliveForBrowser(Context context) {
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

  /**
   * Brings a presented card's task forward from the keep-alive notification. Started from the
   * card itself, so it resolves in the card's task whatever the host's affinity or launch mode.
   * Clear-top with single-top finishes only what lies above the card (a Custom Tab) and delivers
   * to the existing instance instead of recreating it; the host activities below stay untouched.
   *
   * @return false when no card is presented
   */
  boolean returnToPresentedCard() {
    StashCardActivity checkout = getCheckoutActivity();
    if (!isCurrentlyPresented || !ownsCheckout(checkout)) {
      return false;
    }
    try {
      checkout.startActivity(new Intent(checkout, StashCardActivity.class)
          .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP
              | Intent.FLAG_ACTIVITY_NO_ANIMATION));
      return true;
    } catch (Exception e) {
      Log.w(TAG, "Cannot return to the card: " + e.getMessage(), e);
      return false;
    }
  }

  /** Closes a keepOpen browser over the presented card; no effect otherwise. */
  void closeBrowserOverCard() {
    if (Looper.myLooper() != Looper.getMainLooper()) {
      mainHandler.post(this::closeBrowserOverCard);
      return;
    }
    StashCardActivity checkout = getCheckoutActivity();
    if (checkout != null && checkout.externalBrowserOverCard) {
      returnToPresentedCard();
    }
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

  /**
   * Ends a handoff the player dismissed from the dim overlay, before a browser covered the card or
   * after one closed without a close signal. Cancels any launch still pending and reports the
   * handoff's final event; the caller finishes the card.
   */
  void abandonPendingExternalBrowserCheckoutDismiss(StashCardActivity checkout) {
    if (!ownsCheckout(checkout) || pendingCheckoutDismissAfterExternalBrowser == null) {
      return;
    }
    pendingCheckoutDismissAfterExternalBrowser = null;
    cancelBrowserCloseTrackingLaunch();
    invokeBrowserDismissedListenerAndDismissCheckout();
  }

  private void notifyCardDismissedListener() {
    StashNative.StashNativeListener l = getListener();
    if (l != null) {
      try {
        l.onCardDismissed();
      } catch (Exception e) {
        Log.w(TAG, "Error in card dismissal callback: " + e.getMessage(), e);
      }
    }
  }

  private void invokeBrowserDismissedListenerAndDismissCheckout() {
    final Runnable dismiss = pendingCheckoutDismissAfterExternalBrowser;
    pendingCheckoutDismissAfterExternalBrowser = null;
    // The browser has ended. A recreated host never resumes as the instance that opened it, so
    // its resume cannot be relied on to stop keep-alive.
    Activity host = getActivity();
    Context keepAliveContext = host != null ? host : registeredAppContext;
    if (keepAliveContext != null) {
      stopKeepAliveForegroundService(keepAliveContext);
    }
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

  private boolean ownsCheckout(StashCardActivity checkout) {
    return checkout != null && checkout == getCheckoutActivity()
        && checkout.getPresentationSessionId() == presentationSessionId
        && !checkout.isDismissing && !checkout.isFinishing() && !checkout.isDestroyed();
  }

  private Runnable forCheckout(StashCardActivity checkout, Runnable action) {
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
      StashCardActivity checkoutActivity,
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
      if (getCheckoutActivity() == checkoutActivity && checkoutActivity.isDismissing
          && browserSessionId == browserBeforeCallback) {
        // dismiss() from the callback: no browser opens, and the card ends as dismissed, as on
        // iOS. The card's own dismissal event is suppressed because the handoff began. A reset, a
        // new presentation, or a browser the host opens before this runs retires the card
        // silently, as the same calls do inside the callback.
        long session = presentationSessionId;
        long browserSession = browserSessionId;
        mainHandler.post(() -> {
          if (session == presentationSessionId && browserSession == browserSessionId
              && !isCurrentlyPresented) {
            notifyCardDismissedListener();
          }
        });
      }
      return;
    }
    pendingCheckoutDismissAfterExternalBrowser =
        forCheckout(checkoutActivity, dismissAfterBrowserClosed);
    try {
      if (!launchExternalBrowser(checkoutActivity, url)) {
        // Nothing opened: end the handoff as a closed browser does.
        invokeBrowserDismissedListenerAndDismissCheckout();
        return;
      }
      startKeepAliveForBrowser(checkoutActivity);
      if (hideCheckoutChromeWhileBrowserOpen != null) {
        mainHandler.post(forCheckout(checkoutActivity, hideCheckoutChromeWhileBrowserOpen));
      }
    } catch (Exception e) {
      cancelBrowserCloseTrackingLaunch();
      stopKeepAliveForegroundService(checkoutActivity.getApplicationContext());
      invokeBrowserDismissedListenerAndDismissCheckout();
      Log.w(TAG, "Error opening external browser from checkout: " + e.getMessage(), e);
    }
  }

  /**
   * Opens a browser over a checkout that stays open: the host hears about the external payment,
   * but no browser-dismissal event follows and the card session continues.
   */
  void openExternalBrowserOverCheckout(StashCardActivity checkoutActivity, String url) {
    // Like iOS, ignore repeats while a browser is over the card (a double tap lands before the
    // card pauses; a page can still call while paused beneath the browser).
    if (!isCurrentlyPresented || !ownsCheckout(checkoutActivity)
        || url == null || url.isEmpty()
        || checkoutActivity.externalBrowserOverCard || checkoutActivity.isActivityPaused) {
      return;
    }
    // Cleared when the card resumes after the browser, or below if the launch fails.
    checkoutActivity.externalBrowserOverCard = true;
    long browserBeforeCallback = browserSessionId;
    StashNative.StashNativeListener l = getListener();
    if (l != null) {
      try {
        l.onExternalPayment(url);
      } catch (Exception e) {
        Log.w(TAG, "Error in onExternalPayment: " + e.getMessage(), e);
      }
    }
    // The host may reset, open another checkout, or open its own browser from its callback.
    if (!isCurrentlyPresented || !ownsCheckout(checkoutActivity)
        || browserSessionId != browserBeforeCallback) {
      return;
    }
    boolean launched = false;
    try {
      launched = StashUrlLauncher.launchExternalUrl(checkoutActivity, url, 0)
          != StashUrlLauncher.OPEN_EXTERNAL_NONE;
    } catch (Exception e) {
      Log.w(TAG, "Error opening browser over checkout: " + e.getMessage(), e);
    }
    if (!launched) {
      // Nothing covers the card, so it will not pause and resume to re-arm the page's request.
      checkoutActivity.externalBrowserOverCard = false;
      return;
    }
    // The card activity stops the service again when it resumes.
    startKeepAliveForBrowser(checkoutActivity);
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
   * androidx.browser} is on the classpath, otherwise falls back to ACTION_VIEW tracked through
   * the lifecycle of the launching activity (see {@link #isBrowserBoundaryActivity}).
   *
   * @return false when nothing can open the URL; close tracking is cancelled. The proxy reports
   *     its own launch failure as a closed browser.
   */
  private boolean launchExternalBrowser(Activity activity, String url) {
    if (activity == null || url == null || url.isEmpty()) {
      return false;
    }
    if (StashUrlLauncher.isCustomTabsClassAvailable()) {
      beginBrowserCloseTrackingActivityResult();
      Intent intent = new Intent(activity, StashNativeBrowserProxyActivity.class);
      intent.putExtra(StashNativeBrowserProxyActivity.EXTRA_URL, url);
      intent.putExtra(StashNativeBrowserProxyActivity.EXTRA_SESSION_ID, browserSessionId);
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_ANIMATION);
      activity.startActivity(intent);
      return true;
    }
    int mode = StashUrlLauncher.launchExternalUrl(
        activity, url, CardConstants.REQUEST_CODE_STASH_CUSTOM_TAB);
    if (mode == StashUrlLauncher.OPEN_EXTERNAL_NONE) {
      cancelBrowserCloseTrackingLaunch();
      return false;
    }
    applyBrowserCloseTrackingForLaunchMode(mode);
    return true;
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

  void openScanner(Activity host) {
    openScanner(host, null);
  }

  void openScanner(Activity host, StashNative.ScannerConfig config) {
    openPresentation(host, null, StashPresentationOptions.card(null),
        StashScannerOptions.from(config));
  }

  void scannerUnavailable(StashCardActivity checkout) {
    if (checkout == null || checkout != getCheckoutActivity()
        || checkout.getPresentationSessionId() != presentationSessionId) {
      return;
    }
    isCurrentlyPresented = false;
    checkoutActivityRef = null;
    reportScannerUnavailable();
  }

  private void reportScannerUnavailable() {
    StashNative.StashNativeListener current = getListener();
    if (current != null) {
      try {
        current.onScannerError(StashNative.ScannerError.SCANNER_UNAVAILABLE);
      } catch (Exception error) {
        Log.w(TAG, "Error delivering scanner unavailable failure", error);
      }
    }
  }

  private void openPresentation(
      Activity host, String url, StashPresentationOptions options, StashScannerOptions scanner) {
    if (Looper.myLooper() != Looper.getMainLooper()) {
      mainHandler.post(() -> openPresentation(host, url, options, scanner));
      return;
    }
    if (isCurrentlyPresented || host == null || host.isFinishing() || host.isDestroyed()) {
      return;
    }
    if (scanner != null && !StashScannerContent.isAvailable()) {
      // Present nothing, so no dismissal follows; the error still arrives asynchronously.
      mainHandler.post(this::reportScannerUnavailable);
      return;
    }
    setActivity(host);
    String normalized = scanner != null ? null
        : StashWebViewUtils.normalizeExternalPaymentUrl(url);
    if (scanner == null && normalized == null) {
      return;
    }
    // A terminal callback may reopen before the previous dismissal animation finishes.
    retireCheckoutWithoutCallbacks();
    cleanupAllViews();
    presentationSessionId++;
    presentationIsScanner = scanner != null;
    isCurrentlyPresented = true;
    presentationOptions = options;
    if (scanner == null) {
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
    launchCheckoutActivity(normalized, host, scanner);
  }

  /**
   * Opens the URL through {@link #launchExternalBrowser} (the Custom Tabs proxy when available,
   * else the system browser). An open card stays open beneath it. If nothing can open the URL,
   * {@link StashNative.StashNativeListener#onBrowserDismissed()} follows at once.
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
              if (launchExternalBrowser(finalActivity, finalUrl)) {
                startKeepAliveForBrowser(finalActivity);
              } else {
                // Nothing opened: report it as a closed browser, as the proxy does.
                invokeBrowserDismissedListenerAndDismissCheckout();
              }
            } catch (Exception e) {
              cancelBrowserCloseTrackingLaunch();
              stopKeepAliveForegroundService(finalActivity.getApplicationContext());
              invokeBrowserDismissedListenerAndDismissCheckout();
              Log.w(TAG, "Error in openBrowser: " + e.getMessage(), e);
            }
          });
    } catch (Exception e) {
      Log.w(TAG, "Error in openBrowser: " + e.getMessage(), e);
    }
  }

  void dismissDialog() {
    if (Looper.myLooper() != Looper.getMainLooper()) {
      mainHandler.post(this::dismissDialog);
      return;
    }
    StashCardActivity checkout = getCheckoutActivity();
    if (checkout != null) {
      checkout.dismissWithAnimation();
    } else if (isCurrentlyPresented && registeredSessionId != presentationSessionId) {
      cancelPendingLaunch();
    }
  }

  /**
   * Dismisses an admitted card or scanner whose activity has not been created yet. The new
   * session ID makes that activity finish silently in onCreate; the presentation stays busy until
   * the dismissal callback, as it does during an animated dismissal.
   */
  private void cancelPendingLaunch() {
    long cancelled = ++presentationSessionId;
    boolean scanner = presentationIsScanner;
    releaseLaunchingBackdrop();
    mainHandler.post(() -> {
      if (!isCurrentlyPresented || presentationSessionId != cancelled) {
        return;
      }
      cleanupAllViews();
      StashNative.StashNativeListener l = getListener();
      if (l == null) {
        return;
      }
      try {
        if (scanner) {
          l.onScannerDismissed();
        } else {
          l.onCardDismissed();
        }
      } catch (Exception e) {
        Log.w(TAG, "Error in dismissal callback: " + e.getMessage(), e);
      }
    });
  }

  /**
   * Package-private: the checkout activity registers/deregisters itself for programmatic dismiss.
   */
  void setCheckoutActivity(StashCardActivity activity) {
    checkoutActivityRef = new WeakReference<>(activity);
    if (activity != null) {
      registeredSessionId = activity.getPresentationSessionId();
    }
  }

  private StashCardActivity getCheckoutActivity() {
    WeakReference<StashCardActivity> reference = checkoutActivityRef;
    return reference != null ? reference.get() : null;
  }

  private void retireCheckoutWithoutCallbacks() {
    StashCardActivity checkout = getCheckoutActivity();
    checkoutActivityRef = null;
    if (checkout != null) {
      checkout.finishForPluginResetWithoutCallbacks();
    }
  }

  void clearCheckoutActivity(StashCardActivity activity) {
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

  /** Removes session observers, browser tracking and keep-alive, retaining the live listener. */
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
      // The host-resume observer that normally stops it is unregistered below.
      stopKeepAliveForegroundService(appContext);
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
    StashCardActivity checkout = getCheckoutActivity();
    if (!isCurrentlyPresented) {
      return false;
    }
    return checkout != null && checkout.getPresentationSessionId() == presentationSessionId
        && checkout.isPurchaseProcessing;
  }

  private void launchCheckoutActivity(
      String url, Activity activity, StashScannerOptions scanner) {
    try {
      Intent intent = new Intent(activity, StashCardActivity.class);
      intent.putExtra(CardConstants.INTENT_EXTRA_URL, url);
      intent.putExtra(CardConstants.INTENT_EXTRA_SCANNER, scanner != null);
      if (scanner != null) {
        scanner.put(intent);
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
