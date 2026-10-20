package com.stash.stashnative;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.WebView;
import android.widget.Button;
import android.widget.FrameLayout;
import android.window.OnBackInvokedCallback;

/** Same-process host for a responsive card: checkout, browser handoff, or the scanner. */
public class StashCardActivity extends Activity implements StashScannerHost {
  private static final String TAG = "StashNative";
  FrameLayout rootLayout;
  View backdropView;
  private StashHostBackdropSupport hostBackdrop;
  StashSheetLayout cardContainer;
  private View dragHandleArea;
  WebView webView;
  View loadingView;
  Button homeButton;
  String url;
  String initialURL;
  boolean isDismissing;
  boolean callbackSent;
  private boolean paymentResultHandled;
  volatile boolean isPurchaseProcessing;
  boolean effectiveIsDarkForContent;
  int sheetChromeBackgroundArgb;
  StashPresentationOptions options;
  StashPresentationController presentation;
  StashContentSizeSupport contentSizeSupport;
  StashTelemetrySupport telemetrySupport;
  StashScannerContent scannerContent;
  StashScannerOptions scannerOptions;
  boolean scanner;
  boolean scanCompleted;
  private boolean scanCancelled;
  private String scanResult;
  private boolean awaitingExternalBrowserDimOverlay;
  private OnBackInvokedCallback backCallback;
  boolean initialPageLoadComplete;
  boolean networkErrorHandled;

  /** One-shot: rebuild the WebView after an OS renderer kill (not a crash) before giving up. */
  boolean rendererGoneReloadAttempted;

  /**
   * Absolute uptime target for the network deadline so pause/resume does not extend it (0 = unset).
   */
  long networkDeadlineTargetUptime;

  /** Deadline budget frozen at onPause; -1 = nothing frozen. Paused time must not consume it. */
  long networkDeadlineRemainingMs = -1L;

  /** True between onPause and onResume; renderer-gone rebuilds must not arm timers while set. */
  boolean isActivityPaused;

  boolean mainFrameErrorReceived;

  /** Main-thread handler for retry + network deadline (aligned with iOS WebViewLoadDelegate). */
  android.os.Handler loadTimersHandler;

  Runnable retryAfterStallRunnable;
  Runnable networkDeadlineRunnable;

  /** URL with theme used for the initial load; retry uses this with a cache-busting query param. */
  String webViewCommittedReloadUrl;

  /** 0 = first load; 1 = one stall retry issued (no further automatic retries). */
  int webViewRetryCount;

  /** First attempt's URL from the stall retry until the retry starts; its late events are stale. */
  String supersededInitialLoadUrl;

  /** True once the main frame has committed visible content (or progress fallback on older API). */
  boolean mainFrameNavigationCommitted;

  /**
   * After the first loading-overlay crossfade, skip full-screen loading on later navigations
   * (matches iOS WebView staying visible once revealed). Reset on stall retry.
   */
  boolean webViewLoadingRevealComplete;

  /** True while the loading/WebView crossfade is running (ignore duplicate onPageFinished). */
  boolean webViewRevealAnimationRunning;
  android.animation.Animator webViewRevealAnimator;
  StashContentRevealSupport contentRevealSupport;

  /** Monotonic token to ignore stale crossfade callbacks from older loads/retries. */
  int webViewRevealAnimationToken;

  long pageLoadStartTime;
  boolean pageLoadedCallbackSent;

  /** Token the injected main-frame bridge passes with every StashAndroid call. */
  String bridgeDocumentToken;

  /** Issues the token for the next document; calls carrying earlier tokens are ignored. */
  String issueBridgeDocumentToken() {
    bridgeDocumentToken = java.util.UUID.randomUUID().toString();
    return bridgeDocumentToken;
  }

  boolean acceptsBridgeToken(String token) {
    return token != null && token.equals(bridgeDocumentToken);
  }

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    // A restored process must not replay a checkout POST or invent a processing state.
    if (savedInstanceState != null) {
      callbackSent = true;
      if (!savedInstanceState.getBoolean("stash.callbackSent", false)) {
        StashCheckoutBridge.emitDialogDismissed(this);
      }
      finish();
      return;
    }
    StashNativePlugin plugin = StashNativePlugin.getInstance();
    if (!plugin.isCurrentlyPresented()
        || plugin.presentationSessionId != getPresentationSessionId()) {
      callbackSent = true;
      finish();
      return;
    }
    plugin.setCheckoutActivity(this);
    Intent intent = getIntent();
    options = StashPresentationOptions.read(intent);
    scanner = intent.getBooleanExtra(CardConstants.INTENT_EXTRA_SCANNER, false);
    scannerOptions = scanner ? StashScannerOptions.read(intent) : null;
    url = intent.getStringExtra(CardConstants.INTENT_EXTRA_URL);
    initialURL = url;
    if (url == null && !scanner) {
      finish();
      return;
    }
    updateOrientationPreference();
    hostBackdrop = plugin.takeBackdrop(getPresentationSessionId());
    if (hostBackdrop != null
        && getRequestedOrientation() != ActivityInfo.SCREEN_ORIENTATION_PORTRAIT) {
      hostBackdrop.dispose();
      hostBackdrop = null;
    }
    boolean dark = scanner || StashWebViewUtils.isDarkTheme(this);
    sheetChromeBackgroundArgb =
        dark ? Color.parseColor(CardConstants.COLOR_DARK_BG) : Color.WHITE;
    effectiveIsDarkForContent = dark;
    requestWindowFeature(Window.FEATURE_NO_TITLE);
    Window window = getWindow();
    window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
    window.addFlags(WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED);
    StashWindowCompat.setDecorFitsSystemWindows(window, false);
    StashWebViewUtils.applySystemBarAppearanceForSheet(
        window, window.getDecorView());
    if (!createUI()) {
      callbackSent = true;
      isDismissing = true;
      finishActivityWithNoAnimation();
      plugin.scannerUnavailable(this);
      return;
    }
    if (Build.VERSION.SDK_INT >= 33) {
      backCallback = this::requestUserDismiss;
      getOnBackInvokedDispatcher()
          .registerOnBackInvokedCallback(
              android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT, backCallback);
    }
  }

  private boolean createUI() {
    rootLayout = new FrameLayout(this);
    if (hostBackdrop != null) {
      hostBackdrop.attach(this, rootLayout);
    }
    backdropView = new View(this);
    backdropView.setBackgroundColor(Color.parseColor(CardConstants.COLOR_BACKGROUND_DIM));
    rootLayout.addView(backdropView, new FrameLayout.LayoutParams(-1, -1));
    backdropView.setOnClickListener(v -> requestUserDismiss());
    cardContainer = new StashSheetLayout(this, StashWebViewUtils.dpToPx(this, 28));
    cardContainer.setBackgroundColor(sheetChromeBackgroundArgb);
    cardContainer.setElevation(StashWebViewUtils.dpToPx(this, 24));
    cardContainer.setClickable(true);
    rootLayout.addView(cardContainer, new FrameLayout.LayoutParams(1, 1));
    presentation = new StashPresentationController(this, options);
    cardContainer.controller = presentation;
    if (scanner) {
      View scannerView = null;
      scannerContent = StashScannerContent.create(this);
      try {
        scannerView = scannerContent != null ? scannerContent.getView() : null;
      } catch (Throwable error) {
        Log.w(TAG, "QR Code Linking is missing a library it needs", error);
      }
      if (scannerView == null) {
        disposeScanner();
        scannerContent = null;
        return false;
      }
      cardContainer.addView(scannerView, new FrameLayout.LayoutParams(-1, -1));
    } else {
      contentSizeSupport = new StashContentSizeSupport(this);
      telemetrySupport = new StashTelemetrySupport(this);
      StashCheckoutWebViewSupport.addWebView(this);
    }
    addDragHandle();
    if (!scanner) {
      addHomeButton();
    }
    setContentView(rootLayout);
    presentation.attach();
    return true;
  }

  private void addDragHandle() {
    final FrameLayout tray = new FrameLayout(this);
    GradientDrawable rippleMask = new GradientDrawable();
    rippleMask.setColor(Color.WHITE);
    rippleMask.setCornerRadius(StashWebViewUtils.dpToPx(this, 24));
    tray.setBackground(new RippleDrawable(
        ColorStateList.valueOf(effectiveIsDarkForContent ? 0x24ffffff : 0x18000000),
        null, rippleMask));
    View handle = new View(this);
    GradientDrawable background = new GradientDrawable();
    background.setColor(StashBackgroundColorUtils.dragHandleFor(sheetChromeBackgroundArgb));
    background.setCornerRadius(StashWebViewUtils.dpToPx(this, 3));
    handle.setBackground(background);
    FrameLayout.LayoutParams pill =
        new FrameLayout.LayoutParams(
            StashWebViewUtils.dpToPx(this, 36),
            StashWebViewUtils.dpToPx(this, 4),
            Gravity.TOP | Gravity.CENTER_HORIZONTAL);
    pill.topMargin = StashWebViewUtils.dpToPx(this, 8);
    tray.addView(handle, pill);
    tray.setContentDescription(scanner ? "Resize scanner" : "Resize checkout");
    tray.setOnTouchListener(presentation);
    tray.setFocusable(true);
    tray.setOnClickListener(
        v -> {
          if (!isInteractionLocked()) {
            presentation.setExpanded(!presentation.state.expanded);
          }
        });
    cardContainer.addView(
        tray,
        new FrameLayout.LayoutParams(
            StashWebViewUtils.dpToPx(this, 72),
            StashWebViewUtils.dpToPx(this, 48),
            Gravity.TOP | Gravity.CENTER_HORIZONTAL));
    dragHandleArea = tray;
  }

  void applyDragHandlePurchaseProcessingFade(boolean hide) {
    if (dragHandleArea != null) {
      dragHandleArea.setPressed(false);
      dragHandleArea.setAlpha(hide ? 0 : 1);
      dragHandleArea.setEnabled(!hide);
    }
  }

  private void addHomeButton() {
    homeButton = new Button(this);
    homeButton.setText("Home");
    homeButton.setTextSize(12);
    homeButton.setContentDescription("Return to checkout");
    homeButton.setVisibility(View.GONE);
    FrameLayout.LayoutParams params =
        new FrameLayout.LayoutParams(-2, StashWebViewUtils.dpToPx(this, 40));
    params.gravity = Gravity.TOP | Gravity.START;
    homeButton.setOnClickListener(
        v -> {
          if (webView != null && initialURL != null) {
            webView.loadUrl(
                StashWebViewUtils.appendThemeQueryParameter(initialURL, effectiveIsDarkForContent));
          }
        });
    cardContainer.addView(homeButton, params);
  }

  void animateExpand() {
    if (presentation != null) {
      presentation.setExpanded(true);
    }
  }

  void animateCollapse() {
    if (presentation != null) {
      presentation.setExpanded(false);
    }
  }

  void requestUserDismiss() {
    if (options != null && options.allowDismiss) {
      requestCloseFromPage();
    }
  }

  void requestCloseFromPage() {
    if (isInteractionLocked() || options == null) {
      return;
    }
    if (awaitingExternalBrowserDimOverlay) {
      finishAfterExternalBrowserClose();
    } else {
      dismissWithAnimation();
    }
  }

  void handleNetworkError() {
    if (networkErrorHandled || isDismissing) {
      return;
    }
    networkErrorHandled = true;
    callbackSent = true;
    StashCheckoutLoadingSupport.cancelLoadTimers(this);
    try {
      StashCheckoutBridge.emitNetworkError(this);
    } catch (Exception e) {
      Log.w(TAG, "Network error broadcast failed: " + e.getMessage(), e);
    }
    finishActivityWithNoAnimation();
  }

  void hideCardSheetLeavingDimOverlay() {
    if (isDismissing || awaitingExternalBrowserDimOverlay) {
      return;
    }
    awaitingExternalBrowserDimOverlay = true;
    if (webView != null) {
      webView.onPause();
    }
    if (cardContainer != null) {
      cardContainer.setVisibility(View.INVISIBLE);
    }
  }

  void finishAfterExternalBrowserClose() {
    if (isDismissing) {
      return;
    }
    StashNativePlugin.getInstance().abandonPendingExternalBrowserCheckoutDismiss(this);
    awaitingExternalBrowserDimOverlay = false;
    dismissWithAnimation();
  }

  void dismissWithAnimation() {
    cancelScan();
    if (isDismissing) {
      return;
    }
    isDismissing = true;
    if (presentation != null) {
      presentation.dismiss(this::finishActivityWithNoAnimation);
    } else {
      finishActivityWithNoAnimation();
    }
  }

  private void finishActivityWithNoAnimation() {
    isDismissing = true;
    if (hostBackdrop != null && getPresentationSessionId()
        == StashNativePlugin.getInstance().presentationSessionId) {
      cardContainer.setVisibility(View.INVISIBLE);
      backdropView.setVisibility(View.INVISIBLE);
      if (hostBackdrop.finishAfterRotation(this::finishImmediately)) {
        return;
      }
    }
    finishImmediately();
  }

  private void finishImmediately() {
    finish();
    overridePendingTransition(0, 0);
  }

  void finishForPluginResetWithoutCallbacks() {
    cancelScan();
    callbackSent = true;
    isDismissing = true;
    if (hostBackdrop != null) {
      hostBackdrop.cancelFinish();
    }
    finishImmediately();
  }

  boolean isInteractionLocked() {
    return isPurchaseProcessing || scanCompleted;
  }

  @Override
  public Activity getActivity() {
    return this;
  }

  @Override
  public StashScannerOptions getScannerOptions() {
    if (scannerOptions == null) {
      scannerOptions = StashScannerOptions.read(getIntent());
    }
    return scannerOptions;
  }

  @Override
  public boolean isDismissing() {
    return isDismissing;
  }

  @Override
  public void requestDismiss() {
    requestUserDismiss();
  }

  @Override
  public void reportScannerError(StashNative.ScannerError error) {
    if (isDismissing || error == null) {
      return;
    }
    try {
      StashCheckoutBridge.emitScannerError(this, error);
    } catch (Exception e) {
      Log.w(TAG, "Scanner error broadcast failed: " + e.getMessage(), e);
    }
  }

  @Override
  public void completeScan(String content) {
    if (!scanner || scanCompleted || isDismissing || scannerContent == null
        || content == null || content.isEmpty()) {
      return;
    }
    scanCompleted = true;
    presentation.processingStarted();
    applyDragHandlePurchaseProcessingFade(true);
    callScanner(() -> scannerContent.showConnected(() -> {
      if (scanCancelled || isDismissing) {
        return;
      }
      isDismissing = true;
      presentation.dismiss(() -> {
        if (!scanCancelled) {
          scanResult = content;
          callbackSent = true;
        }
        finishActivityWithNoAnimation();
      });
    }));
  }

  private void cancelScan() {
    scanCancelled = true;
    scanResult = null;
    disposeScanner();
  }

  /**
   * Calls into the optional scanner module. A library that fails only on first use (a partial
   * installation the module's initialization did not catch) closes the card as
   * SCANNER_UNAVAILABLE, without a dismissal callback, instead of crashing the host process.
   */
  private void callScanner(Runnable call) {
    if (scannerContent == null) {
      return;
    }
    try {
      call.run();
    } catch (Throwable error) {
      Log.w(TAG, "QR Code Linking is missing a library it needs", error);
      disposeScanner();
      scannerContent = null;
      if (isDismissing) {
        return;
      }
      callbackSent = true;
      isDismissing = true;
      finishActivityWithNoAnimation();
      StashNativePlugin.getInstance().scannerUnavailable(this);
    }
  }

  void setScannerBottomInset(int inset) {
    callScanner(() -> scannerContent.setBottomInset(inset));
  }

  private void disposeScanner() {
    if (scannerContent == null) {
      return;
    }
    try {
      scannerContent.dispose();
    } catch (Throwable error) {
      Log.w(TAG, "Scanner cleanup failed", error);
    }
  }

  void notifyPaymentResult(boolean success, String order) {
    try {
      runOnUiThread(
          () -> {
            try {
              if (isDismissing || (options.autoClose && paymentResultHandled)) {
                return;
              }
              isPurchaseProcessing = false;
              applyDragHandlePurchaseProcessingFade(false);
              try {
                if (success) {
                  StashCheckoutBridge.emitPaymentSuccess(
                      StashCardActivity.this,
                      StashCheckoutBridge.capPaymentOrder(order),
                      options.autoClose);
                } else {
                  StashCheckoutBridge.emitPaymentFailure(
                      StashCardActivity.this, options.autoClose);
                }
              } catch (Exception e) {
                // The once-flags are still clear. End through the network error path so the
                // plugin releases the presentation instead of waiting on a lost result.
                Log.w(TAG, "Payment result broadcast failed: " + e.getMessage(), e);
                handleNetworkError();
                return;
              }
              if (options.autoClose) {
                callbackSent = true;
                paymentResultHandled = true;
                dismissWithAnimation();
              }
            } catch (Exception e) {
              Log.w(TAG, "Error delivering payment result: " + e.getMessage(), e);
              try {
                finish();
              } catch (Exception e2) {
                Log.w(TAG, "Error finishing activity: " + e2.getMessage(), e2);
              }
            }
          });
    } catch (Exception e) {
      Log.w(TAG, "Error scheduling payment result: " + e.getMessage(), e);
    }
  }

  @Override
  public void onEnterAnimationComplete() {
    super.onEnterAnimationComplete();
    // Start after the system's activity/rotation transition stops covering the card.
    if (presentation != null) {
      presentation.windowEntered();
    }
  }

  @Override
  protected void onPause() {
    super.onPause();
    isActivityPaused = true;
    callScanner(() -> scannerContent.pause());
    if (contentRevealSupport != null) {
      contentRevealSupport.pause();
    }
    if (webView != null) {
      webView.onPause();
    }
    // A paused WebView cannot load; do not let the network deadline expire against a frozen load.
    if (!mainFrameNavigationCommitted && !networkErrorHandled) {
      // Freeze the remaining budget: uptime keeps ticking while paused, so the absolute
      // target would otherwise be already expired on resume after any longer pause.
      if (networkDeadlineTargetUptime != 0L) {
        networkDeadlineRemainingMs =
            Math.max(0L, networkDeadlineTargetUptime - android.os.SystemClock.uptimeMillis());
      }
      StashCheckoutLoadingSupport.cancelLoadTimers(this);
    }
  }

  @Override
  protected void onResume() {
    super.onResume();
    isActivityPaused = false;
    if (!isDismissing) {
      callScanner(() -> scannerContent.resume());
    }
    StashNativePlugin.getInstance().stopKeepAliveForegroundService(getApplicationContext());
    if (webView != null) {
      webView.onResume();
    }
    if (contentRevealSupport != null) {
      contentRevealSupport.check();
    }
    // Restart the retry/deadline window if the initial load never committed, thawing the
    // budget frozen in onPause (paused time does not count against the deadline).
    if (!mainFrameNavigationCommitted && !networkErrorHandled && !isDismissing && webView != null) {
      if (networkDeadlineRemainingMs >= 0L) {
        networkDeadlineTargetUptime =
            android.os.SystemClock.uptimeMillis() + networkDeadlineRemainingMs;
        networkDeadlineRemainingMs = -1L;
      }
      StashCheckoutLoadingSupport.scheduleInitialLoadTimers(this);
    }
  }

  long getPresentationSessionId() {
    return getIntent() != null
        ? getIntent().getLongExtra(StashCheckoutBridge.EXTRA_SESSION_ID, 0L)
        : 0L;
  }

  @Override
  protected void onSaveInstanceState(Bundle outState) {
    outState.putBoolean("stash.callbackSent", callbackSent);
    super.onSaveInstanceState(outState);
  }

  @Override
  public void onConfigurationChanged(Configuration configuration) {
    super.onConfigurationChanged(configuration);
    updateOrientationPreference();
    if (hostBackdrop != null) {
      hostBackdrop.geometryChanged();
    }
    callScanner(() -> scannerContent.geometryChanged());
    if (presentation != null) {
      rootLayout.post(presentation::environmentChanged);
    }
  }

  @Override
  public void onMultiWindowModeChanged(boolean inMultiWindow) {
    super.onMultiWindowModeChanged(inMultiWindow);
    updateOrientationPreference();
  }

  private void updateOrientationPreference() {
    if (options == null || isDismissing) {
      return;
    }
    boolean windowed = Build.VERSION.SDK_INT >= 24 && isInMultiWindowMode();
    boolean compact = getResources().getConfiguration().smallestScreenWidthDp < 600;
    int orientation = !scanner
        && options.orientation == StashNative.CardConfig.ORIENTATION_PORTRAIT
        && compact && !windowed
        ? ActivityInfo.SCREEN_ORIENTATION_PORTRAIT : ActivityInfo.SCREEN_ORIENTATION_BEHIND;
    if (getRequestedOrientation() != orientation) {
      try {
        setRequestedOrientation(orientation);
      } catch (RuntimeException ignored) {
        // Some hosts refuse rotation; sizing always follows the actual window.
      }
    }
  }

  @Override
  public void onBackPressed() {
    requestUserDismiss();
  }

  @Override
  public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) {
    super.onRequestPermissionsResult(requestCode, permissions, results);
    if (requestCode == StashScannerContent.CAMERA_PERMISSION_REQUEST) {
      callScanner(() -> scannerContent.permissionResult());
    }
  }

  @Override
  protected void onDestroy() {
    if (hostBackdrop != null) {
      hostBackdrop.dispose();
      hostBackdrop = null;
    }
    disposeScanner();
    if (presentation != null) {
      presentation.dispose();
    }
    if (contentSizeSupport != null) {
      contentSizeSupport.dispose();
    }
    if (telemetrySupport != null) {
      telemetrySupport.dispose();
    }
    StashNativePlugin.getInstance().clearCheckoutActivity(this);
    StashCheckoutLoadingSupport.cancelLoadTimers(this);
    StashCheckoutLoadingSupport.cancelLoadingRevealAnimation(this);
    if (contentRevealSupport != null) {
      contentRevealSupport.dispose();
    }
    if (Build.VERSION.SDK_INT >= 33 && backCallback != null) {
      getOnBackInvokedDispatcher().unregisterOnBackInvokedCallback(backCallback);
    }
    if (webView != null) {
      webView.stopLoading();
      webView.removeJavascriptInterface(StashWebViewUtils.JS_INTERFACE_NAME);
      webView.setWebViewClient(null);
      webView.setWebChromeClient(null);
      cardContainer.removeView(webView);
      webView.destroy();
      webView = null;
    }
    if (!scanner) {
      try {
        android.webkit.CookieManager.getInstance().flush();
      } catch (Throwable expected) {
        // A checkout may close before the WebView process starts.
      }
    }
    if (!callbackSent && !isChangingConfigurations()) {
      callbackSent = true;
      StashCheckoutBridge.emitDialogDismissed(this);
    }
    super.onDestroy();
    if (scanResult != null) {
      StashCheckoutBridge.emitQrCodeScanned(this, scanResult);
      scanResult = null;
    }
  }
}
