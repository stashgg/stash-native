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

/** Same-process host for a responsive card. */
public class StashCheckoutActivity extends Activity {
  private static final String TAG = "StashNativeCard";
  FrameLayout rootLayout;
  View backdropView;
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
  StashCodeLinkSupport codeLinkSupport;
  boolean codeLink;
  boolean codeLinkCompleted;
  private boolean codeLinkCancelled;
  private String codeLinkResult;
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
    StashNativeCardPlugin plugin = StashNativeCardPlugin.getInstance();
    if (!plugin.isCurrentlyPresented()
        || plugin.presentationSessionId != getPresentationSessionId()) {
      callbackSent = true;
      finish();
      return;
    }
    plugin.setCheckoutActivity(this);
    Intent intent = getIntent();
    options = StashPresentationOptions.read(intent);
    codeLink = intent.getBooleanExtra(CardConstants.INTENT_EXTRA_CODE_LINK, false);
    url = intent.getStringExtra(CardConstants.INTENT_EXTRA_URL);
    initialURL = url;
    if (url == null && !codeLink) {
      finish();
      return;
    }
    updateOrientationPreference();
    boolean dark = codeLink || StashWebViewUtils.isDarkTheme(this);
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
    createUI();
    if (Build.VERSION.SDK_INT >= 33) {
      backCallback = this::requestUserDismiss;
      getOnBackInvokedDispatcher()
          .registerOnBackInvokedCallback(
              android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT, backCallback);
    }
  }

  private void createUI() {
    rootLayout = new FrameLayout(this);
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
    if (codeLink) {
      codeLinkSupport = new StashCodeLinkSupport(this);
      cardContainer.addView(codeLinkSupport.view, new FrameLayout.LayoutParams(-1, -1));
    } else {
      contentSizeSupport = new StashContentSizeSupport(this);
      telemetrySupport = new StashTelemetrySupport(this);
      StashCheckoutWebViewSupport.addWebView(this);
    }
    addDragHandle();
    if (!codeLink) {
      addHomeButton();
    }
    setContentView(rootLayout);
    presentation.attach();
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
    tray.setContentDescription(codeLink ? "Resize scanner" : "Resize checkout");
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
    if (isInteractionLocked() || options == null || !options.allowDismiss) {
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
    StashCheckoutWebViewSupport.cancelLoadTimers(this);
    StashCheckoutBridge.emitNetworkError(this);
    callbackSent = true;
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
    StashNativeCardPlugin.getInstance().abandonPendingExternalBrowserCheckoutDismiss(this);
    awaitingExternalBrowserDimOverlay = false;
    dismissWithAnimation();
  }

  void dismissWithAnimation() {
    cancelCodeLink();
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
    finish();
    overridePendingTransition(0, 0);
  }

  void finishForPluginResetWithoutCallbacks() {
    cancelCodeLink();
    callbackSent = true;
    isDismissing = true;
    finishActivityWithNoAnimation();
  }

  boolean isInteractionLocked() {
    return isPurchaseProcessing || codeLinkCompleted;
  }

  void completeCodeLink(String content) {
    if (!codeLink || codeLinkCompleted || isDismissing || codeLinkSupport == null
        || content == null || content.isEmpty()) {
      return;
    }
    codeLinkCompleted = true;
    presentation.processingStarted();
    applyDragHandlePurchaseProcessingFade(true);
    codeLinkSupport.showConnected(() -> {
      if (codeLinkCancelled || isDismissing) {
        return;
      }
      isDismissing = true;
      presentation.dismiss(() -> {
        if (!codeLinkCancelled) {
          codeLinkResult = content;
          callbackSent = true;
        }
        finishActivityWithNoAnimation();
      });
    });
  }

  private void cancelCodeLink() {
    codeLinkCancelled = true;
    codeLinkResult = null;
    if (codeLinkSupport != null) {
      codeLinkSupport.dispose();
    }
  }

  void notifyListenerAndDismiss(String messageType, String messageBody, boolean success) {
    try {
      runOnUiThread(
          () -> {
            try {
              if (isDismissing) {
                return;
              }
              if (success) {
                // Always re-enable interaction so the user can dismiss the card after the result.
                isPurchaseProcessing = false;
                applyDragHandlePurchaseProcessingFade(false);
                // Only latch callbackSent (which suppresses the onDestroy dismiss callback) when
                // the
                // card actually auto-closes as part of this payment event. With autoClose = false
                // the
                // card stays open and the later, user-initiated close must still emit
                // onDialogDismissed.
                if (options.autoClose) {
                  callbackSent = true;
                }
              }

              boolean isPaymentEvent =
                  CardConstants.MESSAGE_TYPE_SUCCESS.equals(messageType)
                      || CardConstants.MESSAGE_TYPE_FAILURE.equals(messageType);

              // Once-guard: with autoClose on, only the first payment result is delivered (parity
              // with
              // iOS handlePaymentSuccessSignal / handlePaymentFailureSignal). autoClose off never
              // gates.
              if (isPaymentEvent && options.autoClose) {
                if (paymentResultHandled) {
                  return;
                }
                paymentResultHandled = true;
              }

              switch (messageType) {
                case CardConstants.MESSAGE_TYPE_SUCCESS:
                  StashCheckoutBridge.emitPaymentSuccess(
                      StashCheckoutActivity.this,
                      messageBody != null && !messageBody.isEmpty() ? messageBody : null,
                      options.autoClose);
                  break;
                case CardConstants.MESSAGE_TYPE_FAILURE:
                  StashCheckoutBridge.emitPaymentFailure(
                      StashCheckoutActivity.this, options.autoClose);
                  break;
                case CardConstants.MESSAGE_TYPE_OPTIN:
                  StashCheckoutBridge.emitOptIn(StashCheckoutActivity.this, messageBody);
                  break;
                default:
                  break;
              }

              if (!isPaymentEvent || options.autoClose) {
                dismissWithAnimation();
              }
            } catch (Exception e) {
              Log.w(TAG, "Error in notifyListenerAndDismiss UI thread: " + e.getMessage(), e);
              try {
                finish();
              } catch (Exception e2) {
                Log.w(TAG, "Error finishing activity: " + e2.getMessage(), e2);
              }
            }
          });
    } catch (Exception e) {
      Log.w(TAG, "Error scheduling notifyListenerAndDismiss: " + e.getMessage(), e);
    }
  }

  @Override
  protected void onPause() {
    super.onPause();
    isActivityPaused = true;
    if (codeLinkSupport != null) {
      codeLinkSupport.pause();
    }
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
      StashCheckoutWebViewSupport.cancelLoadTimers(this);
    }
  }

  @Override
  protected void onResume() {
    super.onResume();
    isActivityPaused = false;
    if (codeLinkSupport != null && !isDismissing) {
      codeLinkSupport.resume();
    }
    StashNativeCardPlugin.getInstance().stopKeepAliveForegroundService(getApplicationContext());
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
      StashCheckoutWebViewSupport.scheduleInitialLoadTimers(this);
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
    if (codeLinkSupport != null) {
      codeLinkSupport.geometryChanged();
    }
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
    if (options == null) {
      return;
    }
    boolean windowed = Build.VERSION.SDK_INT >= 24 && isInMultiWindowMode();
    boolean compact = getResources().getConfiguration().smallestScreenWidthDp < 600;
    int orientation = !codeLink
        && options.orientation == StashNativeCard.CardConfig.ORIENTATION_PORTRAIT
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
    if (requestCode == StashCodeLinkSupport.CAMERA_PERMISSION_REQUEST && codeLinkSupport != null) {
      codeLinkSupport.permissionResult();
    }
  }

  @Override
  protected void onDestroy() {
    if (codeLinkSupport != null) {
      codeLinkSupport.dispose();
    }
    if (presentation != null) {
      presentation.dispose();
    }
    if (contentSizeSupport != null) {
      contentSizeSupport.dispose();
    }
    if (telemetrySupport != null) {
      telemetrySupport.dispose();
    }
    StashNativeCardPlugin.getInstance().clearCheckoutActivity(this);
    StashCheckoutWebViewSupport.cancelLoadTimers(this);
    StashCheckoutWebViewSupport.cancelLoadingRevealAnimation(this);
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
    if (!codeLink) {
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
    if (codeLinkResult != null) {
      StashCheckoutBridge.emitQrCodeScanned(this, codeLinkResult);
      codeLinkResult = null;
    }
  }
}
