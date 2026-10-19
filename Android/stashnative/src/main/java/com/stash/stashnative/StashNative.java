package com.stash.stashnative;

import android.app.Activity;
import android.graphics.Bitmap;

/**
 * Native Android SDK for Stash checkout, browser, and QR Code Linking integration.
 *
 * <p>This is the main entry point for Stash Native in your Android app. It opens checkout cards,
 * browser sessions, and the QR scanner, and delivers their callbacks.
 *
 * <p>Usage:
 *
 * <pre>
 * StashNative.getInstance().setListener(new StashNative.StashNativeListenerAdapter() {
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
 *     public void onCardDismissed() {
 *         // Handle checkout dismissal
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
 *     public void onBrowserDismissed() {
 *         // Browser dismissed
 *     }
 * });
 *
 * StashNative.getInstance().openCard(this, "https://your-checkout-url.com", null);
 * </pre>
 */
public class StashNative {
  private static StashNative instance;
  private final StashNativePlugin plugin;

  /**
   * Shared live listener for all SDK flows. Callbacks run on the main thread. Replacing the
   * listener affects future events from already-open flows; clearing it drops events.
   */
  public interface StashNativeListener {

    /** Returns the unchanged QR payload once, after Connected and the card's dismissal. */
    default void onQrCodeScanned(String content) {}

    /**
     * Reports an error once per scanner session. {@link ScannerError#SCANNER_UNAVAILABLE}
     * closes the card without a dismissal callback when the optional {@code stashnative-codelink}
     * module or its camera libraries are missing. Other camera errors leave the card open.
     */
    default void onScannerError(ScannerError error) {}

    /**
     * Called when a payment completes successfully. With {@code autoClose=false}, payment events
     * can repeat while the card remains open.
     *
     * @param order Optional payload from {@code window.stash_sdk.onPaymentSuccess(order)}: a plain
     *     string or JSON string; {@code null} if the page called {@code onPaymentSuccess()} with no
     *     argument.
     */
    void onPaymentSuccess(String order);

    /** Called when a payment fails; repeatable with {@code autoClose=false}. */
    void onPaymentFailure();

    /**
     * Called when the user, {@link StashNative#dismiss()}, or the page's {@code window.close()}
     * dismisses checkout. Payment-driven closure, browser handoff, and load or connection
     * failures (reported through {@link #onNetworkError()}) do not emit this event.
     */
    void onCardDismissed();

    /** Called when the scanner is dismissed without a result by the user or native dismiss. */
    default void onScannerDismissed() {}

    /**
     * Called when the checkout page finishes loading.
     *
     * @param loadTimeMs The page load time in milliseconds
     */
    void onPageLoaded(long loadTimeMs);

    /**
     * Called when checkout cannot be shown or must be torn down: no network connection, a failed
     * initial response, the 15-second load deadline, a connection failure after the page loaded
     * (also during purchase processing), or an unrecoverable renderer loss on Android 8.0+
     * (API 26+). The card is dismissed before this callback runs; {@link #onCardDismissed()} is
     * not sent.
     */
    void onNetworkError();

    /**
     * Called before launching the checkout page's {@code window.stash_sdk.openExternalBrowser(url)}
     * handoff in Chrome Custom Tabs (or the system browser as fallback). The URL includes the
     * theme query parameter when applicable. The card hides after launch and finishes after the
     * browser-dismissal callback, without {@link #onCardDismissed()}.
     *
     * @param url Validated {@code http} or {@code https} URL
     */
    void onExternalPayment(String url);

    /**
     * Called when a browser opened via {@link StashNative#openBrowser(Activity, String)} or
     * checkout's {@code window.stash_sdk.openExternalBrowser} closes. For Chrome Custom Tabs,
     * the SDK uses {@link Activity#startActivityForResult} and, when Chrome supports it, engagement
     * session callbacks so this also runs when the tab is closed from floating or minimized UI.
     * Handled internally by the SDK's proxy activity; no host forwarding needed. The system
     * browser fallback ({@code ACTION_VIEW}) uses activity lifecycle with a short debounce: the
     * host activity after {@code openBrowser}, the checkout activity after a checkout handoff.
     *
     * <p>Very old Chrome or devices without engagement support may still delay {@code
     * onActivityResult} in some floating-dismiss cases until the next host activity transition.
     */
    void onBrowserDismissed();
  }

  /**
   * Simple adapter class for StashNativeListener with empty default implementations. Extend
   * this class if you only need to implement some callbacks.
   */
  public static class StashNativeListenerAdapter implements StashNativeListener {

    @Override
    public void onPaymentSuccess(String order) {}

    @Override
    public void onPaymentFailure() {}

    @Override
    public void onCardDismissed() {}

    @Override
    public void onPageLoaded(long loadTimeMs) {}

    @Override
    public void onNetworkError() {}

    @Override
    public void onExternalPayment(String url) {}

    @Override
    public void onBrowserDismissed() {}
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

  /** Scanner copy, snapshotted when the scanner opens. Null or empty text uses bundled defaults. */
  public static final class ScannerConfig {
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

  private StashNative() {
    plugin = StashNativePlugin.getInstance();
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
   * Gets the singleton instance of StashNative.
   *
   * @return The StashNative instance
   */
  public static synchronized StashNative getInstance() {
    if (instance == null) {
      instance = new StashNative();
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
   * Sets the single, strongly retained listener on the main thread. Replacing it affects future
   * callbacks from all flows, including those already open. Pass null on the main thread to stop
   * delivery; dropped events are not replayed. Clear an Activity-owned listener during teardown.
   *
   * @param listener The listener to receive callbacks, or null to clear it
   */
  public void setListener(StashNativeListener listener) {
    plugin.setListener(listener);
  }

  /**
   * Gets the current listener. Call on the main thread.
   *
   * @return The current StashNativeListener
   */
  public StashNativeListener getListener() {
    return plugin.getListener();
  }

  /** Opens a responsive checkout card in the supplied host's task. May be called on any thread. */
  public void openCard(Activity activity, String url, CardConfig config) {
    plugin.openCard(activity, url, config);
  }

  /**
   * Supplies a screenshot for the next accepted card's portrait backdrop. Pass null to clear.
   * The SDK takes ownership and recycles the bitmap; do not reuse it after this call.
   */
  public static void setBackdropBitmap(Bitmap bitmap) {
    StashNativePlugin.getInstance().setBackdropBitmap(bitmap);
  }

  /** Supplies PNG/JPEG backdrop bytes, convenient for Unity/JNI. Null or invalid bytes clear it. */
  public static void setBackdropBytes(byte[] pngOrJpeg) {
    setBackdropBitmap(StashHostBackdropSupport.decode(pngOrJpeg));
  }

  /** Opens the QR scanner following the host app's orientation. May be called on any thread. */
  public void openScanner(Activity activity) {
    openScanner(activity, null);
  }

  /**
   * Opens the QR scanner with optional copy. May be called on any thread. Scanning is opt in:
   * the host adds the {@code stashnative-codelink} module, which declares {@code
   * android.permission.CAMERA} and uses the CameraX and ZXing libraries. A missing permission
   * declaration reports {@link ScannerError#CAMERA_PERMISSION_NOT_DECLARED}; a missing module
   * or library reports {@link ScannerError#SCANNER_UNAVAILABLE} and closes without a dismissal
   * callback.
   */
  public void openScanner(Activity activity, ScannerConfig config) {
    plugin.openScanner(activity, config);
  }

  /** Camera and dependency errors reported by the scanner. */
  public enum ScannerError {
    CAMERA_PERMISSION_DENIED,
    CAMERA_UNAVAILABLE,
    /** Camera setup failed; the scanner card remains open. */
    CAMERA_CONFIGURATION_FAILED,
    /** The host manifest does not declare android.permission.CAMERA; the card stays open. */
    CAMERA_PERMISSION_NOT_DECLARED,
    /** The stashnative-codelink module or its libraries are missing; the card closes. */
    SCANNER_UNAVAILABLE
  }

  /** Dismisses the active checkout or scanner card. */
  public void dismiss() {
    plugin.dismissDialog();
  }

  /** Silently tears down active flows, retaining the listener. */
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
   * Opens a URL from any thread in Chrome Custom Tabs when {@code androidx.browser} is present,
   * otherwise in the system browser ({@code ACTION_VIEW}). For Custom Tabs, the result is handled
   * internally by the
   * SDK's proxy activity; nothing to forward from this activity so {@link
   * StashNativeListener#onBrowserDismissed()} runs when the tab closes;
   * {@code ACTION_VIEW} uses lifecycle-based detection (see
   * {@link StashNativeListener#onBrowserDismissed()}).
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
