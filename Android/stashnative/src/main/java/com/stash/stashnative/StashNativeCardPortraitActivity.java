package com.stash.stashnative;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.ValueAnimator;
import android.app.Activity;
import android.window.OnBackInvokedCallback;
import android.window.OnBackInvokedDispatcher;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Outline;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.Surface;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewOutlineProvider;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.WebView;
import android.graphics.Bitmap;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import androidx.core.view.ViewCompat;

/**
 * Activity that displays the Stash Pay checkout as a card or popup overlay.
 */
public class StashNativeCardPortraitActivity extends Activity {
  private static final String TAG = "StashNativeCard";

  FrameLayout rootLayout;
  private View backdropView;
  /** Drag handle strip; faded out while {@link #isPurchaseProcessing} so the sheet looks non-dismissable. */
  private View dragHandleArea;
  FrameLayout cardContainer;
  WebView webView;
  View loadingView;
  Button homeButton;
  
  String url;
  String initialURL;
  boolean usePopup;
  boolean useModal;
  boolean isExpanded;
  boolean isDismissing;
  /** True after the sheet was hidden for external browser; dim overlay stays until browser closes. */
  private boolean awaitingExternalBrowserDimOverlay;
  private boolean pendingCreateUIAfterRotation;
  boolean callbackSent;
  boolean googlePayRedirectHandled;
  boolean isPurchaseProcessing;
  boolean initialPageLoadComplete;
  boolean networkErrorHandled;
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
  /**
   * Pixel height to restore when collapsing the phone sheet. Set at creation, updated on
   * orientation change, and snapshotted from layout params immediately before each expand so the
   * collapse animation matches the actual initial/collapsed card height.
   */
  private int collapsedCardTargetHeightPx = -1;
  /** Tablet: configured base card height for SDK collapse (updated on rotation). */
  private int tabletSdkBaseHeightPx = -1;
  /** Running {@link #animateCardHeight} animator; cancelled before starting a new height change. */
  private ValueAnimator cardHeightAnimator;
  /** Soft-keyboard overlap currently applied, px; 0 when the keyboard is hidden. */
  int currentImeOverlapPx = 0;
  /** Pre-API-30: last keyboard-free bottom system-window inset (nav bar), used to keep the card static. */
  int navBottomInsetPx = 0;
  /** Pre-API-30 keyboard detector (Type.ime() is 30+); null on API 30+. */
  android.view.ViewTreeObserver.OnGlobalLayoutListener imeGlobalLayoutListener;
  /** True while the keyboard is open (suppresses page-driven expand/collapse during that time). */
  boolean keyboardActive = false;
  /** True when the keyboard-show triggered the card expand, so we collapse it again on keyboard hide. */
  boolean keyboardExpandedCard = false;
  
  // Phone card: portrait = full width + height ratio; landscape = width/height ratios
  float cardHeightRatioPortrait = CardConstants.DEFAULT_CARD_HEIGHT_RATIO;
  boolean forcePortraitOnCheckout = false;
  float cardWidthRatioLandscape = CardConstants.DEFAULT_CARD_WIDTH_RATIO_LANDSCAPE;
  float cardHeightRatioLandscape = CardConstants.DEFAULT_CARD_HEIGHT_RATIO_LANDSCAPE;
  
  // Modal configuration
  private boolean modalAllowDismiss = true;
  /** When false, dialog stays open after payment success/failure (callback still fires). */
  private boolean autoCloseOnPaymentEvent = true;
  float modalPhoneWidthRatioPortrait =
      CardConstants.DEFAULT_MODAL_PHONE_WIDTH_RATIO_PORTRAIT;
  float modalPhoneHeightRatioPortrait =
      CardConstants.DEFAULT_MODAL_PHONE_HEIGHT_RATIO_PORTRAIT;
  float modalPhoneWidthRatioLandscape =
      CardConstants.DEFAULT_MODAL_PHONE_WIDTH_RATIO_LANDSCAPE;
  float modalPhoneHeightRatioLandscape =
      CardConstants.DEFAULT_MODAL_PHONE_HEIGHT_RATIO_LANDSCAPE;
  float modalTabletWidthRatioPortrait =
      CardConstants.DEFAULT_MODAL_TABLET_WIDTH_RATIO_PORTRAIT;
  float modalTabletHeightRatioPortrait =
      CardConstants.DEFAULT_MODAL_TABLET_HEIGHT_RATIO_PORTRAIT;
  float modalTabletWidthRatioLandscape =
      CardConstants.DEFAULT_MODAL_TABLET_WIDTH_RATIO_LANDSCAPE;
  float modalTabletHeightRatioLandscape =
      CardConstants.DEFAULT_MODAL_TABLET_HEIGHT_RATIO_LANDSCAPE;
  
  // Orientation-specific tablet card configuration
  float tabletWidthRatioPortrait = CardConstants.DEFAULT_TABLET_WIDTH_RATIO_PORTRAIT;
  float tabletHeightRatioPortrait = CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_PORTRAIT;
  float tabletWidthRatioLandscape = CardConstants.DEFAULT_TABLET_WIDTH_RATIO_LANDSCAPE;
  float tabletHeightRatioLandscape = CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_LANDSCAPE;

  /** Cached at activity start to avoid repeated theme/device lookups. */
  private boolean cachedIsDarkTheme;
  boolean cachedIsTablet;

  /** Custom sheet chrome from intent (#hex); when false, {@link #sheetChromeBackgroundArgb} is still set from system theme. */
  private boolean chromeColorOverrideActive;
  /** Card/modal container + WebView chrome background (custom or system-derived). */
  int sheetChromeBackgroundArgb;
  /** WebView force-dark, URL theme=, home/error styling. */
  boolean effectiveIsDarkForContent;
  private OnBackInvokedCallback onBackInvokedCallback;

  /** Optional host-supplied screenshot used as background behind the dim overlay. */
  private Bitmap hostBackdropBitmap;
  private ImageView hostBackdropImageView;
  /** {@link android.view.Display#getRotation()} when checkout opened; drives backdrop ±90° mapping. */
  private int hostBackdropSourceDisplayRotation = Surface.ROTATION_90;
  /**
   * After card dismiss, wait for landscape {@link Configuration} before {@link #finish()} so the
   * host backdrop can cover the system rotation (force-portrait phone checkout only).
   */
  private boolean pendingFinishAfterLandscape;
  final Runnable pendingLandscapeFinishFallback = this::completeDeferredFinishFromLandscape;

  @Override
  protected void attachBaseContext(Context newBase) {
    super.attachBaseContext(newBase);
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      String processName = android.app.Application.getProcessName();
      if (processName != null && processName.contains(":")) {
        String suffix = processName.substring(processName.indexOf(':') + 1);
        try {
          WebView.setDataDirectorySuffix(suffix);
        } catch (IllegalStateException e) {
          Log.w(TAG, "WebView data directory suffix already set");
        }
      }
    }
  }

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    
    try {
      Intent intent = getIntent();
      if (intent == null) {
        Log.e(TAG, "Intent is null in onCreate");
        finish();
        return;
      }
      
      url = intent.getStringExtra(CardConstants.INTENT_EXTRA_URL);
      initialURL = intent.getStringExtra(CardConstants.INTENT_EXTRA_INITIAL_URL);
      usePopup = intent.getBooleanExtra(CardConstants.INTENT_EXTRA_USE_POPUP, false);
      useModal = intent.getBooleanExtra(CardConstants.INTENT_EXTRA_USE_MODAL, false);

      cardHeightRatioPortrait = intent.getFloatExtra(
          CardConstants.INTENT_EXTRA_CARD_HEIGHT_RATIO_PORTRAIT,
          CardConstants.DEFAULT_CARD_HEIGHT_RATIO);
      forcePortraitOnCheckout = intent.getBooleanExtra(
          CardConstants.INTENT_EXTRA_FORCE_PORTRAIT_ON_CHECKOUT, false);
      cardWidthRatioLandscape = intent.getFloatExtra(
          CardConstants.INTENT_EXTRA_CARD_WIDTH_RATIO_LANDSCAPE,
          CardConstants.DEFAULT_CARD_WIDTH_RATIO_LANDSCAPE);
      cardHeightRatioLandscape = intent.getFloatExtra(
          CardConstants.INTENT_EXTRA_CARD_HEIGHT_RATIO_LANDSCAPE,
          CardConstants.DEFAULT_CARD_HEIGHT_RATIO_LANDSCAPE);
      tabletWidthRatioPortrait = intent.getFloatExtra(
          CardConstants.INTENT_EXTRA_TABLET_WIDTH_RATIO_PORTRAIT,
          CardConstants.DEFAULT_TABLET_WIDTH_RATIO_PORTRAIT);
      tabletHeightRatioPortrait = intent.getFloatExtra(
          CardConstants.INTENT_EXTRA_TABLET_HEIGHT_RATIO_PORTRAIT,
          CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_PORTRAIT);
      tabletWidthRatioLandscape = intent.getFloatExtra(
          CardConstants.INTENT_EXTRA_TABLET_WIDTH_RATIO_LANDSCAPE,
          CardConstants.DEFAULT_TABLET_WIDTH_RATIO_LANDSCAPE);
      tabletHeightRatioLandscape = intent.getFloatExtra(
          CardConstants.INTENT_EXTRA_TABLET_HEIGHT_RATIO_LANDSCAPE,
          CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_LANDSCAPE);
      hostBackdropSourceDisplayRotation = intent.getIntExtra(
          CardConstants.INTENT_EXTRA_HOST_DISPLAY_ROTATION, Surface.ROTATION_90);

      autoCloseOnPaymentEvent = intent.getBooleanExtra(
          CardConstants.INTENT_EXTRA_AUTO_CLOSE, true);

      // Read modal configuration
      if (useModal) {
        modalAllowDismiss = intent.getBooleanExtra(
            CardConstants.INTENT_EXTRA_MODAL_ALLOW_DISMISS, true);
        modalPhoneWidthRatioPortrait = intent.getFloatExtra(
            CardConstants.INTENT_EXTRA_MODAL_PHONE_WIDTH_RATIO_PORTRAIT,
            CardConstants.DEFAULT_MODAL_PHONE_WIDTH_RATIO_PORTRAIT);
        modalPhoneHeightRatioPortrait = intent.getFloatExtra(
            CardConstants.INTENT_EXTRA_MODAL_PHONE_HEIGHT_RATIO_PORTRAIT,
            CardConstants.DEFAULT_MODAL_PHONE_HEIGHT_RATIO_PORTRAIT);
        modalPhoneWidthRatioLandscape = intent.getFloatExtra(
            CardConstants.INTENT_EXTRA_MODAL_PHONE_WIDTH_RATIO_LANDSCAPE,
            CardConstants.DEFAULT_MODAL_PHONE_WIDTH_RATIO_LANDSCAPE);
        modalPhoneHeightRatioLandscape = intent.getFloatExtra(
            CardConstants.INTENT_EXTRA_MODAL_PHONE_HEIGHT_RATIO_LANDSCAPE,
            CardConstants.DEFAULT_MODAL_PHONE_HEIGHT_RATIO_LANDSCAPE);
        modalTabletWidthRatioPortrait = intent.getFloatExtra(
            CardConstants.INTENT_EXTRA_MODAL_TABLET_WIDTH_RATIO_PORTRAIT,
            CardConstants.DEFAULT_MODAL_TABLET_WIDTH_RATIO_PORTRAIT);
        modalTabletHeightRatioPortrait = intent.getFloatExtra(
            CardConstants.INTENT_EXTRA_MODAL_TABLET_HEIGHT_RATIO_PORTRAIT,
            CardConstants.DEFAULT_MODAL_TABLET_HEIGHT_RATIO_PORTRAIT);
        modalTabletWidthRatioLandscape = intent.getFloatExtra(
            CardConstants.INTENT_EXTRA_MODAL_TABLET_WIDTH_RATIO_LANDSCAPE,
            CardConstants.DEFAULT_MODAL_TABLET_WIDTH_RATIO_LANDSCAPE);
        modalTabletHeightRatioLandscape = intent.getFloatExtra(
            CardConstants.INTENT_EXTRA_MODAL_TABLET_HEIGHT_RATIO_LANDSCAPE,
            CardConstants.DEFAULT_MODAL_TABLET_HEIGHT_RATIO_LANDSCAPE);
      }
      
      if (url == null || url.isEmpty()) {
        finish();
        return;
      }

      hostBackdropBitmap = StashNativeCard.consumeBackdropBitmap();
      
      cachedIsDarkTheme = StashWebViewUtils.isDarkTheme(this);
      try {
        cachedIsTablet = StashWebViewUtils.isTablet(this);
      } catch (Exception e) {
        Log.w(TAG, "Error checking if tablet: " + e.getMessage(), e);
      }

      Integer parsedChrome = StashBackgroundColorUtils.parseSolidColorOrNull(
          intent.getStringExtra(CardConstants.INTENT_EXTRA_BACKGROUND_COLOR));
      chromeColorOverrideActive = parsedChrome != null;
      if (chromeColorOverrideActive) {
        sheetChromeBackgroundArgb = parsedChrome;
        effectiveIsDarkForContent =
            StashBackgroundColorUtils.isDarkBackground(parsedChrome);
      } else {
        sheetChromeBackgroundArgb = cachedIsDarkTheme
            ? Color.parseColor(StashWebViewUtils.COLOR_DARK_BG)
            : Color.WHITE;
        effectiveIsDarkForContent = cachedIsDarkTheme;
      }
      
      try {
        if (useModal) {
          // Modal follows the underlying app rotation rules; no orientation lock.
          setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED);
        } else if (usePopup) {
          // Popup locks to current orientation.
          int currentOrientation = getResources().getConfiguration().orientation;
          if (currentOrientation == Configuration.ORIENTATION_LANDSCAPE) {
            setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE);
          } else {
            setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT);
          }
        } else if (!cachedIsTablet && forcePortraitOnCheckout) {
          // Checkout on phone: force portrait only when enabled
          int currentOrientation = getResources().getConfiguration().orientation;
          if (currentOrientation == Configuration.ORIENTATION_LANDSCAPE) {
            // Defer card creation until onConfigurationChanged delivers portrait metrics so
            // animateSlideUp starts from the correct (portrait) screen dimensions.
            pendingCreateUIAfterRotation = true;
          }
          setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT);
        } else if (!cachedIsTablet && !forcePortraitOnCheckout) {
          // Checkout on phone without force portrait: lock to current orientation
          int currentOrientation = getResources().getConfiguration().orientation;
          if (currentOrientation == Configuration.ORIENTATION_LANDSCAPE) {
            setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE);
          } else {
            setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT);
          }
        }
      } catch (Exception e) {
        Log.w(TAG, "Error setting orientation: " + e.getMessage(), e);
      }
      
      Window window = getWindow();
      if (window != null) {
        try {
          // When a host backdrop is present, start with an opaque window so the
          // compositor never shows the paused host surface during rotation.
          // Without backdrop, stay transparent so the host app shows through.
          window.setBackgroundDrawable(new ColorDrawable(
              hostBackdropBitmap != null ? Color.BLACK : Color.TRANSPARENT));
          
          requestWindowFeature(Window.FEATURE_NO_TITLE);
          window.addFlags(WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED);
          // Edge-to-edge disabled; we apply system bar insets as padding on rootLayout so the
          // bottom sheet and modal sit above nav bars (3-button, gesture, etc.).
          StashWindowCompat.setDecorFitsSystemWindows(window, false);
          if (chromeColorOverrideActive) {
            StashWebViewUtils.applySystemBarAppearanceForSheet(
                window, window.getDecorView(), sheetChromeBackgroundArgb);
          } else {
            StashWebViewUtils.applySystemBarAppearance(
                window, window.getDecorView(), cachedIsDarkTheme);
          }
        } catch (Exception e) {
          Log.w(TAG, "Error configuring window: " + e.getMessage(), e);
        }
      }
      
      if (!pendingCreateUIAfterRotation) {
        createUI();
        registerBackCallbackIfNeeded();
      }
    } catch (Exception e) {
      Log.w(TAG, "Error in onCreate: " + e.getMessage(), e);
      finish();
    }
  }

  private void registerBackCallbackIfNeeded() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
      return;
    }
    onBackInvokedCallback = () -> {
      if (!isPurchaseProcessing) {
        if (awaitingExternalBrowserDimOverlay) {
          finishAfterExternalBrowserClose();
        } else {
          dismissWithAnimation();
        }
      }
    };
    getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
        OnBackInvokedDispatcher.PRIORITY_DEFAULT, onBackInvokedCallback);
  }

  private void createUI() {
    try {
      rootLayout = new FrameLayout(this);
      rootLayout.setBackgroundColor(Color.TRANSPARENT);
      
      // Optional host screenshot backdrop (behind the dim layer)
      if (hostBackdropBitmap != null && !hostBackdropBitmap.isRecycled()) {
        hostBackdropImageView = new ImageView(this);
        hostBackdropImageView.setLayoutParams(new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT));
        hostBackdropImageView.setScaleType(ImageView.ScaleType.MATRIX);
        hostBackdropImageView.setImageBitmap(hostBackdropBitmap);
        // Bitmap buffer is in physical order; avoid RTL mirroring the matrix result.
        hostBackdropImageView.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);

        hostBackdropImageView.post(() -> StashHostBackdropSupport.applyPortraitCheckoutMatrix(
            hostBackdropImageView, hostBackdropBitmap, hostBackdropSourceDisplayRotation));

        rootLayout.addView(hostBackdropImageView);

        // Now that the backdrop image covers the screen, switch window to transparent
        // so dismissal fades cleanly.
        Window w = getWindow();
        if (w != null) {
          w.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        }
      }

      // Create separate backdrop view for independent fade animation (dim layer)
      backdropView = new View(this);
      backdropView.setLayoutParams(new FrameLayout.LayoutParams(
          FrameLayout.LayoutParams.MATCH_PARENT,
          FrameLayout.LayoutParams.MATCH_PARENT));
      try {
        backdropView.setBackgroundColor(Color.parseColor(StashWebViewUtils.COLOR_BACKGROUND_DIM));
      } catch (Exception e) {
        Log.w(TAG, "Error setting background color: " + e.getMessage(), e);
        backdropView.setBackgroundColor(Color.parseColor(CardConstants.COLOR_BACKGROUND_DIM));
      }
      rootLayout.addView(backdropView);
      
      try {
        if (usePopup) {
          createPopup();
        } else if (useModal) {
          createModal();
        } else {
          createCard();
        }
      } catch (Exception e) {
        Log.w(TAG, "Error creating UI: " + e.getMessage(), e);
        finish();
        return;
      }
      
      // Configure backdrop tap to dismiss (for card, tablet, and modal with allowDismiss)
      boolean allowBackdropDismiss = !usePopup && cardContainer != null;
      if (useModal) {
        allowBackdropDismiss = modalAllowDismiss;
      }
      if (allowBackdropDismiss && cardContainer != null) {
        backdropView.setOnClickListener(v -> {
          try {
            if (!isDismissing && !isPurchaseProcessing) {
              dismissWithAnimation();
            }
          } catch (Exception e) {
            Log.w(TAG, "Error in backdrop click handler: " + e.getMessage(), e);
          }
        });
        cardContainer.setOnClickListener(v -> {});
      }
      
      setContentView(rootLayout);
      ViewCompat.setOnApplyWindowInsetsListener(
          rootLayout, (v, insets) -> StashCheckoutImeSupport.onWindowInsets(this, v, insets));
      ViewCompat.requestApplyInsets(rootLayout);
      StashCheckoutImeSupport.registerImeGlobalLayoutListenerIfNeeded(this);
      // Insets (e.g. nav bar height) may not be present until after the first layout pass; re-apply
      // phone sheet sizing so portrait + force-portrait checkout match config, not full display.
      if (!usePopup && !useModal && !cachedIsTablet) {
        rootLayout.post(
            () -> {
              if (cardContainer != null) {
                animatePhoneCheckoutRotation();
              }
            });
      }
    } catch (Exception e) {
      Log.w(TAG, "Error in createUI: " + e.getMessage(), e);
      finish();
    }
  }
  
  private void configureCardContainer(boolean isTablet, int cardWidth, int cardHeight) {
    float radius = StashWebViewUtils.dpToPx(this, (int) CardConstants.CORNER_RADIUS_DP);
    if (isTablet) {
      cardContainer = new FrameLayout(this);
    } else {
      // Phone: canvas clip (TopRoundedFrameLayout); Outline path cannot clip WebView pre-API 33.
      cardContainer = new TopRoundedFrameLayout(this, radius);
    }
    FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(cardWidth, cardHeight);
    params.gravity = isTablet ? Gravity.CENTER : (Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
    cardContainer.setLayoutParams(params);
    
    GradientDrawable bg = new GradientDrawable();
    bg.setColor(sheetChromeBackgroundArgb);
    
    if (isTablet) {
      bg.setCornerRadius(radius);
    } else {
      bg.setCornerRadii(new float[]{radius, radius, radius, radius, 0, 0, 0, 0});
    }
    cardContainer.setBackground(bg);
    
    cardContainer.setElevation(StashWebViewUtils.dpToPx(this, (int) CardConstants.ELEVATION_DP));
    if (isTablet) {
      cardContainer.setOutlineProvider(new ViewOutlineProvider() {
        @Override
        public void getOutline(View view, Outline outline) {
          outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), radius);
        }
      });
      cardContainer.setClipToOutline(true);
    } else {
      // Shadow shape only; child clipping is handled in TopRoundedFrameLayout.dispatchDraw.
      cardContainer.setOutlineProvider(TopRoundedFrameLayout.outlineProviderForElevation(radius));
      cardContainer.setClipToOutline(false);
    }
  }

  private void createCard() {
    DisplayMetrics metrics = getResources().getDisplayMetrics();
    boolean isTablet = cachedIsTablet;

    int cardWidth;
    int cardHeight;
    if (isTablet) {
      int[] cardSize = StashCheckoutSizing.calculateTabletCardSize(this, metrics);
      cardWidth = cardSize[0];
      cardHeight = cardSize[1];
      tabletSdkBaseHeightPx = cardHeight;
      isExpanded = false;
    } else {
      boolean isLandscape = getResources().getConfiguration().orientation
          == Configuration.ORIENTATION_LANDSCAPE;
      // Cap card height so it never extends behind the status bar / notch.
      int maxCardHeight = metrics.heightPixels
          - StashWindowCompat.getSystemTopInsetPx(getWindow());
      if (maxCardHeight <= 0) maxCardHeight = metrics.heightPixels;

      if (isLandscape && !forcePortraitOnCheckout) {
        // Phone checkout in landscape without forcing portrait: use landscape ratios
        int w = (int) (metrics.widthPixels * cardWidthRatioLandscape);
        int h = (int) (metrics.heightPixels * cardHeightRatioLandscape);
        int minPx = (int) StashWebViewUtils.dpToPx(
            this, (int) CardConstants.MIN_PHONE_CARD_WIDTH_DP);
        if (w < minPx) {
          w = minPx;
        }
        if (h < minPx) {
          h = minPx;
        }
        cardWidth = w;
        cardHeight = Math.min(h, maxCardHeight);
        // Landscape phone card is fixed to configured size (dismiss-only gesture behavior).
        isExpanded = false;
      } else {
        isExpanded = false;
        cardHeight = StashCheckoutSizing.computePhonePortraitSheetHeightPx(this, metrics);
        cardWidth = FrameLayout.LayoutParams.MATCH_PARENT;
      }
    }
    
    configureCardContainer(isTablet, cardWidth, cardHeight);
    
    if (!isTablet && !usePopup && !useModal) {
      collapsedCardTargetHeightPx = StashCheckoutSizing.computeCollapsedPhoneCardHeight(this, metrics);
    }
    
    StashCheckoutWebViewSupport.addWebView(this);
    addDragHandle();
    addHomeButton();
    rootLayout.addView(cardContainer);
    
    if (isTablet) {
      animateFadeIn();
    } else {
      animateSlideUp();
    }
  }
  
  private void createPopup() {
    DisplayMetrics metrics = getResources().getDisplayMetrics();
    int size = (int) (Math.min(metrics.widthPixels, metrics.heightPixels) * 0.75f);
    
    configureCardContainer(true, size, size);
    
    StashCheckoutWebViewSupport.addWebView(this);
    rootLayout.addView(cardContainer);
    animateFadeIn();
  }
  
  private void createModal() {
    DisplayMetrics metrics = getResources().getDisplayMetrics();
    int[] cardSize = StashCheckoutSizing.calculateModalCardSize(this, metrics);
    int cardWidth = cardSize[0];
    int cardHeight = cardSize[1];
    
    // Modal is always centered (like tablet mode)
    configureCardContainer(true, cardWidth, cardHeight);
    
    StashCheckoutWebViewSupport.addWebView(this);
    addHomeButton();
    rootLayout.addView(cardContainer);
    
    // Same as tablet checkout: backdrop visible; card fades in while WebView loads underneath.
    animateFadeIn();
    
    // Modal is always considered expanded
    isExpanded = true;
  }

  private void addDragHandle() {
    LinearLayout dragArea = new LinearLayout(this);
    dragArea.setOrientation(LinearLayout.VERTICAL);
    dragArea.setGravity(Gravity.CENTER_HORIZONTAL);
    int padH = StashWebViewUtils.dpToPx(this, 20);
    int padTop = StashWebViewUtils.dpToPx(this, Math.round(CardConstants.DRAG_HANDLE_TOP_INSET_DP));
    int padBottom =
        StashWebViewUtils.dpToPx(this, Math.round(CardConstants.DRAG_TRAY_PADDING_BOTTOM_DP));
    dragArea.setPadding(padH, padTop, padH, padBottom);

    View handle = new View(this);
    GradientDrawable handleBg = new GradientDrawable();
    handleBg.setColor(StashBackgroundColorUtils.dragHandleFor(sheetChromeBackgroundArgb));
    handleBg.setCornerRadius(
        StashWebViewUtils.dpToPx(this, Math.round(CardConstants.DRAG_HANDLE_CORNER_RADIUS_DP)));
    handle.setBackground(handleBg);
    handle.setLayoutParams(new LinearLayout.LayoutParams(
        StashWebViewUtils.dpToPx(this, (int) CardConstants.DRAG_HANDLE_WIDTH_DP),
        StashWebViewUtils.dpToPx(this, (int) CardConstants.DRAG_HANDLE_HEIGHT_DP)));
    dragArea.addView(handle);

    FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
        StashWebViewUtils.dpToPx(this, 120), FrameLayout.LayoutParams.WRAP_CONTENT);
    params.gravity = Gravity.TOP | Gravity.CENTER_HORIZONTAL;
    dragArea.setLayoutParams(params);
    
    dragArea.setElevation(StashWebViewUtils.dpToPx(this, 8));
    
    addDragTouchHandling(dragArea);
    dragHandleArea = dragArea;
    cardContainer.addView(dragArea);
  }

  /** Fades the drag strip out during purchase processing (dismiss is blocked) or back in. */
  void applyDragHandlePurchaseProcessingFade(boolean hide) {
    if (dragHandleArea == null) {
      return;
    }
    dragHandleArea.animate().cancel();
    dragHandleArea.animate()
        .alpha(hide ? 0f : 1f)
        .setDuration(CardConstants.OVERLAY_FADE_IN_DURATION_MS)
        .setInterpolator(new android.view.animation.AccelerateDecelerateInterpolator())
        .start();
    dragHandleArea.setEnabled(!hide);
  }
  
  /**
  * Touch listener for drag handle with velocity-based gesture recognition.
  * Uses CardConstants for consistent threshold values.
  */
  private class DragHandleTouchListener implements View.OnTouchListener {
    private float initialY;
    private float initialTranslationY;
    private boolean isDragging;
    private long lastMoveTime;
    private float lastMoveY;
    private float velocity;
    /** Cached for the current touch sequence to avoid repeated getDisplayMetrics() calls. */
    private DisplayMetrics displayMetrics;
    
    /** Applies drag-down feedback: translation and alpha fade. Shared by tablet and phone. */
    private void applyDragDownFeedback(float deltaY) {
      if (displayMetrics == null) {
        return;
      }
      float newTranslationY = initialTranslationY + deltaY;
      cardContainer.setTranslationY(newTranslationY);
      float progress = Math.min(deltaY / displayMetrics.heightPixels, 1.0f);
      cardContainer.setAlpha(1.0f - (progress * CardConstants.ALPHA_FADE_MULTIPLIER));
    }
    
    @Override
    public boolean onTouch(View v, MotionEvent event) {
      if (cardContainer == null) {
        return false;
      }
      
      if (isPurchaseProcessing) {
        return false;
      }
      
      // Modal mode never supports drag gestures (only visual drag bar)
      if (useModal) {
        return false;
      }
      
      boolean isTablet = cachedIsTablet;
      boolean isLandscape = isLandscapeMode();
      
      switch (event.getAction()) {
        case MotionEvent.ACTION_DOWN:
          initialY = event.getRawY();
          initialTranslationY = cardContainer.getTranslationY();
          isDragging = false;
          lastMoveTime = System.currentTimeMillis();
          lastMoveY = event.getRawY();
          velocity = 0;
          displayMetrics = getResources().getDisplayMetrics();
          return true;
        
        case MotionEvent.ACTION_MOVE:
          // Calculate velocity
          long currentTime = System.currentTimeMillis();
          float timeDelta = (currentTime - lastMoveTime) / 1000f;
          if (timeDelta > 0) {
            velocity = (event.getRawY() - lastMoveY) / timeDelta;
          }
          lastMoveTime = currentTime;
          lastMoveY = event.getRawY();
          float deltaY = event.getRawY() - initialY;

          if (Math.abs(deltaY) > StashWebViewUtils.dpToPx(StashNativeCardPortraitActivity.this, 10)) {
            // Landscape phone behaves like a fixed-size sheet: dismiss-only drag (downward).
            // Tablet and modal are also dismiss-only.
            isDragging = (isTablet || useModal || isLandscape) ? (deltaY > 0) : true;
            
            if (deltaY > 0) {
              // Drag down: same feedback for tablet, modal, and phone
              applyDragDownFeedback(deltaY);
            } else if (!isTablet && !useModal && !isExpanded && !isLandscape) {
              // Phone only (not modal, not landscape): drag up to expand
              float cardHeight = cardContainer.getHeight();
              float expandThreshold = cardHeight * CardConstants.EXPAND_DISTANCE_THRESHOLD;
              float dragProgress = Math.min(Math.abs(deltaY) / expandThreshold, 1.0f);
              cardContainer.setScaleX(1.0f + (dragProgress * 0.02f));
              cardContainer.setScaleY(1.0f + (dragProgress * 0.02f));
            }
          }
          return true;
        
        case MotionEvent.ACTION_UP:
        case MotionEvent.ACTION_CANCEL:
          if (isDragging) {
            float finalDeltaY = event.getRawY() - initialY;
            DisplayMetrics metrics = displayMetrics != null
                ? displayMetrics
                : getResources().getDisplayMetrics();
            float cardHeight = cardContainer.getHeight();
            
            if (isTablet || useModal) {
              // Tablet or Modal: Dismiss only (no expand/collapse)
              if (finalDeltaY > 0) {
                float dismissThreshold =
                    metrics.heightPixels * CardConstants.DISMISS_DISTANCE_THRESHOLD_TABLET;
                if (finalDeltaY > dismissThreshold
                    || velocity > CardConstants.DISMISS_VELOCITY_THRESHOLD_TABLET) {
                  animateTabletDismiss();
                } else {
                  animateSnapBack();
                }
              } else {
                animateSnapBack();
              }
            } else {
              // Phone: landscape is dismiss-only; portrait keeps expand/collapse behavior.
              if (isLandscape) {
                if (finalDeltaY > 0) {
                  float dismissThreshold =
                      metrics.heightPixels * CardConstants.DISMISS_DISTANCE_THRESHOLD_PHONE;
                  if (finalDeltaY > dismissThreshold
                      || velocity > CardConstants.DISMISS_VELOCITY_THRESHOLD) {
                    animateDismiss();
                  } else {
                    animateSnapBack();
                  }
                } else {
                  cardContainer.setScaleX(1.0f);
                  cardContainer.setScaleY(1.0f);
                  animateSnapBack();
                }
              } else {
                // Portrait phone: three-state system with velocity.
                if (finalDeltaY > 0) {
                  // Drag down
                  float dismissThreshold =
                      metrics.heightPixels * CardConstants.DISMISS_DISTANCE_THRESHOLD_PHONE;
                  float collapseThreshold =
                      cardHeight * CardConstants.COLLAPSE_DISTANCE_THRESHOLD;
                  
                  if (isExpanded) {
                    // From expanded: collapse or dismiss
                    if (finalDeltaY > dismissThreshold
                        && velocity > CardConstants.DISMISS_VELOCITY_THRESHOLD) {
                      animateDismiss();
                    } else if (finalDeltaY > collapseThreshold
                        || velocity > CardConstants.COLLAPSE_VELOCITY_THRESHOLD) {
                      animateCollapse();
                    } else {
                      animateSnapBack();
                    }
                  } else {
                    // From collapsed: dismiss
                    if (finalDeltaY > dismissThreshold
                        || velocity > CardConstants.DISMISS_VELOCITY_THRESHOLD) {
                      animateDismiss();
                    } else {
                      animateSnapBack();
                    }
                  }
                } else if (finalDeltaY < 0 && !isExpanded) {
                  // Drag up: expand (portrait phone only)
                  float expandThreshold =
                      cardHeight * CardConstants.EXPAND_DISTANCE_THRESHOLD;
                  if (Math.abs(finalDeltaY) > expandThreshold
                      || velocity < CardConstants.EXPAND_VELOCITY_THRESHOLD) {
                    animateExpand();
                  } else {
                    cardContainer.setScaleX(1.0f);
                    cardContainer.setScaleY(1.0f);
                    animateSnapBack();
                  }
                } else {
                  cardContainer.setScaleX(1.0f);
                  cardContainer.setScaleY(1.0f);
                  animateSnapBack();
                }
              }
            }
          }
          return true;
        default:
          return false;
      }
    }
  }

  private void addDragTouchHandling(View dragArea) {
    dragArea.setOnTouchListener(new DragHandleTouchListener());
  }
  
  private void animateDismiss() {
    if (cardContainer == null) {
      return;
    }
    if (isPurchaseProcessing) {
      return;
    }
    int height = cardContainer.getHeight();
    if (height == 0) {
      height = (int) (getResources().getDisplayMetrics().heightPixels * cardHeightRatioPortrait);
    }
    
    // Fade out the backdrop independently
    if (backdropView != null) {
      backdropView.animate()
          .alpha(0f)
          .setDuration(CardConstants.ANIMATION_DURATION_DISMISS)
          .setInterpolator(new android.view.animation.AccelerateInterpolator())
          .start();
    }
    
    cardContainer.animate()
        .translationY(height)
        .setDuration(CardConstants.ANIMATION_DURATION_ENTRY)
        .setInterpolator(new android.view.animation.AccelerateInterpolator())
        .withEndAction(this::finish)
        .start();
  }
  
  private void animateTabletDismiss() {
    if (cardContainer == null) {
      return;
    }
    if (isPurchaseProcessing) {
      return;
    }
    
    isDismissing = true;
    
    // Fade out the backdrop
    if (backdropView != null) {
      backdropView.animate()
          .alpha(0f)
          .setDuration(CardConstants.ANIMATION_DURATION_POPUP)
          .setInterpolator(new android.view.animation.AccelerateInterpolator())
          .start();
    }
    
    // Scale down and fade out the card for a seamless tablet dismiss
    cardContainer.animate()
        .alpha(0f)
        .scaleX(0.9f)
        .scaleY(0.9f)
        .setDuration(CardConstants.ANIMATION_DURATION_POPUP)
        .setInterpolator(new android.view.animation.AccelerateInterpolator())
        .withEndAction(this::finishActivityWithNoAnimation)
        .start();
  }

  private void animateCardHeight(int targetHeight, int duration) {
    if (cardContainer == null) {
      return;
    }
    if (cardHeightAnimator != null) {
      cardHeightAnimator.cancel();
      cardHeightAnimator = null;
    }
    FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
    if (params == null) {
      return;
    }
    int startHeight = params.height;
    if (startHeight <= 0) {
      startHeight = cardContainer.getHeight();
    }
    if (startHeight <= 0) {
      params.height = targetHeight;
      cardContainer.setLayoutParams(params);
      return;
    }
    if (startHeight == targetHeight) {
      return;
    }
    final int endHeight = targetHeight;
    cardHeightAnimator = ValueAnimator.ofInt(startHeight, endHeight);
    cardHeightAnimator.setDuration(duration);
    cardHeightAnimator.setInterpolator(new SpringInterpolator());
    cardHeightAnimator.addUpdateListener(animation -> {
      if (cardContainer == null) {
        return;
      }
      FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
      if (p == null) {
        return;
      }
      p.height = (Integer) animation.getAnimatedValue();
      cardContainer.setLayoutParams(p);
    });
    cardHeightAnimator.addListener(new AnimatorListenerAdapter() {
      @Override
      public void onAnimationEnd(Animator animation) {
        if (cardHeightAnimator == animation) {
          cardHeightAnimator = null;
        }
        if (cardContainer == null) {
          return;
        }
        FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
        if (p != null) {
          p.height = endHeight;
          cardContainer.setLayoutParams(p);
        }
      }
    });
    cardHeightAnimator.start();
  }

  void animateExpand() {
    if (cardContainer == null) {
      return;
    }

    DisplayMetrics metrics = getResources().getDisplayMetrics();
    FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
    if (params == null) {
      return;
    }

    boolean isTablet = cachedIsTablet;
    if (isTablet) {
      if (isExpanded) {
        return;
      }
      int base =
          tabletSdkBaseHeightPx > 0
              ? tabletSdkBaseHeightPx
              : (params.height > 0 ? params.height : cardContainer.getHeight());
      if (base <= 0) {
        return;
      }
      int maxH = (int) (metrics.heightPixels * CardConstants.EXPANDED_CARD_HEIGHT_RATIO);
      int target =
          Math.min(
              Math.round(base * CardConstants.TABLET_SDK_EXPAND_HEIGHT_MULTIPLIER), maxH);
      if (target <= base) {
        return;
      }
      animateCardHeight(target, 450);
      cardContainer
          .animate()
          .translationY(0)
          .alpha(1f)
          .scaleX(1f)
          .scaleY(1f)
          .setDuration(CardConstants.ANIMATION_DURATION_SNAP_BACK)
          .setInterpolator(new SpringInterpolator())
          .start();
      isExpanded = true;
      return;
    }

    if (params.height > 0) {
      collapsedCardTargetHeightPx = params.height;
    }

    int expandedHeight = (int) (metrics.heightPixels * CardConstants.EXPANDED_CARD_HEIGHT_RATIO);

    animateCardHeight(expandedHeight, 450);

    cardContainer
        .animate()
        .translationY(0)
        .alpha(1f)
        .scaleX(1f)
        .scaleY(1f)
        .setDuration(CardConstants.ANIMATION_DURATION_SNAP_BACK)
        .setInterpolator(new SpringInterpolator())
        .start();

    isExpanded = true;
  }
  
  void animateCollapse() {
    if (cardContainer == null || !isExpanded) {
      return;
    }

    boolean isTablet = cachedIsTablet;
    if (isTablet) {
      DisplayMetrics metrics = getResources().getDisplayMetrics();
      int collapsedHeight = tabletSdkBaseHeightPx;
      if (collapsedHeight <= 0) {
        collapsedHeight = StashCheckoutSizing.calculateTabletCardSize(this, metrics)[1];
        tabletSdkBaseHeightPx = collapsedHeight;
      }
      FrameLayout.LayoutParams layoutParams =
          (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
      if (layoutParams == null) {
        return;
      }
      int startHeight = layoutParams.height;
      if (startHeight <= 0) {
        startHeight = cardContainer.getHeight();
      }
      if (startHeight <= 0) {
        return;
      }
      if (startHeight == collapsedHeight
          && Math.abs(cardContainer.getTranslationY()) < 0.5f
          && cardContainer.getAlpha() >= 0.99f) {
        isExpanded = false;
        return;
      }
      cardContainer.animate().cancel();
      if (cardHeightAnimator != null) {
        cardHeightAnimator.cancel();
        cardHeightAnimator = null;
      }
      cardContainer.setScaleX(1f);
      cardContainer.setScaleY(1f);
      isExpanded = false;
      animateCardHeight(collapsedHeight, CardConstants.ANIMATION_DURATION_COLLAPSE);
      return;
    }

    DisplayMetrics metrics = getResources().getDisplayMetrics();

    int collapsedHeight = collapsedCardTargetHeightPx > 0
        ? collapsedCardTargetHeightPx
        : StashCheckoutSizing.computeCollapsedPhoneCardHeight(this, metrics);

    // Capture drag feedback before cancelling (release position). One ValueAnimator updates height,
    // translationY, and alpha each frame so we do not desync two animators (wrong perceived height)
    // or snap TY to 0 first (jump back to expanded).
    float startTranslationY = cardContainer.getTranslationY();
    float startAlpha = cardContainer.getAlpha();
    FrameLayout.LayoutParams layoutParams =
        (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
    if (layoutParams == null) {
      return;
    }
    int startHeight = layoutParams.height;
    if (startHeight <= 0) {
      startHeight = cardContainer.getHeight();
    }
    if (startHeight <= 0) {
      return;
    }
    final int endHeight = collapsedHeight;
    if (startHeight == endHeight
        && Math.abs(startTranslationY) < 0.5f
        && startAlpha >= 0.99f) {
      isExpanded = false;
      return;
    }

    cardContainer.animate().cancel();
    if (cardHeightAnimator != null) {
      cardHeightAnimator.cancel();
      cardHeightAnimator = null;
    }
    cardContainer.setScaleX(1f);
    cardContainer.setScaleY(1f);

    final int startH = startHeight;
    cardHeightAnimator = ValueAnimator.ofFloat(0f, 1f);
    cardHeightAnimator.setDuration(CardConstants.ANIMATION_DURATION_COLLAPSE);
    cardHeightAnimator.setInterpolator(new SpringInterpolator());
    cardHeightAnimator.addUpdateListener(animation -> {
      if (cardContainer == null) {
        return;
      }
      float t = (Float) animation.getAnimatedValue();
      int h = Math.round(startH + (endHeight - startH) * t);
      FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
      if (p != null) {
        p.height = h;
        cardContainer.setLayoutParams(p);
      }
      cardContainer.setTranslationY(startTranslationY * (1f - t));
      cardContainer.setAlpha(startAlpha + (1f - startAlpha) * t);
    });
    cardHeightAnimator.addListener(new AnimatorListenerAdapter() {
      @Override
      public void onAnimationEnd(Animator animation) {
        if (cardHeightAnimator == animation) {
          cardHeightAnimator = null;
        }
        if (cardContainer == null) {
          return;
        }
        FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
        if (p != null) {
          p.height = endHeight;
          cardContainer.setLayoutParams(p);
        }
        cardContainer.setTranslationY(0f);
        cardContainer.setAlpha(1f);
      }

      @Override
      public void onAnimationCancel(Animator animation) {
        if (cardHeightAnimator == animation) {
          cardHeightAnimator = null;
        }
      }
    });
    cardHeightAnimator.start();

    isExpanded = false;
  }
  
  private void animateSnapBack() {
    if (cardContainer == null) {
      return;
    }
    DisplayMetrics metrics = getResources().getDisplayMetrics();
    boolean isTablet = cachedIsTablet;
    
    FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
    int targetHeight;
    if (isTablet) {
      // Tablet: single fixed size - keep current height, only reset translation/alpha/scale
      targetHeight = params.height;
    } else if (isExpanded) {
      targetHeight = (int) (metrics.heightPixels * CardConstants.EXPANDED_CARD_HEIGHT_RATIO);
    } else {
      targetHeight = collapsedCardTargetHeightPx > 0
          ? collapsedCardTargetHeightPx
          : StashCheckoutSizing.computeCollapsedPhoneCardHeight(this, metrics);
    }
    
    if (params.height != targetHeight) {
      animateCardHeight(targetHeight, CardConstants.ANIMATION_DURATION_SNAP_BACK);
    }
    
    cardContainer.animate()
        .translationY(0)
        .alpha(1f)
        .scaleX(1f)
        .scaleY(1f)
        .setDuration(CardConstants.ANIMATION_DURATION_SNAP_BACK)
        .setInterpolator(new SpringInterpolator())
        .start();
  }

  private void removePendingLandscapeFinishCallback() {
    if (loadTimersHandler != null) {
      loadTimersHandler.removeCallbacks(pendingLandscapeFinishFallback);
    }
  }

  /** Phone force-portrait checkout with host backdrop: hold static plate through return rotation. */
  private boolean shouldDeferFinishForHostBackdrop() {
    return hostBackdropImageView != null
        && forcePortraitOnCheckout
        && !cachedIsTablet
        && !usePopup
        && !useModal;
  }

  /** Called when landscape is ready or fallback timer fires; idempotent if already completed. */
  private void completeDeferredFinishFromLandscape() {
    if (!pendingFinishAfterLandscape) {
      return;
    }
    StashHostBackdropSupport.prepareForLandscapeDisplay(hostBackdropImageView);
    pendingFinishAfterLandscape = false;
    removePendingLandscapeFinishCallback();
    finishActivityWithNoAnimation();
  }

  private void beginFinishAfterLandscapeTransition() {
    pendingFinishAfterLandscape = true;
    if (loadTimersHandler == null) {
      loadTimersHandler = new android.os.Handler(android.os.Looper.getMainLooper());
    }
    removePendingLandscapeFinishCallback();
    loadTimersHandler.postDelayed(
        pendingLandscapeFinishFallback, CardConstants.LANDSCAPE_FINISH_FALLBACK_MS);
    try {
      setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
    } catch (Exception e) {
      Log.w(TAG, "Error requesting landscape for dismiss: " + e.getMessage(), e);
    }
    if (getResources().getConfiguration().orientation == Configuration.ORIENTATION_LANDSCAPE) {
      if (hostBackdropImageView != null) {
        hostBackdropImageView.post(this::completeDeferredFinishFromLandscape);
      } else {
        completeDeferredFinishFromLandscape();
      }
    }
  }

  private void finishAfterDismissAnimations() {
    if (shouldDeferFinishForHostBackdrop()) {
      beginFinishAfterLandscapeTransition();
    } else {
      finishActivityWithNoAnimation();
    }
  }
  
  void handleNetworkError() {
    if (networkErrorHandled || isDismissing) {
      return;
    }
    networkErrorHandled = true;
    
    StashCheckoutWebViewSupport.cancelLoadTimers(this);
    
    StashCheckoutBridge.emitNetworkError(this);
    
    // Dismiss immediately without callback for dialog dismissed
    callbackSent = true;  // Prevent onDialogDismissed from being called
    finishActivityWithNoAnimation();
  }
  
  private void addHomeButton() {
    homeButton = new Button(this);
    homeButton.setText("⌂");
    homeButton.setTextSize(18);
    homeButton.setTextColor(Color.parseColor(CardConstants.COLOR_HOME_TEXT));
    homeButton.setGravity(Gravity.CENTER);
    homeButton.setPadding(0, 0, 0, 0);
    
    GradientDrawable bg = new GradientDrawable();
    bg.setColor(effectiveIsDarkForContent
        ? Color.parseColor(CardConstants.COLOR_HOME_BUTTON_DARK_BG)
        : Color.parseColor(CardConstants.COLOR_LIGHT_BG));
    bg.setCornerRadius(StashWebViewUtils.dpToPx(this, 20));
    int strokeColor = effectiveIsDarkForContent
        ? Color.parseColor(CardConstants.COLOR_DARK_STROKE)
        : Color.parseColor(CardConstants.COLOR_LIGHT_STROKE);
    bg.setStroke(StashWebViewUtils.dpToPx(this, 1), strokeColor);
    homeButton.setBackground(bg);
    
    homeButton.setElevation(StashWebViewUtils.dpToPx(this, 6));
    
    int btnSize = StashWebViewUtils.dpToPx(this, 36);
    int margin = StashWebViewUtils.dpToPx(this, 12);
    FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(btnSize, btnSize);
    params.gravity = Gravity.TOP | Gravity.START;
    params.setMargins(margin, margin, 0, 0);
    homeButton.setLayoutParams(params);
    homeButton.setVisibility(View.GONE);
    homeButton.setOnClickListener(v -> {
      if (initialURL != null && webView != null) {
        String urlWithTheme =
            StashWebViewUtils.appendThemeQueryParameter(initialURL, effectiveIsDarkForContent);
        webView.loadUrl(urlWithTheme);
      }
    });
    
    cardContainer.addView(homeButton);
  }
  
  private void animateSlideUp() {
    DisplayMetrics metrics = getResources().getDisplayMetrics();
    cardContainer.setTranslationY(metrics.heightPixels);

    // Match iOS: fade dim first, brief hold, then sheet slide (extra time for WebView load).
    if (backdropView != null) {
      backdropView.setAlpha(0f);
      backdropView.animate()
          .alpha(1f)
          .setDuration(CardConstants.OVERLAY_FADE_IN_DURATION_MS)
          .setInterpolator(new android.view.animation.AccelerateDecelerateInterpolator())
          .start();
    }
    final long slideDelay = CardConstants.OVERLAY_FADE_IN_DURATION_MS
        + CardConstants.CARD_ENTRY_HOLD_AFTER_OVERLAY_FADE_MS;

    cardContainer.post(() -> {
      if (cardContainer == null) {
        return;
      }
      cardContainer.animate()
          .setStartDelay(slideDelay)
          .translationY(0)
          .setDuration(CardConstants.ANIMATION_DURATION_ENTRY)
          .setInterpolator(new android.view.animation.DecelerateInterpolator())
          .start();
    });
  }
  
  private void animateFadeIn() {
    cardContainer.setAlpha(0f);
    cardContainer.setScaleX(0.9f);
    cardContainer.setScaleY(0.9f);
    cardContainer.animate()
        .alpha(1f)
        .scaleX(1f)
        .scaleY(1f)
        .setDuration(200)
        .setInterpolator(new android.view.animation.AccelerateDecelerateInterpolator())
        .start();
  }

  /**
   * Hides the checkout sheet while keeping the dim (and host snapshot) overlay until {@link
   * #finishAfterExternalBrowserClose()} runs after the browser closes.
   */
  void hideCardSheetLeavingDimOverlay() {
    try {
      if (isDismissing || awaitingExternalBrowserDimOverlay || cardContainer == null) {
        return;
      }
      awaitingExternalBrowserDimOverlay = true;
      if (backdropView != null) {
        backdropView.setOnClickListener(null);
      }
      if (webView != null) {
        try {
          webView.onPause();
        } catch (Exception e) {
          Log.d(TAG, "webView.onPause: " + e.getMessage(), e);
        }
      }

      boolean isTablet = cachedIsTablet;
      if (usePopup || useModal || isTablet) {
        cardContainer
            .animate()
            .alpha(0f)
            .scaleX(0.9f)
            .scaleY(0.9f)
            .setDuration(CardConstants.ANIMATION_DURATION_POPUP)
            .setInterpolator(new android.view.animation.AccelerateInterpolator())
            .withEndAction(
                () -> {
                  if (cardContainer != null) {
                    cardContainer.setVisibility(View.GONE);
                  }
                })
            .start();
      } else {
        int height = cardContainer.getHeight();
        if (height == 0) {
          height =
              (int)
                  (getResources().getDisplayMetrics().heightPixels * cardHeightRatioPortrait);
        }
        cardContainer
            .animate()
            .translationY(height)
            .setDuration(CardConstants.ANIMATION_DURATION_ENTRY)
            .setInterpolator(new android.view.animation.AccelerateInterpolator())
            .withEndAction(
                () -> {
                  if (cardContainer != null) {
                    cardContainer.setVisibility(View.GONE);
                  }
                })
            .start();
      }
    } catch (Exception e) {
      Log.w(TAG, "Error hiding sheet for external browser: " + e.getMessage(), e);
      awaitingExternalBrowserDimOverlay = false;
    }
  }

  /**
   * Fades the dim overlay and finishes after external browser flow, or runs a normal dismiss if the
   * sheet was not hidden first.
   */
  void finishAfterExternalBrowserClose() {
    try {
      if (isDismissing) {
        return;
      }
      if (!awaitingExternalBrowserDimOverlay) {
        dismissWithAnimation();
        return;
      }
      StashNativeCardPlugin.getInstance().abandonPendingExternalBrowserCheckoutDismiss();
      awaitingExternalBrowserDimOverlay = false;
      isDismissing = true;
      try {
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LOCKED);
      } catch (Exception e) {
        Log.w(TAG, "Error locking orientation: " + e.getMessage(), e);
      }

      Runnable end =
          () -> {
            try {
              finishAfterDismissAnimations();
            } catch (Exception e) {
              Log.w(TAG, "Error finishing after external browser overlay: " + e.getMessage(), e);
              finish();
            }
          };

      if (backdropView != null) {
        backdropView
            .animate()
            .alpha(0f)
            .setDuration(CardConstants.ANIMATION_DURATION_ENTRY)
            .setInterpolator(new android.view.animation.AccelerateInterpolator())
            .withEndAction(end)
            .start();
      } else {
        end.run();
      }
      if (hostBackdropImageView != null && !shouldDeferFinishForHostBackdrop()) {
        hostBackdropImageView
            .animate()
            .alpha(0f)
            .setDuration(CardConstants.ANIMATION_DURATION_ENTRY)
            .setInterpolator(new android.view.animation.AccelerateInterpolator())
            .start();
      }
    } catch (Exception e) {
      Log.w(TAG, "Error in finishAfterExternalBrowserClose: " + e.getMessage(), e);
      try {
        finish();
      } catch (Exception e2) {
        Log.w(TAG, "Error finishing activity: " + e2.getMessage(), e2);
      }
    }
  }

  void dismissWithAnimation() {
    if (isDismissing) {
      return;
    }
    isDismissing = true;
    
    try {
      try {
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LOCKED);
      } catch (Exception e) {
        Log.w(TAG, "Error locking orientation: " + e.getMessage(), e);
      }
      
      if (cardContainer == null) {
        finishAfterDismissAnimations();
        return;
      }
      
      // Fade dim only; host backdrop stays opaque until landscape (see shouldDeferFinishForHostBackdrop).
      if (backdropView != null) {
        backdropView.animate()
            .alpha(0f)
            .setDuration(CardConstants.ANIMATION_DURATION_ENTRY)
            .setInterpolator(new android.view.animation.AccelerateInterpolator())
            .start();
      }
      if (hostBackdropImageView != null && !shouldDeferFinishForHostBackdrop()) {
        hostBackdropImageView.animate()
            .alpha(0f)
            .setDuration(CardConstants.ANIMATION_DURATION_ENTRY)
            .setInterpolator(new android.view.animation.AccelerateInterpolator())
            .start();
      }
      
      boolean isTablet = cachedIsTablet;
      
      if (usePopup || useModal || isTablet) {
        // Use fade animation for popups, modals, and tablets
        try {
          cardContainer.animate()
              .alpha(0f)
              .scaleX(0.9f)
              .scaleY(0.9f)
              .setDuration(CardConstants.ANIMATION_DURATION_POPUP)
              .setInterpolator(new android.view.animation.AccelerateInterpolator())
              .withEndAction(() -> {
                try {
                  finishAfterDismissAnimations();
                } catch (Exception e) {
                  Log.w(TAG, "Error in animation end action: " + e.getMessage(), e);
                  finish();
                }
              })
              .start();
        } catch (Exception e) {
          Log.w(TAG, "Error animating popup dismissal: " + e.getMessage(), e);
          finishAfterDismissAnimations();
        }
      } else {
        // Use slide animation for phones
        try {
          cardContainer.animate()
              .translationY(cardContainer.getHeight())
              .setDuration(CardConstants.ANIMATION_DURATION_ENTRY)
              .setInterpolator(new android.view.animation.AccelerateInterpolator())
              .withEndAction(() -> {
                try {
                  finishAfterDismissAnimations();
                } catch (Exception e) {
                  Log.w(TAG, "Error in animation end action: " + e.getMessage(), e);
                  finish();
                }
              })
              .start();
        } catch (Exception e) {
          Log.w(TAG, "Error animating card dismissal: " + e.getMessage(), e);
          finishAfterDismissAnimations();
        }
      }
    } catch (Exception e) {
      Log.w(TAG, "Error in dismissWithAnimation: " + e.getMessage(), e);
      try {
        finish();
      } catch (Exception e2) {
        Log.w(TAG, "Error finishing activity: " + e2.getMessage(), e2);
      }
    }
  }
  
  private void finishActivityWithNoAnimation() {
    if (backdropView != null) {
      backdropView.setVisibility(View.INVISIBLE);
    }
    if (cardContainer != null) {
      cardContainer.setVisibility(View.INVISIBLE);
    }
    
    overridePendingTransition(0, 0);
    finish();
  }
  
  void notifyListenerAndDismiss(String messageType, String messageBody, boolean success) {
    try {
      runOnUiThread(() -> {
        try {
          if (success) {
            // Always re-enable interaction so the user can dismiss the card after the result.
            isPurchaseProcessing = false;
            // Only latch callbackSent (which suppresses the onDestroy dismiss callback) when the
            // card actually auto-closes as part of this payment event. With autoClose = false the
            // card stays open and the later, user-initiated close must still emit onDialogDismissed.
            if (autoCloseOnPaymentEvent) {
              callbackSent = true;
            }
          }
          
          boolean isPaymentEvent =
              CardConstants.MESSAGE_TYPE_SUCCESS.equals(messageType)
                  || CardConstants.MESSAGE_TYPE_FAILURE.equals(messageType);

          switch (messageType) {
            case CardConstants.MESSAGE_TYPE_SUCCESS:
              StashCheckoutBridge.emitPaymentSuccess(
                  StashNativeCardPortraitActivity.this,
                  messageBody != null && !messageBody.isEmpty() ? messageBody : null);
              break;
            case CardConstants.MESSAGE_TYPE_FAILURE:
              StashCheckoutBridge.emitPaymentFailure(StashNativeCardPortraitActivity.this);
              break;
            case CardConstants.MESSAGE_TYPE_OPTIN:
              StashCheckoutBridge.emitOptIn(StashNativeCardPortraitActivity.this, messageBody);
              break;
            default:
              break;
          }

          if (!isPaymentEvent || autoCloseOnPaymentEvent) {
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

  /**
   * Returns true when the card is currently displaying in landscape orientation.
   * In landscape the card is fixed to its configured size; expand/collapse gestures and
   * JS API calls have no effect.
   */
  boolean isLandscapeMode() {
    return getResources().getConfiguration().orientation == Configuration.ORIENTATION_LANDSCAPE;
  }

  @Override
  protected void onPause() {
    super.onPause();
    if (webView != null) {
      webView.onPause();
    }
  }

  @Override
  protected void onResume() {
    super.onResume();
    StashNativeCardPlugin.getInstance().stopKeepAliveForegroundService(getApplicationContext());
    if (webView != null) {
      webView.onResume();
    }
  }

  @Override
  protected void onDestroy() {
    try {
      super.onDestroy();
      StashCheckoutWebViewSupport.cancelLoadTimers(this);

      if (imeGlobalLayoutListener != null && rootLayout != null) {
        try {
          rootLayout.getViewTreeObserver().removeOnGlobalLayoutListener(imeGlobalLayoutListener);
        } catch (Throwable ignored) {
        }
        imeGlobalLayoutListener = null;
      }

      if (webView != null) {
        try {
          if (webView.getParent() != null) {
            ((ViewGroup) webView.getParent()).removeView(webView);
          }
          webView.stopLoading();
          webView.setWebChromeClient(null);
          webView.setWebViewClient(null);
          webView.removeJavascriptInterface(StashWebViewUtils.JS_INTERFACE_NAME);
          webView.destroy();
        } catch (Exception e) {
          Log.w(TAG, "Error destroying WebView: " + e.getMessage(), e);
        }
        webView = null;
      }
      cardContainer = null;
      rootLayout = null;
      backdropView = null;
      loadingView = null;
      homeButton = null;
      hostBackdropImageView = null;
      if (hostBackdropBitmap != null) {
        if (!hostBackdropBitmap.isRecycled()) {
          hostBackdropBitmap.recycle();
        }
        hostBackdropBitmap = null;
      }
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && onBackInvokedCallback != null) {
        getOnBackInvokedDispatcher().unregisterOnBackInvokedCallback(onBackInvokedCallback);
        onBackInvokedCallback = null;
      }
      
      if (!callbackSent) {
        callbackSent = true;
        try {
          StashCheckoutBridge.emitDialogDismissed(this);
        } catch (Exception e) {
          Log.w(TAG, "Error sending dialog dismissed: " + e.getMessage(), e);
        }
      }
    } catch (Exception e) {
      Log.w(TAG, "Error in onDestroy: " + e.getMessage(), e);
    }
  }
  
  @Override
  @SuppressWarnings("deprecation") // minSdk 21; use OnBackPressedDispatcher for API 33+
  public void onBackPressed() {
    if (isPurchaseProcessing) {
      return;
    }
    if (awaitingExternalBrowserDimOverlay) {
      finishAfterExternalBrowserClose();
    } else {
      dismissWithAnimation();
    }
  }
  
  @Override
  public void onConfigurationChanged(Configuration newConfig) {
    super.onConfigurationChanged(newConfig);

    if (pendingFinishAfterLandscape) {
      if (newConfig.orientation == Configuration.ORIENTATION_LANDSCAPE) {
        if (hostBackdropImageView != null) {
          hostBackdropImageView.post(this::completeDeferredFinishFromLandscape);
        } else {
          completeDeferredFinishFromLandscape();
        }
      }
      return;
    }

    // forcePortrait from landscape: card creation was deferred until rotation completes so that
    // animateSlideUp uses the correct portrait screen dimensions from the very first frame.
    if (pendingCreateUIAfterRotation
        && newConfig.orientation == Configuration.ORIENTATION_PORTRAIT) {
      pendingCreateUIAfterRotation = false;
      try {
        createUI();
        registerBackCallbackIfNeeded();
      } catch (Exception e) {
        Log.w(TAG, "Error creating UI after rotation: " + e.getMessage(), e);
        finish();
      }
      return;
    }

    if (useModal && cardContainer != null && rootLayout != null) {
      // Modal mode: always animate resize on rotation
      StashCheckoutImeSupport.resetImeOverlap(this);
      animateModalRotation();
      StashCheckoutImeSupport.reapplyImeOverlapAfterRotation(this);
    } else if (!usePopup && cardContainer != null && rootLayout != null) {
      boolean isTablet = cachedIsTablet;
      StashCheckoutImeSupport.resetImeOverlap(this);
      if (isTablet) {
        // Seamless animation for tablet rotation
        animateTabletRotation();
      } else {
        // Phone: keep card sized to config (portrait ratios + insets) after rotation, insets,
        // multi-window, etc. — same path for force-portrait and current-orientation checkout.
        animatePhoneCheckoutRotation();
      }
      StashCheckoutImeSupport.reapplyImeOverlapAfterRotation(this);
    }
  }
  
  private void animateTabletRotation() {
    DisplayMetrics metrics = getResources().getDisplayMetrics();
    int[] newSize = StashCheckoutSizing.calculateTabletCardSize(this, metrics);
    int newWidth = newSize[0];
    int newBaseHeight = newSize[1];
    tabletSdkBaseHeightPx = newBaseHeight;
    int maxH = (int) (metrics.heightPixels * CardConstants.EXPANDED_CARD_HEIGHT_RATIO);
    int targetHeight =
        isExpanded
            ? Math.min(
                Math.round(newBaseHeight * CardConstants.TABLET_SDK_EXPAND_HEIGHT_MULTIPLIER), maxH)
            : newBaseHeight;

    FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
    int currentWidth = params.width;
    int currentHeight = params.height;

    // Animate width
    if (currentWidth != newWidth) {
      ValueAnimator widthAnim = ValueAnimator.ofInt(currentWidth, newWidth);
      widthAnim.setDuration(CardConstants.ANIMATION_DURATION_DEFAULT);
      widthAnim.setInterpolator(new SpringInterpolator());
      widthAnim.addUpdateListener(
          animation -> {
            if (cardContainer != null) {
              FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
              p.width = (Integer) animation.getAnimatedValue();
              cardContainer.setLayoutParams(p);
            }
          });
      widthAnim.start();
    }

    // Animate height
    if (currentHeight != targetHeight) {
      ValueAnimator heightAnim = ValueAnimator.ofInt(currentHeight, targetHeight);
      heightAnim.setDuration(CardConstants.ANIMATION_DURATION_DEFAULT);
      heightAnim.setInterpolator(new SpringInterpolator());
      heightAnim.addUpdateListener(
          animation -> {
            if (cardContainer != null) {
              FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
              p.height = (Integer) animation.getAnimatedValue();
              cardContainer.setLayoutParams(p);
            }
          });
      heightAnim.start();
    }
  }
  
  private void animateModalRotation() {
    DisplayMetrics metrics = getResources().getDisplayMetrics();
    int[] newSize = StashCheckoutSizing.calculateModalCardSize(this, metrics);
    int newWidth = newSize[0];
    int newHeight = newSize[1];
    
    FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
    int currentWidth = params.width;
    int currentHeight = params.height;
    
    // Animate width
    if (currentWidth != newWidth) {
      ValueAnimator widthAnim = ValueAnimator.ofInt(currentWidth, newWidth);
      widthAnim.setDuration(CardConstants.ANIMATION_DURATION_DEFAULT);
      widthAnim.setInterpolator(new SpringInterpolator());
      widthAnim.addUpdateListener(animation -> {
        if (cardContainer != null) {
          FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
          p.width = (int) (Integer) animation.getAnimatedValue();
          cardContainer.setLayoutParams(p);
        }
      });
      widthAnim.start();
    }
    
    // Animate height
    if (currentHeight != newHeight) {
      ValueAnimator heightAnim = ValueAnimator.ofInt(currentHeight, newHeight);
      heightAnim.setDuration(CardConstants.ANIMATION_DURATION_DEFAULT);
      heightAnim.setInterpolator(new SpringInterpolator());
      heightAnim.addUpdateListener(animation -> {
        if (cardContainer != null) {
          FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
          p.height = (int) (Integer) animation.getAnimatedValue();
          cardContainer.setLayoutParams(p);
        }
      });
      heightAnim.start();
    }
  }
  
  private void animatePhoneCheckoutRotation() {
    DisplayMetrics metrics = getResources().getDisplayMetrics();
    int[] newSize = StashCheckoutSizing.calculatePhoneCheckoutCardSize(this, metrics);
    int newWidth = newSize[0];
    
    FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
    int currentWidth = params.width;
    
    // MATCH_PARENT is -1; use actual measured width for animation
    if (currentWidth == FrameLayout.LayoutParams.MATCH_PARENT
        && rootLayout != null
        && rootLayout.getWidth() > 0) {
      currentWidth = rootLayout.getWidth();
    }
    
    if (newWidth == FrameLayout.LayoutParams.MATCH_PARENT && rootLayout != null) {
      int rw = rootLayout.getWidth();
      newWidth = rw > 0 ? rw : metrics.widthPixels;
    }
    
    int currentHeight = params.height;
    int newHeight = newSize[1];
    collapsedCardTargetHeightPx = newHeight;
    params.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
    if (currentWidth == newWidth && currentHeight == newHeight) {
      cardContainer.setLayoutParams(params);
      return;
    }
    
    if (currentWidth != newWidth) {
      ValueAnimator widthAnim = ValueAnimator.ofInt(currentWidth, newWidth);
      widthAnim.setDuration(CardConstants.ANIMATION_DURATION_DEFAULT);
      widthAnim.setInterpolator(new SpringInterpolator());
      widthAnim.addUpdateListener(animation -> {
        if (cardContainer != null) {
          FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
          p.width = (int) (Integer) animation.getAnimatedValue();
          p.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
          cardContainer.setLayoutParams(p);
        }
      });
      widthAnim.start();
    }
    
    if (currentHeight != newHeight) {
      ValueAnimator heightAnim = ValueAnimator.ofInt(currentHeight, newHeight);
      heightAnim.setDuration(CardConstants.ANIMATION_DURATION_DEFAULT);
      heightAnim.setInterpolator(new SpringInterpolator());
      heightAnim.addUpdateListener(animation -> {
        if (cardContainer != null) {
          FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
          p.height = (int) (Integer) animation.getAnimatedValue();
          p.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
          cardContainer.setLayoutParams(p);
        }
      });
      heightAnim.start();
    }
  }
}
