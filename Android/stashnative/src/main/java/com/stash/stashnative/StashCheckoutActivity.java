package com.stash.stashnative;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
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
    url = intent.getStringExtra(CardConstants.INTENT_EXTRA_URL);
    initialURL = url;
    if (url == null) {
      finish();
      return;
    }
    if (options.orientation == StashNativeCard.CardConfig.ORIENTATION_PORTRAIT) {
      try {
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT);
      } catch (RuntimeException ignored) {
        // Orientation preferences may be refused; presentation still uses the actual window.
      }
    }
    boolean dark = StashWebViewUtils.isDarkTheme(this);
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
    cardContainer = new StashSheetLayout(this, StashWebViewUtils.dpToPx(this, 16));
    cardContainer.setBackgroundColor(sheetChromeBackgroundArgb);
    cardContainer.setElevation(StashWebViewUtils.dpToPx(this, 24));
    cardContainer.setClickable(true);
    rootLayout.addView(cardContainer, new FrameLayout.LayoutParams(1, 1));
    presentation = new StashPresentationController(this, options);
    cardContainer.controller = presentation;
    contentSizeSupport = new StashContentSizeSupport(this);
    StashCheckoutWebViewSupport.addWebView(this);
    addDragHandle();
    addHomeButton();
    setContentView(rootLayout);
    presentation.attach();
  }

  private void addDragHandle() {
    final FrameLayout tray = new FrameLayout(this);
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
    tray.setContentDescription("Resize checkout");
    tray.setOnTouchListener(presentation);
    tray.setFocusable(true);
    tray.setOnClickListener(
        v -> {
          if (!isPurchaseProcessing) {
            presentation.setExpanded(!presentation.state.expanded);
          }
        });
    cardContainer.addView(
        tray,
        new FrameLayout.LayoutParams(
            StashWebViewUtils.dpToPx(this, 72),
            StashWebViewUtils.dpToPx(this, 28),
            Gravity.TOP | Gravity.CENTER_HORIZONTAL));
    dragHandleArea = tray;
  }

  void applyDragHandlePurchaseProcessingFade(boolean hide) {
    if (dragHandleArea != null) {
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
    if (isPurchaseProcessing || options == null || !options.allowDismiss) {
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
    StashNativeCardPlugin.getInstance().abandonPendingExternalBrowserCheckoutDismiss();
    awaitingExternalBrowserDimOverlay = false;
    dismissWithAnimation();
  }

  void dismissWithAnimation() {
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
    callbackSent = true;
    isDismissing = true;
    finishActivityWithNoAnimation();
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
    StashNativeCardPlugin.getInstance().stopKeepAliveForegroundService(getApplicationContext());
    if (webView != null) {
      webView.onResume();
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
    if (presentation != null) {
      rootLayout.post(presentation::environmentChanged);
    }
  }

  @Override
  public void onBackPressed() {
    requestUserDismiss();
  }

  @Override
  protected void onDestroy() {
    if (presentation != null) {
      presentation.dispose();
    }
    if (contentSizeSupport != null) {
      contentSizeSupport.dispose();
    }
    StashNativeCardPlugin.getInstance().clearCheckoutActivity(this);
    StashCheckoutWebViewSupport.cancelLoadTimers(this);
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
    try {
      android.webkit.CookieManager.getInstance().flush();
    } catch (Throwable expected) {
    }
    if (!callbackSent && !isChangingConfigurations()) {
      callbackSent = true;
      StashCheckoutBridge.emitDialogDismissed(this);
    }
    super.onDestroy();
  }
}
