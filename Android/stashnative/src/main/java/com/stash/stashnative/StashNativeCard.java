package com.stash.stashnative;

import android.app.Activity;

/**
 * StashNativeCard - Native Android SDK for Stash Native checkout integration.
 *
 * <p>This is the main entry point for integrating Stash Native checkout into your Android app. It
 * provides methods to display checkout cards, and handles payment callbacks.
 *
 * <p>Usage:
 *
 * <pre>
 * StashNativeCard.getInstance().setListener(new StashNativeCard.StashNativeCardListener() {
 *     {@literal @}Override
 *     public void onPaymentSuccess(String order) {
 *         // The page supplies order as a string or null.
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
 *         // The external payment URL includes the checkout theme.
 *     }
 *
 *     {@literal @}Override
 *     public void onBrowserClosed() {
 *         // Chrome Custom Tabs / browser dismissed; host activity resumed
 *     }
 * });
 *
 * StashNativeCard.getInstance().openCard(this, "https://your-checkout-url.com", null);
 * </pre>
 */
public class StashNativeCard {
  private static StashNativeCard instance;
  private StashNativeCardPlugin plugin;

  /**
   * Strong reference so callbacks keep working after Custom Tabs / background (WeakRef would allow
   * GC).
   */
  private StashNativeCardListener listener;

  /** Callback interface for Stash Native events. */
  public interface StashNativeCardListener {

    /** Returns the unchanged QR payload once, after Connected and the card's dismissal. */
    default void onQrCodeScanned(String content) {}

    /**
     * Reports an error once per CodeLink session. Missing scanner dependencies close the card;
     * other camera errors leave it open.
     */
    default void onCodeLinkError(CodeLinkError error) {}

    /**
     * Called when a payment completes successfully.
     *
     * @param order Optional payload from {@code window.stash_sdk.onPaymentSuccess(order)}: a plain
     *     string or JSON string; {@code null} if the page called {@code onPaymentSuccess()} with no
     *     argument.
     */
    void onPaymentSuccess(String order);

    /** Called when a payment fails. */
    void onPaymentFailure();

    /**
     * Called when the checkout dialog is dismissed by the user, or when the embedded page calls
     * {@code window.close()}.
     */
    void onDialogDismissed();

    /**
     * Called when the checkout page finishes loading.
     *
     * @param loadTimeMs The page load time in milliseconds
     */
    void onPageLoaded(long loadTimeMs);

    /**
     * Called when checkout cannot be shown or must be torn down due to a load failure. This
     * includes: no network connection, page load failure, a 15-second foreground timeout, and
     * renderer termination on Android 8.0+ (API 26+). For renderer termination,
     * the card is dismissed before this callback runs.
     */
    void onNetworkError();

    /**
     * Called when the checkout page calls {@code window.stash_sdk.openExternalBrowser(url)}. The
     * SDK closes the card without invoking {@link #onDialogDismissed()}, then opens the URL
     * in Chrome Custom Tabs (or the system browser as fallback). The {@code url} includes the theme
     * query parameter when applicable.
     *
     * @param url Validated {@code http} or {@code https} URL
     */
    void onExternalPayment(String url);

    /**
     * Called when the browser opened via {@link #openBrowser(Activity, String)} or {@code
     * window.stash_sdk.openExternalBrowser} is dismissed by the user. For Chrome Custom Tabs, the
     * SDK uses {@link Activity#startActivityForResult} and, when Chrome supports it, engagement
     * session callbacks so this also runs when the tab is closed from floating or minimized UI.
     * Handled internally by the SDK's proxy activity; no host forwarding needed. External browser
     * ({@code ACTION_VIEW}) uses host lifecycle with a short debounce.
     *
     * <p>Very old Chrome or devices without engagement support may still delay {@code
     * onActivityResult} in some floating-dismiss cases until the next host activity transition.
     */
    void onBrowserClosed();
  }

  /**
   * Simple adapter class for StashNativeCardListener with empty default implementations. Extend
   * this class if you only need to implement some callbacks.
   */
  public static class StashNativeCardListenerAdapter implements StashNativeCardListener {

    @Override
    public void onPaymentSuccess(String order) {}

    @Override
    public void onPaymentFailure() {}

    @Override
    public void onDialogDismissed() {}

    @Override
    public void onPageLoaded(long loadTimeMs) {}

    @Override
    public void onNetworkError() {}

    @Override
    public void onExternalPayment(String url) {}

    @Override
    public void onBrowserClosed() {}
  }

  /** Responsive card constraints, measured in density-independent pixels. */
  public static class CardConfig {
    public static final int ORIENTATION_FOLLOW_HOST = 0;
    public static final int ORIENTATION_PORTRAIT = 1;
    public float preferredContentWidth = 400f;
    public float preferredContentHeight = 560f;

    /** Zero uses all available height. */
    public float maximumContentHeight = 720f;

    public float edgeMargin = 16f;

    /** Portrait applies to compact fullscreen windows; tablets and multi-window follow the host. */
    public int orientationPreference = ORIENTATION_FOLLOW_HOST;
    /** Allows user dismissal. Page close, payment callbacks, and native dismiss are independent. */
    public boolean allowDismiss = true;
    public boolean autoClose = true;
  }

  /** Scanner copy, snapshotted when CodeLink opens. Null or empty text uses bundled defaults. */
  public static final class CodeLinkConfig {
    /** Default: "Scan QR code". */
    public String headerText;
    /** Default: "Scan the webshop code". */
    public String calloutTitle;
    /** Default: "Keep the QR code centered inside the frame." */
    public String calloutSubtitle;
    /** Default: "Camera unavailable". */
    public String cameraUnavailableText;
    /** Default: "Connected". */
    public String connectedText;
    /** False removes the callout and gives its space to the scan frame. */
    public boolean showCallout = true;
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

  private static final String SDK_VERSION = "3.0.0";

  /** Returns the SDK version string (e.g. "3.0.0"). */
  public static String getVersion() {
    return SDK_VERSION;
  }

  /** Opt-in webview inspection. Off by default; only debug/sample builds should enable it. */
  private static volatile boolean inspectableWebViewsEnabled = false;

  /**
   * Enables remote inspection (chrome://inspect) of the SDK's checkout webviews. Off by default.
   * When enabled, the SDK calls {@link
   * android.webkit.WebView#setWebContentsDebuggingEnabled(boolean)} (process-global) as it
   * configures each checkout webview.
   *
   * <p>Intended for debug/QA builds and automated UI testing only. Do NOT enable in production: it
   * lets the webview contents be inspected via chrome://inspect. Set before opening any checkout.
   *
   * @param enabled true to make the SDK's webviews inspectable
   */
  public static void setInspectableWebViewsEnabled(boolean enabled) {
    inspectableWebViewsEnabled = enabled;
  }

  /** Returns whether WebView inspection is enabled; disabled by default. */
  public static boolean isInspectableWebViewsEnabled() {
    return inspectableWebViewsEnabled;
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

  /** Bridge from {@link StashNativeBrowserProxyActivity}; not part of the public API. */
  static void notifyBrowserClosedFromProxyInternal(long sessionId) {
    getInstance().plugin.notifyBrowserClosedFromProxyInternal(sessionId);
  }

  /** Bridge from {@link StashNativeBrowserProxyActivity}; not part of the public API. */
  static void notifyBrowserEngagementSessionEndedFromProxyInternal(long sessionId) {
    getInstance().plugin.notifyBrowserEngagementSessionEndedFromProxyInternal(sessionId);
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

  /** Opens a responsive checkout card in the supplied host's task. */
  public void openCard(Activity activity, String url, CardConfig config) {
    plugin.openCard(activity, url, config);
  }

  /** Opens the QR scanner in the responsive card, following the host app's orientation. */
  public void codeLink(Activity activity) {
    codeLink(activity, null);
  }

  /**
   * Opens CodeLink with optional scanner copy. Requires the optional CameraX and ZXing libraries;
   * missing dependencies report {@link CodeLinkError#CAMERA_CONFIGURATION_FAILED} and close.
   */
  public void codeLink(Activity activity, CodeLinkConfig config) {
    plugin.codeLink(activity, config);
  }

  /** Camera and dependency errors reported by CodeLink. */
  public enum CodeLinkError {
    CAMERA_PERMISSION_DENIED,
    CAMERA_UNAVAILABLE,
    CAMERA_CONFIGURATION_FAILED,
    CAMERA_PERMISSION_NOT_DECLARED
  }

  /** Dismisses any currently displayed checkout dialog. */
  public void dismiss() {
    plugin.dismissDialog();
  }

  /** Resets the presentation state and dismisses any displayed dialog. */
  public void resetPresentationState() {
    plugin.resetPresentationState();
  }

  /**
   * Checks if a checkout card is currently displayed.
   *
   * @return true if a checkout UI is currently visible
   */
  public boolean isCurrentlyPresented() {
    return plugin.isCurrentlyPresented();
  }

  /**
   * Opens a URL in Chrome Custom Tabs when {@code androidx.browser} is present, otherwise in the
   * system browser ({@code ACTION_VIEW}). For Custom Tabs, the result is handled internally by the
   * SDK's proxy activity; nothing to forward from this activity so {@link
   * StashNativeCardListener#onBrowserClosed()} runs when the tab closes; {@code ACTION_VIEW} uses
   * lifecycle-based detection (see {@link StashNativeCardListener#onBrowserClosed}).
   *
   * @param url The URL to open in the browser
   */
  public void openBrowser(Activity activity, String url) {
    plugin.openBrowser(activity, url);
  }

  /**
   * Attempts to close the Chrome Custom Tabs browser. Chrome Custom Tabs cannot be programmatically
   * dismissed on Android. This method exists for API consistency with iOS but has no effect on
   * Android.
   */
  public void closeBrowser() {
    // No-op on Android
  }

  /**
   * Checks if a purchase is currently being processed.
   *
   * <p>When true, the checkout dialog cannot be dismissed by the user to prevent interrupting the
   * payment flow.
   *
   * @return true if a purchase is being processed
   */
  public boolean isPurchaseProcessing() {
    return plugin.isPurchaseProcessing();
  }

  /**
   * When true, opening Chrome Custom Tabs or the system browser for {@link #openBrowser(Activity,
   * String)}, {@code window.stash_sdk.openExternalBrowser(url)}, or checkout external flows may
   * start a short foreground service so the app is less likely to be killed on low-RAM devices.
   * Default false.
   *
   * @param enabled whether to use the keep-alive helper
   */
  public void setKeepAliveEnabled(boolean enabled) {
    plugin.setKeepAliveEnabled(enabled);
  }

  /** Returns whether the keep-alive foreground service is enabled. */
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
