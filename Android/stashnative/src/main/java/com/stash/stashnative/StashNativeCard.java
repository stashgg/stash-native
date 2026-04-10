package com.stash.stashnative;

import android.app.Activity;

/**
 * StashNativeCard - Native Android SDK for Stash Native checkout integration.
 *
 * <p>This is the main entry point for integrating Stash Native checkout into your Android app.
 * It provides methods to display checkout cards and popups, and handles payment callbacks.
 *
 * <p>Usage:
 * <pre>
 * StashNativeCard.getInstance().setActivity(this);
 * StashNativeCard.getInstance().setListener(new StashNativeCard.StashNativeCardListener() {
 *     {@literal @}Override
 *     public void onPaymentSuccess(String order) {
 *         // Handle successful payment; {@code order} is plain or JSON string from the page, or null
 *     }
 *
 *     {@literal @}Override
 *     public void onPaymentFailure() {
 *         // Handle failed payment
 *     }
 *
 *     {@literal @}Override
 *     public void onDialogDismissed() {
 *         // Handle dialog dismissed
 *     }
 *
 *     {@literal @}Override
 *     public void onOptInResponse(String optinType) {
 *         // Handle opt-in response
 *     }
 *
 *     {@literal @}Override
 *     public void onPageLoaded(long loadTimeMs) {
 *         // Handle page loaded
 *     }
 *
 *     {@literal @}Override
 *     public void onNetworkError() {
 *         // Load failed
 *     }
 *
 *     {@literal @}Override
 *     public void onExternalPayment(String url) {
 *         // {@code window.stash_sdk.openExternalBrowser(url)} — URL includes theme query when applicable
 *     }
 * });
 *
 * StashNativeCard.getInstance().openCard("https://your-checkout-url.com", null);
 * </pre>
 */
public class StashNativeCard {
  private static StashNativeCard instance;
  private StashNativeCardPlugin plugin;
  /** Strong reference so callbacks keep working after Custom Tabs / background (WeakRef would allow GC). */
  private StashNativeCardListener listener;
  
  /**
   * Callback interface for Stash Native events.
   */
  public interface StashNativeCardListener {

    /**
     * Called when a payment completes successfully.
     *
     * @param order Optional payload from {@code window.stash_sdk.onPaymentSuccess(order)}: a plain
     *     string or JSON string; {@code null} if the page called {@code onPaymentSuccess()} with no
     *     argument.
     */
    void onPaymentSuccess(String order);

    /**
     * Called when a payment fails.
     */
    void onPaymentFailure();

    /**
     * Called when the checkout dialog is dismissed by the user, or when the embedded page calls
     * {@code window.close()}.
     */
    void onDialogDismissed();
    
    /**
     * Called when an opt-in response is received.
     *
     * @param optinType The type of opt-in response
     */
    void onOptInResponse(String optinType);

    /**
     * Called when the checkout page finishes loading.
     *
     * @param loadTimeMs The page load time in milliseconds
     */
    void onPageLoaded(long loadTimeMs);

    /**
     * Called when checkout cannot be shown or must be torn down due to a load failure.
     * This includes: no network connection, page load failure, timeout (5 seconds), and
     * (on Android 8.0+, API 26+) when the WebView renderer process crashes or is killed; in
     * that case the card is dismissed before this callback runs.
     */
    void onNetworkError();

    /**
     * Called when the checkout page calls {@code window.stash_sdk.openExternalBrowser(url)}. The SDK closes
     * the card/modal without invoking {@link #onDialogDismissed()}, then opens the URL in Chrome
     * Custom Tabs (or the system browser as fallback). The {@code url} includes the theme query
     * parameter when applicable.
     *
     * @param url Validated {@code http} or {@code https} URL
     */
    void onExternalPayment(String url);
  }

  /**
   * Simple adapter class for StashNativeCardListener with empty default implementations.
   * Extend this class if you only need to implement some callbacks.
   */
  public static class StashNativeCardListenerAdapter implements StashNativeCardListener {

    @Override public void onPaymentSuccess(String order) {}

    @Override public void onPaymentFailure() {}

    @Override public void onDialogDismissed() {}

    @Override public void onOptInResponse(String optinType) {}

    @Override public void onPageLoaded(long loadTimeMs) {}

    @Override public void onNetworkError() {}

    @Override public void onExternalPayment(String url) {}
  }

  /**
   * Configuration for custom popup sizing.
   */
  public static class PopupSizeConfig {
    public float portraitWidthMultiplier = CardConstants.POPUP_PORTRAIT_WIDTH_MULTIPLIER;
    public float portraitHeightMultiplier = CardConstants.POPUP_PORTRAIT_HEIGHT_MULTIPLIER;
    public float landscapeWidthMultiplier = CardConstants.POPUP_LANDSCAPE_WIDTH_MULTIPLIER;
    public float landscapeHeightMultiplier = CardConstants.POPUP_LANDSCAPE_HEIGHT_MULTIPLIER;

    /** Default constructor using default size multipliers. */
    public PopupSizeConfig() {}

    /**
     * Constructor with explicit portrait and landscape size multipliers.
     *
     * @param portraitWidth portrait width multiplier
     * @param portraitHeight portrait height multiplier
     * @param landscapeWidth landscape width multiplier
     * @param landscapeHeight landscape height multiplier
     */
    public PopupSizeConfig(float portraitWidth, float portraitHeight,
        float landscapeWidth, float landscapeHeight) {
      this.portraitWidthMultiplier = portraitWidth;
      this.portraitHeightMultiplier = portraitHeight;
      this.landscapeWidthMultiplier = landscapeWidth;
      this.landscapeHeightMultiplier = landscapeHeight;
    }
  }
  
  /**
   * Configuration for modal presentation.
   *
   * <p>Modal always appears centered on screen (unlike checkout which uses cards on phones).
   * Supports independent sizing for phone/tablet and portrait/landscape orientations.
   */
  public static class ModalConfig {
    /** Phone width ratio for portrait (0.1-1.0). */
    public float phoneWidthRatioPortrait = CardConstants.DEFAULT_MODAL_PHONE_WIDTH_RATIO_PORTRAIT;
    /** Phone height ratio for portrait (0.1-1.0). */
    public float phoneHeightRatioPortrait = CardConstants.DEFAULT_MODAL_PHONE_HEIGHT_RATIO_PORTRAIT;
    /** Phone width ratio for landscape (0.1-1.0). */
    public float phoneWidthRatioLandscape = CardConstants.DEFAULT_MODAL_PHONE_WIDTH_RATIO_LANDSCAPE;
    /** Phone height ratio for landscape (0.1-1.0). */
    public float phoneHeightRatioLandscape =
        CardConstants.DEFAULT_MODAL_PHONE_HEIGHT_RATIO_LANDSCAPE;
    /** Tablet width ratio for portrait (0.1-1.0). */
    public float tabletWidthRatioPortrait =
        CardConstants.DEFAULT_MODAL_TABLET_WIDTH_RATIO_PORTRAIT;
    /** Tablet height ratio for portrait (0.1-1.0). */
    public float tabletHeightRatioPortrait =
        CardConstants.DEFAULT_MODAL_TABLET_HEIGHT_RATIO_PORTRAIT;
    /** Tablet width ratio for landscape (0.1-1.0). */
    public float tabletWidthRatioLandscape =
        CardConstants.DEFAULT_MODAL_TABLET_WIDTH_RATIO_LANDSCAPE;
    /** Tablet height ratio for landscape (0.1-1.0). */
    public float tabletHeightRatioLandscape =
        CardConstants.DEFAULT_MODAL_TABLET_HEIGHT_RATIO_LANDSCAPE;
    /** Whether tap outside and drag gestures can dismiss the modal. */
    public boolean allowDismiss = true;
    /**
     * Optional HTML hex for sheet background (#RGB, #RRGGBB, #AARRGGBB). When null or invalid,
     * system light/dark applies. Omit for default Stash theme.
     */
    public String backgroundColor;

    public ModalConfig() {}
    
    /**
     * Creates a modal config with all sizing ratios and behavior flags.
     */
    public ModalConfig(float phoneWidthPortrait, float phoneHeightPortrait,
        float phoneWidthLandscape, float phoneHeightLandscape,
        float tabletWidthPortrait, float tabletHeightPortrait,
        float tabletWidthLandscape, float tabletHeightLandscape,
        boolean allowDismiss) {
      this.phoneWidthRatioPortrait = phoneWidthPortrait;
      this.phoneHeightRatioPortrait = phoneHeightPortrait;
      this.phoneWidthRatioLandscape = phoneWidthLandscape;
      this.phoneHeightRatioLandscape = phoneHeightLandscape;
      this.tabletWidthRatioPortrait = tabletWidthPortrait;
      this.tabletHeightRatioPortrait = tabletHeightPortrait;
      this.tabletWidthRatioLandscape = tabletWidthLandscape;
      this.tabletHeightRatioLandscape = tabletHeightLandscape;
      this.allowDismiss = allowDismiss;
    }
  }

  /**
   * Configuration for card presentation (openCard).
   *
   * <p>Card slides up from bottom on phones; centered on tablets.
   * Supports independent sizing for phone/tablet and portrait/landscape orientations.
   */
  public static class CardConfig {
    /** When true, phone card forces portrait orientation. Default false. */
    public boolean forcePortrait = false;
    /** Phone card height ratio in portrait (0.1-1.0). Default 0.68. */
    public float cardHeightRatioPortrait = CardConstants.DEFAULT_CARD_HEIGHT_RATIO;
    /** Phone card width ratio in landscape (0.1-1.0). Default 0.9. */
    public float cardWidthRatioLandscape = CardConstants.DEFAULT_CARD_WIDTH_RATIO_LANDSCAPE;
    /** Phone card height ratio in landscape (0.1-1.0). Default 0.6. */
    public float cardHeightRatioLandscape = CardConstants.DEFAULT_CARD_HEIGHT_RATIO_LANDSCAPE;
    /** Tablet width ratio in portrait (0.1-1.0). Default 0.4. */
    public float tabletWidthRatioPortrait = CardConstants.DEFAULT_TABLET_WIDTH_RATIO_PORTRAIT;
    /** Tablet height ratio in portrait (0.1-1.0). Default 0.5. */
    public float tabletHeightRatioPortrait = CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_PORTRAIT;
    /** Tablet width ratio in landscape (0.1-1.0). Default 0.3. */
    public float tabletWidthRatioLandscape = CardConstants.DEFAULT_TABLET_WIDTH_RATIO_LANDSCAPE;
    /** Tablet height ratio in landscape (0.1-1.0). Default 0.6. */
    public float tabletHeightRatioLandscape = CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_LANDSCAPE;
    /**
     * Optional HTML hex for sheet background (#RGB, #RRGGBB, #AARRGGBB). When null or invalid,
     * system light/dark applies. Omit for default Stash theme.
     */
    public String backgroundColor;

    public CardConfig() {}
  }

  /**
   * Optional notification title, text, and small icon for the foreground keep-alive service used
   * when {@link #setKeepAliveEnabled(boolean)} is true. If {@code notificationIconResId} is 0, a
   * default library icon is used. Null or empty strings fall back to bundled defaults.
   */
  public static final class KeepAliveConfig {
    public String notificationTitle;
    public String notificationText;
    public int notificationIconResId;

    public KeepAliveConfig() {}
  }
  
  private StashNativeCard() {
    plugin = StashNativeCardPlugin.getInstance();
  }
  
  /**
   * Gets the singleton instance of StashNativeCard.
   *
   * @return The StashNativeCard instance
   */
  public static synchronized StashNativeCard getInstance() {
    if (instance == null) {
      instance = new StashNativeCard();
    }
    return instance;
  }
  
  /**
   * Sets the activity to use for displaying checkout UI.
   * This must be called before opening any checkout.
   *
   * @param activity The current activity
   */
  public void setActivity(Activity activity) {
    plugin.setActivity(activity);
  }
  
  /**
   * Sets the listener for Stash Native events.
   *
   * @param listener The listener to receive callbacks
   */
  public void setListener(StashNativeCardListener listener) {
    this.listener = listener;
    plugin.setListener(listener);
  }
  
  /**
   * Gets the current listener.
   *
   * @return The current StashNativeCardListener
   */
  public StashNativeCardListener getListener() {
    return listener;
  }
  
  /**
   * Opens a URL in a sliding card UI.
   *
   * <p>The card slides up from the bottom of the screen. On tablets, the card appears centered.
   * Pass null for config to use default sizing and behavior.
   *
   * @param url The URL to load in the card
   * @param config Card sizing and orientation configuration (null for defaults)
   */
  public void openCard(String url, CardConfig config) {
    plugin.openCard(url, config);
  }
  
  /**
   * Opens a Stash Native URL in a centered popup dialog.
   *
   * <p>The popup appears centered on screen with a semi-transparent background.
   * Uses default sizing appropriate for the device.
   *
   * @param url The Stash Native URL to load
   */
  public void openPopup(String url) {
    plugin.openPopup(url);
  }
  
  /**
   * Opens a Stash Native URL in a centered popup dialog with custom sizing.
   *
   * @param url The Stash Native URL to load
   * @param sizeConfig Custom size configuration for portrait and landscape orientations
   */
  public void openPopup(String url, PopupSizeConfig sizeConfig) {
    if (sizeConfig != null) {
      plugin.openPopupWithSize(url,
          sizeConfig.portraitWidthMultiplier,
          sizeConfig.portraitHeightMultiplier,
          sizeConfig.landscapeWidthMultiplier,
          sizeConfig.landscapeHeightMultiplier);
    } else {
      plugin.openPopup(url);
    }
  }
  
  /**
   * Opens a URL in a centered modal dialog with default configuration.
   *
   * <p>Unlike openCard which uses different presentations on phones vs tablets,
   * openModal always shows a centered modal on all devices. The modal resizes
   * seamlessly when the device rotates.
   *
   * <p>Uses default sizing ratios with dismiss enabled.
   *
   * @param url The URL to load in the modal
   */
  public void openModal(String url) {
    plugin.openModal(url, null);
  }
  
  /**
   * Opens a URL in a centered modal dialog with custom configuration.
   *
   * <p>Unlike openCard which uses different presentations on phones vs tablets,
   * openModal always shows a centered modal on all devices. The modal resizes
   * seamlessly when the device rotates.
   *
   * @param url The URL to load in the modal
   * @param config Configuration for sizing and dismiss behavior (null for defaults)
   */
  public void openModal(String url, ModalConfig config) {
    plugin.openModal(url, config);
  }
  
  /**
   * Dismisses any currently displayed checkout dialog.
   */
  public void dismiss() {
    plugin.dismissDialog();
  }
  
  /**
   * Resets the presentation state and dismisses any displayed dialog.
   */
  public void resetPresentationState() {
    plugin.resetPresentationState();
  }
  
  /**
   * Checks if a checkout card or popup is currently displayed.
   *
   * @return true if a checkout UI is currently visible
   */
  public boolean isCurrentlyPresented() {
    return plugin.isCurrentlyPresented();
  }
  
  /**
   * Opens a URL in Chrome Custom Tabs when {@code androidx.browser} is present, otherwise in the
   * system browser ({@code ACTION_VIEW}). No callbacks or configuration.
   *
   * @param url The URL to open in the browser
   */
  public void openBrowser(String url) {
    plugin.openBrowser(url);
  }
  
  /**
   * Attempts to close the Chrome Custom Tabs browser.
   * Chrome Custom Tabs cannot be programmatically dismissed on Android.
   * This method exists for API consistency with iOS but has no effect on Android.
   */
  public void closeBrowser() {
    // No-op on Android
  }
  
  /**
   * Checks if a purchase is currently being processed.
   *
   * <p>When true, the checkout dialog cannot be dismissed by the user
   * to prevent interrupting the payment flow.
   *
   * @return true if a purchase is being processed
   */
  public boolean isPurchaseProcessing() {
    return plugin.isPurchaseProcessing();
  }

  /**
   * When true, opening Chrome Custom Tabs or the system browser for {@link #openBrowser(String)},
   * {@code window.stash_sdk.openExternalBrowser(url)}, or portrait checkout external flows may start a short
   * foreground service so the app is less likely to be killed on low-RAM devices. Default false.
   *
   * @param enabled whether to use the keep-alive helper
   */
  public void setKeepAliveEnabled(boolean enabled) {
    plugin.setKeepAliveEnabled(enabled);
  }

  /**
   * @return whether the keep-alive foreground service is enabled
   */
  public boolean isKeepAliveEnabled() {
    return plugin.isKeepAliveEnabled();
  }

  /**
   * Sets optional notification strings and icon for the keep-alive service. Pass null to clear
   * customization (defaults from library strings apply).
   *
   * @param config customization, or null
   */
  public void setKeepAliveConfig(KeepAliveConfig config) {
    plugin.setKeepAliveConfig(config);
  }
  
}
