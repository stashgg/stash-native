package com.stash.stashnative;

/**
* Shared constants for card presentation, animations, and gestures.
* Aligned with iOS for consistent cross-platform behavior.
*/
public final class CardConstants {
  private CardConstants() {} // Prevent instantiation
  
  // ============================================================================
  // Animation Durations (milliseconds)
  // ============================================================================
  
  /** Default animation duration. */
  public static final int ANIMATION_DURATION_DEFAULT = 400;

  /** Fast animation duration. */
  public static final int ANIMATION_DURATION_FAST = 250;

  /** Entry animation duration. */
  public static final int ANIMATION_DURATION_ENTRY = 450;

  /** Popup fade animation duration. */
  public static final int ANIMATION_DURATION_POPUP = 200;

  /**
   * Phone bottom-sheet entry: backdrop fade-in duration (matches iOS {@code kOverlayFadeInDuration}
   * 0.25s and {@link #ANIMATION_DURATION_FAST}).
   */
  public static final int OVERLAY_FADE_IN_DURATION_MS = ANIMATION_DURATION_FAST;

  /**
   * After overlay fade completes, hold before sheet slide so WebView can advance load (matches iOS
   * {@code kCardEntryHoldAfterOverlayFadeIn} 0.2s).
   */
  public static final long CARD_ENTRY_HOLD_AFTER_OVERLAY_FADE_MS = 200L;

  /** Card collapse animation duration. */
  public static final int ANIMATION_DURATION_COLLAPSE = 380;

  /** Card dismiss animation duration. */
  public static final int ANIMATION_DURATION_DISMISS = 250;

  /** Snap back animation duration. */
  public static final int ANIMATION_DURATION_SNAP_BACK = 450;

  /** Checkout overlay height expand animation (matches default card timing). */
  public static final int ANIMATION_DURATION_EXPAND = ANIMATION_DURATION_DEFAULT;

  /** Delay after opening Chrome Custom Tabs before reporting dialog dismissed. */
  public static final int DIALOG_DISMISS_DELAY_MS = 300;
  
  // ============================================================================
  // Spring Animation Parameters (aligned with iOS)
  // ============================================================================
  
  
  // ============================================================================
  // Gesture Thresholds (Velocity-based, aligned across platforms)
  // ============================================================================
  
  /** Upward velocity threshold to expand (pixels/second). */
  public static final float EXPAND_VELOCITY_THRESHOLD = -300f;

  /** Downward velocity threshold to collapse when expanded (pixels/second). */
  public static final float COLLAPSE_VELOCITY_THRESHOLD = 300f;

  /** Downward velocity threshold to dismiss when collapsed (pixels/second). */
  public static final float DISMISS_VELOCITY_THRESHOLD = 500f;

  /** iPad/Tablet dismiss velocity threshold. */
  public static final float DISMISS_VELOCITY_THRESHOLD_TABLET = 1040f;
  
  // ============================================================================
  // Distance Thresholds (relative to card height)
  // ============================================================================
  
  /** Drag distance to trigger expand (15% of height). */
  public static final float EXPAND_DISTANCE_THRESHOLD = 0.15f;

  /** Drag distance to trigger collapse (25% of height). */
  public static final float COLLAPSE_DISTANCE_THRESHOLD = 0.25f;

  /** Drag distance to trigger dismiss on phone (25% of screen height). */
  public static final float DISMISS_DISTANCE_THRESHOLD_PHONE = 0.25f;

  /** Drag distance to trigger dismiss on tablet (15% of screen height). */
  public static final float DISMISS_DISTANCE_THRESHOLD_TABLET = 0.15f;
  
  // ============================================================================
  // Visual Constants
  // ============================================================================
  
  /** Default corner radius in dp . */
  public static final float CORNER_RADIUS_DP = 12f;
  
  
  /** Card elevation in dp . */
  public static final float ELEVATION_DP = 24f;
  
  /** Drag handle width in dp . */
  public static final float DRAG_HANDLE_WIDTH_DP = 36f;
  
  /** Drag handle height in dp . */
  public static final float DRAG_HANDLE_HEIGHT_DP = 5f;
  

  /**
   * Top inset from card top to the handle bar (matches iOS {@code kHandleBarTopInset} = 8pt).
   */
  public static final float DRAG_HANDLE_TOP_INSET_DP = 8f;

  /**
   * Padding below the handle within the tray (44 - 8 - 5 = 31; matches iOS drag tray layout).
   */
  public static final float DRAG_TRAY_PADDING_BOTTOM_DP = 31f;

  /**
   * Handle pill corner radius (matches iOS {@code kHandleBarCornerRadius} = 3pt).
   */
  public static final float DRAG_HANDLE_CORNER_RADIUS_DP = 3f;
  
  
  // ============================================================================
  // Overlay Opacity (unified across all modes and platforms: 40%)
  // ============================================================================
  
  /** Overlay dim alpha 0-1 (used consistently everywhere). */
  public static final float OVERLAY_ALPHA = 0.4f;

  /** Overlay dim color 40% black - use for all overlay/dim backgrounds. */
  public static final String COLOR_OVERLAY_DIM = "#66000000";
  
  // ============================================================================
  // Default Size Ratios
  // ============================================================================
  
  /** Default phone card height ratio. */
  public static final float DEFAULT_CARD_HEIGHT_RATIO = 0.68f;
  
  
  /** Default phone card width ratio in landscape (when not forcing portrait). */
  public static final float DEFAULT_CARD_WIDTH_RATIO_LANDSCAPE = 0.9f;

  /** Default phone card height ratio in landscape (when not forcing portrait). */
  public static final float DEFAULT_CARD_HEIGHT_RATIO_LANDSCAPE = 0.6f;
  
  /** Expanded phone card height ratio. */
  public static final float EXPANDED_CARD_HEIGHT_RATIO = 0.95f;
  
  
  /** Minimum phone popup/card width in dp . */
  public static final float MIN_PHONE_CARD_WIDTH_DP = 300f;
  
  /** Minimum tablet card width in dp . */
  public static final float MIN_TABLET_CARD_WIDTH_DP = 400f;
  
  /** Minimum tablet card height in dp . */
  public static final float MIN_TABLET_CARD_HEIGHT_DP = 500f;
  
  /** Default tablet height ratio for portrait . */
  public static final float DEFAULT_TABLET_HEIGHT_RATIO_PORTRAIT = 0.5f;
  
  /** Default tablet width ratio for portrait . */
  public static final float DEFAULT_TABLET_WIDTH_RATIO_PORTRAIT = 0.4f;
  
  /** Default tablet height ratio for landscape . */
  public static final float DEFAULT_TABLET_HEIGHT_RATIO_LANDSCAPE = 0.6f;
  
  /** Default tablet width ratio for landscape . */
  public static final float DEFAULT_TABLET_WIDTH_RATIO_LANDSCAPE = 0.3f;
  
  // ============================================================================
  // Modal Default Size Ratios (openModal always shows centered modal)
  // ============================================================================
  
  /** Default modal phone width ratio for portrait . */
  public static final float DEFAULT_MODAL_PHONE_WIDTH_RATIO_PORTRAIT = 0.9f;
  
  /** Default modal phone height ratio for portrait . */
  public static final float DEFAULT_MODAL_PHONE_HEIGHT_RATIO_PORTRAIT = 0.50f;
  
  /** Default modal phone width ratio for landscape . */
  public static final float DEFAULT_MODAL_PHONE_WIDTH_RATIO_LANDSCAPE = 0.50f;
  
  /** Default modal phone height ratio for landscape . */
  public static final float DEFAULT_MODAL_PHONE_HEIGHT_RATIO_LANDSCAPE = 0.80f;
  
  /** Default modal tablet width ratio for portrait . */
  public static final float DEFAULT_MODAL_TABLET_WIDTH_RATIO_PORTRAIT = 0.40f;
  
  /** Default modal tablet height ratio for portrait . */
  public static final float DEFAULT_MODAL_TABLET_HEIGHT_RATIO_PORTRAIT = 0.30f;
  
  /** Default modal tablet width ratio for landscape . */
  public static final float DEFAULT_MODAL_TABLET_WIDTH_RATIO_LANDSCAPE = 0.30f;
  
  /** Default modal tablet height ratio for landscape . */
  public static final float DEFAULT_MODAL_TABLET_HEIGHT_RATIO_LANDSCAPE = 0.40f;
  
  // ============================================================================
  // Popup Size Multipliers
  // ============================================================================
  
  /** Default popup portrait width multiplier . */
  public static final float POPUP_PORTRAIT_WIDTH_MULTIPLIER = 1.0285f;
  
  /** Default popup portrait height multiplier . */
  public static final float POPUP_PORTRAIT_HEIGHT_MULTIPLIER = 1.485f;
  
  /** Default popup landscape width multiplier . */
  public static final float POPUP_LANDSCAPE_WIDTH_MULTIPLIER = 1.2275445f;
  
  /** Default popup landscape height multiplier . */
  public static final float POPUP_LANDSCAPE_HEIGHT_MULTIPLIER = 1.1385f;
  
  /** Popup size ratio for phone . */
  public static final float POPUP_SIZE_RATIO_PHONE = 0.75f;
  
  /** Popup size ratio for tablet . */
  public static final float POPUP_SIZE_RATIO_TABLET = 0.5f;
  
  /** Fallback popup width when calculation fails . */
  public static final int FALLBACK_POPUP_WIDTH = 800;
  
  /** Fallback popup height when calculation fails . */
  public static final int FALLBACK_POPUP_HEIGHT = 600;
  
  /** Fallback card width for tablet . */
  public static final int FALLBACK_TABLET_CARD_WIDTH = 600;
  
  /** Fallback card height for tablet . */
  public static final int FALLBACK_TABLET_CARD_HEIGHT = 700;
  
  /** Loading indicator size in dp . */
  public static final int LOADING_INDICATOR_SIZE_DP = 48;
  
  /** Delay in ms before hiding loading after page finished (Plugin). */
  public static final int HIDE_LOADING_DELAY_MS = 300;
  
  /** Google Pay redirect: domain to detect . */
  public static final String GOOGLE_PAY_DOMAIN = "pay.google.com";
  public static final String GOOGLE_PAY_PARAM_PREFIX_AMP = "&dpm=gpay";
  public static final String GOOGLE_PAY_PARAM_PREFIX_QUERY = "?dpm=gpay";
  
  // ============================================================================
  // Timing Constants
  // ============================================================================
  
  /**
   * If no main-frame response/progress within this window, reload once with a fresh request
   * (bypass cache). Matches iOS {@code kRetryTimeoutInterval} (1.25s).
   */
  public static final long WEBVIEW_RETRY_TIMEOUT_MS = 1250L;

  /**
   * Hard deadline from first load: if the main frame never commits, report network error.
   * Matches iOS {@code kNetworkTimeoutInterval}.
   */
  public static final long WEBVIEW_NETWORK_DEADLINE_MS = 15000L;

  /**
   * Loading overlay crossfade duration (matches iOS {@code kLoadingRevealAnimationDuration} 0.35s).
   */
  public static final long LOADING_REVEAL_DURATION_MS = 350L;
  
  // ============================================================================
  // Visual Effects
  // ============================================================================
  
  /** Alpha fade multiplier for drag feedback . */
  public static final float ALPHA_FADE_MULTIPLIER = 0.5f;
  
  /** Tablet size threshold in dp . */
  public static final int TABLET_SIZE_THRESHOLD_DP = 600;
  
  // ============================================================================
  // Intent Extras (StashNativeCardPlugin -> StashNativeCardPortraitActivity)
  // ============================================================================
  
  public static final String INTENT_EXTRA_URL = "url";
  public static final String INTENT_EXTRA_INITIAL_URL = "initialURL";
  public static final String INTENT_EXTRA_USE_POPUP = "usePopup";
  public static final String INTENT_EXTRA_WAS_LANDSCAPE = "wasLandscape";
  public static final String INTENT_EXTRA_CARD_HEIGHT_RATIO_PORTRAIT = "cardHeightRatioPortrait";
  public static final String INTENT_EXTRA_FORCE_PORTRAIT_ON_CHECKOUT = "forcePortraitOnCheckout";
  public static final String INTENT_EXTRA_CARD_WIDTH_RATIO_LANDSCAPE = "cardWidthRatioLandscape";
  public static final String INTENT_EXTRA_CARD_HEIGHT_RATIO_LANDSCAPE = "cardHeightRatioLandscape";
  public static final String INTENT_EXTRA_TABLET_WIDTH_RATIO_PORTRAIT = "tabletWidthRatioPortrait";
  public static final String INTENT_EXTRA_TABLET_HEIGHT_RATIO_PORTRAIT =
      "tabletHeightRatioPortrait";
  public static final String INTENT_EXTRA_TABLET_WIDTH_RATIO_LANDSCAPE =
      "tabletWidthRatioLandscape";
  public static final String INTENT_EXTRA_TABLET_HEIGHT_RATIO_LANDSCAPE =
      "tabletHeightRatioLandscape";

  // Modal-specific intent extras
  public static final String INTENT_EXTRA_USE_MODAL = "useModal";
  public static final String INTENT_EXTRA_MODAL_SHOW_DRAG_BAR = "modalShowDragBar";
  public static final String INTENT_EXTRA_MODAL_ALLOW_DISMISS = "modalAllowDismiss";
  public static final String INTENT_EXTRA_MODAL_PHONE_WIDTH_RATIO_PORTRAIT =
      "modalPhoneWidthRatioPortrait";
  public static final String INTENT_EXTRA_MODAL_PHONE_HEIGHT_RATIO_PORTRAIT =
      "modalPhoneHeightRatioPortrait";
  public static final String INTENT_EXTRA_MODAL_PHONE_WIDTH_RATIO_LANDSCAPE =
      "modalPhoneWidthRatioLandscape";
  public static final String INTENT_EXTRA_MODAL_PHONE_HEIGHT_RATIO_LANDSCAPE =
      "modalPhoneHeightRatioLandscape";
  public static final String INTENT_EXTRA_MODAL_TABLET_WIDTH_RATIO_PORTRAIT =
      "modalTabletWidthRatioPortrait";
  public static final String INTENT_EXTRA_MODAL_TABLET_HEIGHT_RATIO_PORTRAIT =
      "modalTabletHeightRatioPortrait";
  public static final String INTENT_EXTRA_MODAL_TABLET_WIDTH_RATIO_LANDSCAPE =
      "modalTabletWidthRatioLandscape";
  public static final String INTENT_EXTRA_MODAL_TABLET_HEIGHT_RATIO_LANDSCAPE =
      "modalTabletHeightRatioLandscape";

  // ============================================================================
  // Cross-process checkout bridge (PortraitActivity runs in :stash_webview)
  // ============================================================================

  public static final String BROADCAST_CHECKOUT_PAYMENT_SUCCESS =
      "com.stash.stashnative.internal.CHECKOUT_PAYMENT_SUCCESS";
  public static final String BROADCAST_CHECKOUT_PAYMENT_FAILURE =
      "com.stash.stashnative.internal.CHECKOUT_PAYMENT_FAILURE";
  public static final String BROADCAST_CHECKOUT_OPT_IN =
      "com.stash.stashnative.internal.CHECKOUT_OPT_IN";
  public static final String BROADCAST_CHECKOUT_NETWORK_ERROR =
      "com.stash.stashnative.internal.CHECKOUT_NETWORK_ERROR";
  public static final String BROADCAST_CHECKOUT_DIALOG_DISMISSED =
      "com.stash.stashnative.internal.CHECKOUT_DIALOG_DISMISSED";
  public static final String BROADCAST_EXTRA_OPTIN_TYPE = "stashOptinType";

  /** Message types for notifyListenerAndDismiss (success/failure/optin). */
  public static final String MESSAGE_TYPE_SUCCESS = "success";
  public static final String MESSAGE_TYPE_FAILURE = "failure";
  public static final String MESSAGE_TYPE_OPTIN = "optin";

  // ============================================================================
  // Colors
  // ============================================================================
  
  /** Background dim color (40% alpha). Same as COLOR_OVERLAY_DIM for consistency. */
  public static final String COLOR_BACKGROUND_DIM = COLOR_OVERLAY_DIM;
  
  public static final String COLOR_LIGHT_BG = "#F2F2F7";
  public static final String COLOR_DARK_BG = "#1e1e1e";
  /** Home button background in dark theme (iOS-style system gray). */
  public static final String COLOR_HOME_BUTTON_DARK_BG = "#2C2C2E";
  public static final String COLOR_DARK_STROKE = "#38383A";
  public static final String COLOR_LIGHT_STROKE = "#E5E5EA";
  public static final String COLOR_DRAG_HANDLE = "#D1D1D6";
  public static final String COLOR_HOME_TEXT = "#8E8E93";
}
