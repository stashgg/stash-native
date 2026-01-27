package com.stash.popup;

import android.app.Activity;
import android.app.Dialog;
import android.content.Intent;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Outline;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Gravity;
import android.view.Surface;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewOutlineProvider;
import android.view.ViewTreeObserver;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.CookieManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.ProgressBar;
import android.net.Uri;

/**
 * Internal plugin class that handles the WebView and dialog management.
 * Use {@link StashPayCard} for the public API.
 */
public class StashPayCardPlugin {
    private static final String TAG = "StashPayCard";
    private static StashPayCardPlugin instance;
    
    private Activity activity;
    private StashPayCard.StashPayListener listener;

    private Dialog currentDialog;
    private WebView webView;
    private FrameLayout currentContainer;
    private ProgressBar loadingIndicator;
    private ViewTreeObserver.OnGlobalLayoutListener orientationChangeListener;
    
    // Pre-warming optimization (memory-aware)
    private WebView preWarmedWebView;
    private boolean isPreWarming = false;
    private boolean preWarmingEnabled = true; // Can be disabled for low-memory devices
    private String preConnectedDomain = null; // Track which domain we've pre-connected to
    
    // DialogFragment optimization (faster than Activity)
    // Auto-enabled when pre-warming is disabled (low-memory devices)
    public boolean useDialogFragment = false; // Set to true to use DialogFragment instead of Activity
    
    // Debug timing measurements
    public boolean enableTimingLogs = true; // Enabled by default for performance monitoring
    private long timingStartTime;
    private long timingWebViewCreateStart;
    private long timingUIShowStart;
    
    private float cardHeightRatio = 0.6f;
    private boolean isCurrentlyPresented;
    private boolean paymentSuccessHandled;
    private boolean isPurchaseProcessing;
    private boolean usePopupPresentation;
    private boolean forceSafariViewController;
    private int lastOrientation = Configuration.ORIENTATION_UNDEFINED;
    
    private boolean useCustomSize;
    private float customPortraitWidthMultiplier = 1.0285f;
    private float customPortraitHeightMultiplier = 1.485f;
    private float customLandscapeWidthMultiplier = 1.2275445f;
    private float customLandscapeHeightMultiplier = 1.1385f;
    
    private long pageLoadStartTime;
    
    private class StashJavaScriptInterface {
        @JavascriptInterface
        public void onPaymentSuccess() {
            if (paymentSuccessHandled) return;
            paymentSuccessHandled = true;
            isPurchaseProcessing = false;

            new Handler(Looper.getMainLooper()).post(() -> {
                try {
                    if (listener != null) {
                        listener.onPaymentSuccess();
                    }
                    dismissCurrentDialog();
                } catch (Exception e) {
                    Log.e(TAG, "Error handling payment success: " + e.getMessage());
                    cleanupAllViews();
                }
            });
        }
        
        @JavascriptInterface
        public void onPaymentFailure() {
            if (paymentSuccessHandled) return;
            paymentSuccessHandled = true;
            isPurchaseProcessing = false;
            new Handler(Looper.getMainLooper()).post(() -> {
                try {
                    if (listener != null) {
                        listener.onPaymentFailure();
                    }
                    dismissCurrentDialog();
                } catch (Exception e) {
                    Log.e(TAG, "Error handling payment failure: " + e.getMessage());
                    cleanupAllViews();
                }
            });
        }
        
        @JavascriptInterface
        public void onPurchaseProcessing() {
            try {
                isPurchaseProcessing = true;
                new Handler(Looper.getMainLooper()).post(() -> {
                    try {
                        if (currentDialog != null && currentDialog.isShowing()) {
                            currentDialog.setCanceledOnTouchOutside(false);
                            currentDialog.setCancelable(false);
                        }
                    } catch (Exception e) {
                        Log.e(TAG, "Error updating dialog dismissibility: " + e.getMessage(), e);
                    }
                });
            } catch (Exception e) {
                Log.e(TAG, "Error in onPurchaseProcessing: " + e.getMessage(), e);
            }
        }
        
        @JavascriptInterface
        public void setPaymentChannel(String optinType) {
            new Handler(Looper.getMainLooper()).post(() -> {
                try {
                    if (listener != null) {
                        listener.onOptInResponse(optinType != null ? optinType : "");
                    }
                    dismissCurrentDialog();
                } catch (Exception e) {
                    Log.e(TAG, "Error handling payment channel: " + e.getMessage());
                }
            });
        }
        
        @JavascriptInterface
        public void expand() {
            // Expand functionality can be implemented here if needed
        }
        
        @JavascriptInterface
        public void collapse() {
            // Collapse functionality can be implemented here if needed
        }
    }
    
    public static StashPayCardPlugin getInstance() {
        if (instance == null) {
            instance = new StashPayCardPlugin();
        }
        return instance;
    }
    
    private StashPayCardPlugin() {
    }
    
    void setActivity(Activity activity) {
        this.activity = activity;
        // Auto-disable pre-warming on low-end devices
        if (activity != null && StashWebViewUtils.isLowEndDevice()) {
            preWarmingEnabled = false;
            Log.d(TAG, "Pre-warming disabled on low-end device");
        }
        
        // Auto-enable DialogFragment when pre-warming is disabled (compensation optimization)
        // DialogFragment is faster and uses less memory, good for low-memory devices
        if (activity != null && !preWarmingEnabled && activity instanceof androidx.fragment.app.FragmentActivity) {
            if (!useDialogFragment) {
                useDialogFragment = true;
                if (enableTimingLogs) {
                    Log.d(TAG, "⏱️ [TIMING] Auto-enabled DialogFragment (pre-warming disabled)");
                }
            }
        }
    }
    
    void setListener(StashPayCard.StashPayListener listener) {
        this.listener = listener;
    }
    
    /**
     * Pre-warms a WebView instance if device has sufficient memory.
     * This improves initial load time but consumes ~20-50MB RAM.
     * Only pre-warms on devices with >=2GB RAM and >=200MB available.
     * 
     * @param activity The activity context
     */
    public void preWarmWebView(Activity activity) {
        if (activity == null || !preWarmingEnabled) {
            return;
        }
        
        // Check memory before pre-warming
        if (!StashWebViewUtils.hasSufficientMemoryForPreWarming(activity)) {
            Log.d(TAG, "Skipping pre-warming due to insufficient memory");
            preWarmingEnabled = false; // Disable for future attempts
            
            // Auto-enable DialogFragment as compensation (faster, less memory)
            // This happens immediately when pre-warming fails
            if (activity instanceof androidx.fragment.app.FragmentActivity && !useDialogFragment) {
                useDialogFragment = true;
                if (enableTimingLogs) {
                    Log.d(TAG, "⏱️ [TIMING] Auto-enabled DialogFragment (insufficient memory for pre-warming)");
                } else {
                    Log.d(TAG, "Auto-enabled DialogFragment (insufficient memory for pre-warming)");
                }
            }
            return;
        }
        
        if (preWarmedWebView != null || isPreWarming) {
            return; // Already pre-warmed or in progress
        }
        
        isPreWarming = true;
        
        // Create on UI thread (WebView requirement)
        activity.runOnUiThread(() -> {
            try {
                preWarmedWebView = new WebView(activity);
                StashWebViewUtils.configureWebViewSettings(
                    preWarmedWebView, 
                    StashWebViewUtils.isDarkTheme(activity)
                );
                
                // Pre-load a minimal blank page to initialize WebView engine
                // This is much lighter than loading a full checkout page
                preWarmedWebView.loadDataWithBaseURL(
                    "https://stash.gg", 
                    "<html><head><meta name='viewport' content='width=device-width, initial-scale=1.0'></head><body></body></html>", 
                    "text/html", 
                    "UTF-8", 
                    null
                );
                
                isPreWarming = false;
                if (enableTimingLogs) {
                    Log.d(TAG, "⏱️ [TIMING] WebView pre-warmed successfully");
                } else {
                    Log.d(TAG, "WebView pre-warmed successfully");
                }
            } catch (OutOfMemoryError e) {
                Log.w(TAG, "Out of memory during pre-warming, disabling feature", e);
                preWarmingEnabled = false;
                isPreWarming = false;
                cleanupPreWarmedWebView();
            } catch (Exception e) {
                Log.e(TAG, "Error pre-warming WebView: " + e.getMessage(), e);
                isPreWarming = false;
                cleanupPreWarmedWebView();
            }
        });
    }
    
    /**
     * Pre-connects to a domain by loading a minimal resource in the pre-warmed WebView.
     * This establishes TCP connection, DNS cache, and TLS handshake before actual page load.
     * Can save 100-300ms on network delay.
     * 
     * @param url The target URL to pre-connect to
     * @param activity The activity context
     */
    private void preConnectToDomain(String url, Activity activity) {
        if (activity == null || url == null || url.isEmpty()) {
            if (enableTimingLogs) {
                Log.d(TAG, "⏱️ [TIMING] Pre-connect skipped: invalid parameters");
            }
            return;
        }
        
        try {
            String baseUrl = StashWebViewUtils.extractBaseUrl(url);
            if (baseUrl == null) {
                if (enableTimingLogs) {
                    Log.d(TAG, "⏱️ [TIMING] Pre-connect skipped: failed to extract base URL");
                }
                return;
            }
            
            if (baseUrl.equals(preConnectedDomain)) {
                if (enableTimingLogs) {
                    Log.d(TAG, "⏱️ [TIMING] Pre-connect skipped: already connected to " + baseUrl);
                }
                return; // Already pre-connected to this domain
            }
            
            // Only pre-connect if we have a pre-warmed WebView ready
            if (preWarmedWebView == null) {
                if (enableTimingLogs) {
                    Log.d(TAG, "⏱️ [TIMING] Pre-connect skipped: WebView not pre-warmed yet (pre-warming in progress: " + isPreWarming + ")");
                }
                return;
            }
            
            if (isPreWarming) {
                if (enableTimingLogs) {
                    Log.d(TAG, "⏱️ [TIMING] Pre-connect skipped: pre-warming still in progress");
                }
                return;
            }
            
            preConnectedDomain = baseUrl;
            
            // Load a minimal data URL with the target domain as base URL
            // This establishes the connection without loading actual content
            String minimalHtml = "<html><head></head><body></body></html>";
            
            if (enableTimingLogs) {
                Log.d(TAG, "⏱️ [TIMING] Pre-connecting to domain: " + baseUrl);
            }
            
            // Load in background - don't wait for it
            // Using loadDataWithBaseURL establishes connection to the domain
            // Optimize: Check if already on UI thread to avoid runOnUiThread overhead
            if (Looper.myLooper() == Looper.getMainLooper()) {
                // Already on UI thread - direct call (saves ~2-5ms)
                try {
                    preWarmedWebView.loadDataWithBaseURL(
                        baseUrl,
                        minimalHtml,
                        "text/html",
                        "UTF-8",
                        null
                    );
                    if (enableTimingLogs) {
                        Log.d(TAG, "⏱️ [TIMING] Pre-connect request sent to domain: " + baseUrl);
                    }
                } catch (Exception e) {
                    Log.d(TAG, "Pre-connect failed (non-critical): " + e.getMessage());
                }
            } else {
                activity.runOnUiThread(() -> {
                    try {
                        preWarmedWebView.loadDataWithBaseURL(
                            baseUrl,
                            minimalHtml,
                            "text/html",
                            "UTF-8",
                            null
                        );
                        if (enableTimingLogs) {
                            Log.d(TAG, "⏱️ [TIMING] Pre-connect request sent to domain: " + baseUrl);
                        }
                    } catch (Exception e) {
                        Log.d(TAG, "Pre-connect failed (non-critical): " + e.getMessage());
                    }
                });
            }
        } catch (Exception e) {
            Log.d(TAG, "Error pre-connecting: " + e.getMessage());
        }
    }
    
    /**
     * Gets or creates a WebView, reusing pre-warmed instance if available.
     * Falls back to creating new WebView if pre-warming failed or was disabled.
     */
    WebView getOrCreateWebView(Activity activity) {
        if (enableTimingLogs) {
            timingWebViewCreateStart = System.currentTimeMillis();
        }
        
        if (preWarmedWebView != null && activity != null) {
            // Reuse pre-warmed WebView
            WebView webView = preWarmedWebView;
            preWarmedWebView = null; // Clear reference to prevent reuse
            preConnectedDomain = null; // Reset pre-connection tracking
            if (enableTimingLogs) {
                long time = System.currentTimeMillis() - timingWebViewCreateStart;
                Log.d(TAG, "⏱️ [TIMING] Reusing pre-warmed WebView: " + time + "ms");
            } else {
                Log.d(TAG, "Reusing pre-warmed WebView");
            }
            return webView;
        }
        
        // Create new WebView - optimized path (removed redundant version check)
        WebView webView;
        try {
            webView = new WebView(activity);
            // Set hardware layer type immediately for faster rendering (saves ~5-10ms)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
                webView.setLayerType(View.LAYER_TYPE_HARDWARE, null);
            }
        } catch (Exception e) {
            Log.e(TAG, "Error creating WebView: " + e.getMessage(), e);
            webView = new WebView(activity);
        }
        
        if (enableTimingLogs) {
            long time = System.currentTimeMillis() - timingWebViewCreateStart;
            Log.d(TAG, "⏱️ [TIMING] Created new WebView: " + time + "ms");
        }
        return webView;
    }
    
    /**
     * Cleans up pre-warmed WebView to free memory.
     */
    private void cleanupPreWarmedWebView() {
        if (preWarmedWebView != null) {
            try {
                if (preWarmedWebView.getParent() != null) {
                    ((ViewGroup)preWarmedWebView.getParent()).removeView(preWarmedWebView);
                }
                preWarmedWebView.stopLoading();
                preWarmedWebView.destroy();
            } catch (Exception e) {
                Log.e(TAG, "Error cleaning up pre-warmed WebView: " + e.getMessage());
            }
            preWarmedWebView = null;
            preConnectedDomain = null; // Reset pre-connection tracking
        }
    }
    
    /**
     * Re-pre-warms WebView after checkout closes to keep it ready for next use.
     * This ensures subsequent checkouts are fast.
     */
    private void rePreWarmWebViewIfNeeded() {
        // Only re-pre-warm if pre-warming is enabled and we have an activity
        if (preWarmingEnabled && activity != null && preWarmedWebView == null && !isPreWarming) {
            // Delay slightly to avoid doing work during cleanup
            new Handler(Looper.getMainLooper()).postDelayed(() -> {
                if (activity != null && preWarmingEnabled && preWarmedWebView == null && !isPreWarming) {
                    if (enableTimingLogs) {
                        Log.d(TAG, "⏱️ [TIMING] Re-pre-warming WebView for next use");
                    }
                    preWarmWebView(activity);
                }
            }, 300); // Wait 300ms after cleanup before re-pre-warming
        }
    }
    
    public void openCheckout(String url) {
        try {
            if (enableTimingLogs) {
                timingStartTime = System.currentTimeMillis();
                Log.d(TAG, "⏱️ [TIMING] openCheckout() called");
            }
            usePopupPresentation = false;
            openURLInternal(url);
        } catch (Exception e) {
            Log.e(TAG, "Error in openCheckout: " + e.getMessage(), e);
            cleanupAllViews();
        }
    }
    
    public void openPopup(String url) {
        try {
            if (enableTimingLogs) {
                timingStartTime = System.currentTimeMillis();
                Log.d(TAG, "⏱️ [TIMING] openPopup() called");
            }
            usePopupPresentation = true;
            useCustomSize = false;
            openURLInternal(url);
        } catch (Exception e) {
            Log.e(TAG, "Error in openPopup: " + e.getMessage(), e);
            cleanupAllViews();
        }
    }
    
    public void openPopupWithSize(String url, float portraitWidthMultiplier, float portraitHeightMultiplier, 
                                   float landscapeWidthMultiplier, float landscapeHeightMultiplier) {
        try {
            usePopupPresentation = true;
            customPortraitWidthMultiplier = portraitWidthMultiplier;
            customPortraitHeightMultiplier = portraitHeightMultiplier;
            customLandscapeWidthMultiplier = landscapeWidthMultiplier;
            customLandscapeHeightMultiplier = landscapeHeightMultiplier;
            useCustomSize = true;
            openURLInternal(url);
        } catch (Exception e) {
            Log.e(TAG, "Error in openPopupWithSize: " + e.getMessage(), e);
            cleanupAllViews();
        }
    }
    
    public void dismissDialog() {
        if (activity != null) {
            activity.runOnUiThread(() -> {
                try {
                    dismissCurrentDialog();
                } catch (Exception e) {
                    Log.e(TAG, "Error dismissing dialog: " + e.getMessage());
                    cleanupAllViews();
                }
            });
        }
    }
    
    public void resetPresentationState() {
        try {
            dismissDialog();
            paymentSuccessHandled = false;
            isCurrentlyPresented = false;
        } catch (Exception e) {
            Log.e(TAG, "Error in resetPresentationState: " + e.getMessage(), e);
            cleanupAllViews();
        }
    }
    
    public boolean isCurrentlyPresented() {
        try {
            return isCurrentlyPresented;
        } catch (Exception e) {
            Log.e(TAG, "Error in isCurrentlyPresented: " + e.getMessage(), e);
            return false;
        }
    }
    
    public void setCardConfiguration(float heightRatio, float verticalPosition, float widthRatio) {
        try {
            this.cardHeightRatio = heightRatio;
        } catch (Exception e) {
            Log.e(TAG, "Error in setCardConfiguration: " + e.getMessage(), e);
        }
    }
    
    public void setForceSafariViewController(boolean force) {
        try {
            this.forceSafariViewController = force;
        } catch (Exception e) {
            Log.e(TAG, "Error in setForceSafariViewController: " + e.getMessage(), e);
        }
    }
    
    public boolean getForceSafariViewController() {
        try {
            return forceSafariViewController;
        } catch (Exception e) {
            Log.e(TAG, "Error in getForceSafariViewController: " + e.getMessage(), e);
            return false;
        }
    }
    
    public boolean isPurchaseProcessing() {
        try {
            return isPurchaseProcessing;
        } catch (Exception e) {
            Log.e(TAG, "Error in isPurchaseProcessing: " + e.getMessage(), e);
            return false;
        }
    }
    
    private void openURLInternal(String url) {
        try {
            if (activity == null || url == null || url.isEmpty()) {
                Log.e(TAG, "Invalid activity or URL");
                return;
            }

            // Ensure DialogFragment is enabled if pre-warming is disabled (compensation optimization)
            if (!preWarmingEnabled && activity instanceof androidx.fragment.app.FragmentActivity && !useDialogFragment) {
                useDialogFragment = true;
                if (enableTimingLogs) {
                    Log.d(TAG, "⏱️ [TIMING] Auto-enabled DialogFragment (pre-warming disabled)");
                }
            }

            if (!url.startsWith("http://") && !url.startsWith("https://")) {
                url = "https://" + url;
            }

            try {
                url = StashWebViewUtils.appendThemeQueryParameter(url, StashWebViewUtils.isDarkTheme(activity));
            } catch (Exception e) {
                Log.e(TAG, "Error appending theme parameter: " + e.getMessage(), e);
            }

            // Pre-connect to the domain to reduce network delay
            preConnectToDomain(url, activity);

            final String finalUrl = url;

            activity.runOnUiThread(() -> {
                try {
                    if (usePopupPresentation) {
                        createAndShowPopupDialog(finalUrl, activity);
                    } else if (forceSafariViewController) {
                        openWithChromeCustomTabs(finalUrl, activity);
                    } else {
                        // Use DialogFragment if enabled (faster), otherwise use Activity
                        if (useDialogFragment && activity instanceof androidx.fragment.app.FragmentActivity) {
                            if (enableTimingLogs) {
                                Log.d(TAG, "⏱️ [TIMING] Using DialogFragment (faster than Activity)");
                            }
                            launchDialogFragment(finalUrl, (androidx.fragment.app.FragmentActivity) activity);
                        } else {
                            if (enableTimingLogs && !useDialogFragment) {
                                Log.d(TAG, "⏱️ [TIMING] Using Activity (DialogFragment not available or disabled)");
                            }
                            launchPortraitActivity(finalUrl, activity);
                        }
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error in UI thread operation: " + e.getMessage(), e);
                    cleanupAllViews();
                }
            });
        } catch (Exception e) {
            Log.e(TAG, "Error in openURLInternal: " + e.getMessage(), e);
            cleanupAllViews();
        }
    }
    
    /**
     * Launches DialogFragment version (faster, lower memory).
     * This is an optional optimization - can be removed if not needed.
     */
    private void launchDialogFragment(String url, androidx.fragment.app.FragmentActivity activity) {
        try {
            if (enableTimingLogs) {
                timingUIShowStart = System.currentTimeMillis();
                long timeToLaunch = timingUIShowStart - timingStartTime;
                Log.d(TAG, "⏱️ [TIMING] Launching DialogFragment (time since openCheckout: " + timeToLaunch + "ms)");
            }
            
            android.view.Display display = activity.getWindowManager().getDefaultDisplay();
            int rotation = display.getRotation();
            boolean isLandscape = (rotation == Surface.ROTATION_90 || rotation == Surface.ROTATION_270);
            
            StashPayCardDialogFragment fragment = StashPayCardDialogFragment.newInstance(
                url, url, usePopupPresentation, isLandscape
            );
            
            fragment.show(activity.getSupportFragmentManager(), "StashPayCardDialog");
            isCurrentlyPresented = true;
            
            if (enableTimingLogs) {
                long launchTime = System.currentTimeMillis() - timingUIShowStart;
                Log.d(TAG, "⏱️ [TIMING] DialogFragment launched in: " + launchTime + "ms");
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to launch DialogFragment, falling back to Activity: " + e.getMessage());
            // Fallback to Activity if DialogFragment fails
            launchPortraitActivity(url, activity);
        }
    }
    
    private void launchPortraitActivity(String url, Activity activity) {
        try {
            if (enableTimingLogs) {
                timingUIShowStart = System.currentTimeMillis();
                long timeToLaunch = timingUIShowStart - timingStartTime;
                Log.d(TAG, "⏱️ [TIMING] Launching Activity (time since openCheckout: " + timeToLaunch + "ms)");
            }
            
            android.view.Display display = activity.getWindowManager().getDefaultDisplay();
            int rotation = display.getRotation();
            boolean isLandscape = (rotation == Surface.ROTATION_90 || rotation == Surface.ROTATION_270);
            
            Intent intent = new Intent();
            intent.setClassName(activity, "com.stash.popup.StashPayCardPortraitActivity");
            intent.putExtra("url", url);
            intent.putExtra("initialURL", url);
            intent.putExtra("cardHeightRatio", cardHeightRatio);
            intent.putExtra("usePopup", usePopupPresentation);
            intent.putExtra("wasLandscape", isLandscape);
            intent.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            
            activity.startActivity(intent);
            activity.overridePendingTransition(0, 0);
            isCurrentlyPresented = true;
            
            if (enableTimingLogs) {
                long launchTime = System.currentTimeMillis() - timingUIShowStart;
                Log.d(TAG, "⏱️ [TIMING] Activity launched in: " + launchTime + "ms");
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to launch Activity: " + e.getMessage());
        }
    }
    
    private class PopupOrientationListener implements ViewTreeObserver.OnGlobalLayoutListener {
        private final Activity activity;

        PopupOrientationListener(Activity activity) {
            this.activity = activity;
        }

        @Override
        public void onGlobalLayout() {
            try {
                if (currentContainer != null && currentDialog != null && currentDialog.isShowing() && activity != null) {
                    int currentOrientation = activity.getResources().getConfiguration().orientation;
                    
                    if (currentOrientation != lastOrientation && currentOrientation != Configuration.ORIENTATION_UNDEFINED) {
                        lastOrientation = currentOrientation;
                        
                        try {
                            int[] newDimensions = calculatePopupDimensions(activity);
                            FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) currentContainer.getLayoutParams();
                            
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
                                currentContainer.animate()
                                    .scaleX(0.95f)
                                    .scaleY(0.95f)
                                    .setDuration(100)
                                    .withEndAction(() -> {
                                        try {
                                            params.width = newDimensions[0];
                                            params.height = newDimensions[1];
                                            currentContainer.setLayoutParams(params);
                                            currentContainer.animate()
                                                .scaleX(1.0f)
                                                .scaleY(1.0f)
                                                .setDuration(200)
                                                .start();
                                        } catch (Exception e) {
                                            Log.e(TAG, "Error in animation end action: " + e.getMessage(), e);
                                        }
                                    })
                                    .start();
                            } else {
                                params.width = newDimensions[0];
                                params.height = newDimensions[1];
                                currentContainer.setLayoutParams(params);
                            }
                        } catch (Exception e) {
                            Log.e(TAG, "Error calculating or applying dimensions: " + e.getMessage(), e);
                        }
                    }
                }
            } catch (Exception e) {
                Log.e(TAG, "Error in onGlobalLayout: " + e.getMessage(), e);
            }
        }
    }

    private void createAndShowPopupDialog(String url, final Activity activity) {
        if (activity == null || url == null || url.isEmpty()) {
            Log.e(TAG, "Invalid activity or URL in createAndShowPopupDialog");
            return;
        }

        boolean preserveUseCustomSize = useCustomSize;
        cleanupAllViews();
        useCustomSize = preserveUseCustomSize;
        paymentSuccessHandled = false;

        try {
            currentDialog = new Dialog(activity, android.R.style.Theme_Translucent_NoTitleBar_Fullscreen);
            currentDialog.requestWindowFeature(Window.FEATURE_NO_TITLE);

            FrameLayout mainFrame = new FrameLayout(activity);
            try {
                mainFrame.setBackgroundColor(Color.parseColor(StashWebViewUtils.COLOR_BACKGROUND_DIM));
            } catch (Exception e) {
                Log.e(TAG, "Error setting background color: " + e.getMessage(), e);
                mainFrame.setBackgroundColor(Color.parseColor("#80000000"));
            }
            
            mainFrame.setOnClickListener(v -> {
                try {
                    if (!isPurchaseProcessing && currentDialog != null && currentDialog.isShowing() && v == mainFrame) {
                        currentDialog.dismiss();
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error in click handler: " + e.getMessage(), e);
                }
            });
            
            int[] dimensions;
            try {
                dimensions = calculatePopupDimensions(activity);
            } catch (Exception e) {
                Log.e(TAG, "Error calculating dimensions: " + e.getMessage(), e);
                DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
                dimensions = new int[]{
                    (int)(metrics.widthPixels * 0.9f),
                    (int)(metrics.heightPixels * 0.7f)
                };
            }
            
            currentContainer = new FrameLayout(activity);
            FrameLayout.LayoutParams containerParams = new FrameLayout.LayoutParams(dimensions[0], dimensions[1]);
            containerParams.gravity = Gravity.CENTER;
            currentContainer.setLayoutParams(containerParams);
            
            try {
                lastOrientation = activity.getResources().getConfiguration().orientation;
            } catch (Exception e) {
                Log.e(TAG, "Error getting orientation: " + e.getMessage(), e);
                lastOrientation = Configuration.ORIENTATION_PORTRAIT;
            }
            
            orientationChangeListener = new PopupOrientationListener(activity);
            try {
                mainFrame.getViewTreeObserver().addOnGlobalLayoutListener(orientationChangeListener);
            } catch (Exception e) {
                Log.e(TAG, "Error adding layout listener: " + e.getMessage(), e);
            }
            
            try {
                GradientDrawable popupBg = new GradientDrawable();
                popupBg.setColor(StashWebViewUtils.getThemeBackgroundColor(activity));
                float radius = StashWebViewUtils.dpToPx(activity, 12);
                popupBg.setCornerRadius(radius);
                currentContainer.setBackground(popupBg);
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    // Reduce elevation on low-end devices
                    boolean isVeryLowEnd = StashWebViewUtils.isVeryLowEndDevice(activity);
                    float elevation = isVeryLowEnd ? 
                        StashWebViewUtils.dpToPx(activity, 8) : // Reduced from 24dp
                        StashWebViewUtils.dpToPx(activity, 24);
                    currentContainer.setElevation(elevation);
                    
                    // Simplify corner radius on very low-end (reduce complexity)
                    if (!isVeryLowEnd) {
                        currentContainer.setOutlineProvider(new ViewOutlineProvider() {
                            @Override
                            public void getOutline(View view, Outline outline) {
                                try {
                                    outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), radius);
                                } catch (Exception e) {
                                    Log.e(TAG, "Error setting outline: " + e.getMessage(), e);
                                }
                            }
                        });
                        currentContainer.setClipToOutline(true);
                    }
                }
            } catch (Exception e) {
                Log.e(TAG, "Error setting container background: " + e.getMessage(), e);
            }
            
            try {
                // Reuse pre-warmed WebView if available, otherwise create new
                webView = getOrCreateWebView(activity);
                FrameLayout.LayoutParams webViewParams = new FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
                webView.setLayoutParams(webViewParams);
                currentContainer.addView(webView);
                
                setupPopupWebView(webView, url, activity);
            } catch (Exception e) {
                Log.e(TAG, "Error creating WebView: " + e.getMessage(), e);
                cleanupAllViews();
                return;
            }
            
            mainFrame.addView(currentContainer);
            currentDialog.setContentView(mainFrame);

            Window window = currentDialog.getWindow();
            if (window != null) {
                try {
                    window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
                    window.setFlags(WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                                   WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED);
                    window.setBackgroundDrawableResource(android.R.color.transparent);
                    window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
                    WindowManager.LayoutParams windowParams = window.getAttributes();
                    windowParams.dimAmount = 0.3f;
                    window.setAttributes(windowParams);
                } catch (Exception e) {
                    Log.e(TAG, "Error configuring window: " + e.getMessage(), e);
                }
            }
            
            currentContainer.setOnClickListener(v -> {});
            
            currentDialog.setCanceledOnTouchOutside(!isPurchaseProcessing);
            currentDialog.setCancelable(!isPurchaseProcessing);

            currentDialog.setOnDismissListener(dialog -> {
                try {
                    if (!paymentSuccessHandled && listener != null) {
                        listener.onDialogDismissed();
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error in dismiss listener: " + e.getMessage(), e);
                }
                cleanupAllViews();
                isCurrentlyPresented = false;
            });
            
            try {
                currentDialog.show();
                animateFadeIn();
                isCurrentlyPresented = true;
            } catch (Exception e) {
                Log.e(TAG, "Error showing dialog: " + e.getMessage(), e);
                cleanupAllViews();
            }
        } catch (Exception e) {
            Log.e(TAG, "Error creating popup: " + e.getMessage(), e);
            cleanupAllViews();
        }
    }
    
    private void animateFadeIn() {
        try {
            if (currentContainer != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
                // Skip animation on very low-end devices for faster display
                boolean isVeryLowEnd = activity != null && StashWebViewUtils.isVeryLowEndDevice(activity);
                
                if (isVeryLowEnd) {
                    // Show immediately without animation
                    currentContainer.setAlpha(1.0f);
                    currentContainer.setScaleX(1.0f);
                    currentContainer.setScaleY(1.0f);
                } else {
                    currentContainer.setAlpha(0.0f);
                    currentContainer.setScaleX(0.9f);
                    currentContainer.setScaleY(0.9f);
                    currentContainer.animate()
                        .alpha(1.0f)
                        .scaleX(1.0f)
                        .scaleY(1.0f)
                        .setDuration(200)
                        .setInterpolator(new android.view.animation.AccelerateDecelerateInterpolator())
                        .start();
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Error in animateFadeIn: " + e.getMessage(), e);
        }
    }
    
    private void dismissPopupDialog() {
        try {
            if (currentDialog != null && currentContainer != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
                    currentContainer.animate()
                        .alpha(0.0f)
                        .scaleX(0.9f)
                        .scaleY(0.9f)
                        .setDuration(250)
                        .setInterpolator(new SpringInterpolator())
                        .withEndAction(() -> {
                            try {
                                if (currentDialog != null) currentDialog.dismiss();
                            } catch (Exception e) {
                                Log.e(TAG, "Error dismissing dialog in animation: " + e.getMessage(), e);
                            }
                        })
                        .start();
                } else {
                    currentDialog.dismiss();
                }
            } else if (currentDialog != null) {
                currentDialog.dismiss();
            }
        } catch (Exception e) {
            Log.e(TAG, "Error in dismissPopupDialog: " + e.getMessage(), e);
            try {
                if (currentDialog != null) {
                    currentDialog.dismiss();
                }
            } catch (Exception e2) {
                Log.e(TAG, "Error force dismissing dialog: " + e2.getMessage(), e2);
            }
        }
    }
    
    private void setupPopupWebView(WebView webView, String url, final Activity activity) {
        if (webView == null || activity == null || url == null || url.isEmpty()) {
            Log.e(TAG, "Invalid parameters in setupPopupWebView");
            return;
        }

        try {
            boolean isDark = StashWebViewUtils.isDarkTheme(activity);
            boolean isLowEnd = StashWebViewUtils.isLowEndDevice() || StashWebViewUtils.isVeryLowEndDevice(activity);
            StashWebViewUtils.configureWebViewSettings(webView, isDark, isLowEnd);
            
            // Re-enable images after page starts loading (low-end optimization)
            if (isLowEnd && Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                webView.postDelayed(() -> {
                    try {
                        webView.getSettings().setLoadsImagesAutomatically(true);
                    } catch (Exception e) {
                        Log.e(TAG, "Error re-enabling images: " + e.getMessage(), e);
                    }
                }, 1000); // Enable images after 1 second
            }
        } catch (Exception e) {
            Log.e(TAG, "Error configuring WebView settings: " + e.getMessage(), e);
        }
        
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
                try {
                    super.onPageStarted(view, url, favicon);
                    pageLoadStartTime = System.currentTimeMillis();
                    showLoadingIndicator(activity);
                    injectStashSDKFunctions();
                } catch (Exception e) {
                    Log.e(TAG, "Error in onPageStarted: " + e.getMessage(), e);
                }
            }
            
            @Override
            public void onPageFinished(WebView view, String url) {
                try {
                    super.onPageFinished(view, url);
                    
                    if (pageLoadStartTime > 0) {
                        long loadTimeMs = System.currentTimeMillis() - pageLoadStartTime;
                        try {
                            if (listener != null) {
                                listener.onPageLoaded(loadTimeMs);
                            }
                        } catch (Exception e) {
                            Log.e(TAG, "Error sending page loaded message: " + e.getMessage(), e);
                        }
                        
                        if (enableTimingLogs && timingStartTime > 0) {
                            long totalTime = System.currentTimeMillis() - timingStartTime;
                            Log.d(TAG, "⏱️ [TIMING] ⭐ TOTAL TIME (openCheckout to page loaded): " + totalTime + "ms");
                        }
                        
                        pageLoadStartTime = 0;
                    }
                    
                    injectStashSDKFunctions();
                    view.postDelayed(() -> {
                        try {
                            hideLoadingIndicator(activity);
                            view.setVisibility(View.VISIBLE);
                        } catch (Exception e) {
                            Log.e(TAG, "Error in delayed page finished handler: " + e.getMessage(), e);
                        }
                    }, 300);
                } catch (Exception e) {
                    Log.e(TAG, "Error in onPageFinished: " + e.getMessage(), e);
                }
            }
            
            @Override
            public void onReceivedError(WebView view, android.webkit.WebResourceRequest request, 
                                        android.webkit.WebResourceError error) {
                try {
                    super.onReceivedError(view, request, error);
                    if (error != null) {
                        Log.e(TAG, "WebView error: " + error.getDescription());
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error in onReceivedError: " + e.getMessage(), e);
                }
            }
        });
        
        try {
            webView.setWebChromeClient(new WebChromeClient());
            webView.addJavascriptInterface(new StashJavaScriptInterface(), "StashAndroid");
            webView.setVerticalScrollBarEnabled(false);
            webView.setHorizontalScrollBarEnabled(false);
            webView.setBackgroundColor(Color.TRANSPARENT);
            webView.loadUrl(url);
        } catch (Exception e) {
            Log.e(TAG, "Error setting up WebView: " + e.getMessage(), e);
            cleanupAllViews();
        }
    }
    
    private void injectStashSDKFunctions() {
        if (webView == null) return;
        
        try {
            webView.evaluateJavascript(StashWebViewUtils.JS_SDK_SCRIPT, null);
        } catch (Exception e) {
            Log.e(TAG, "Error injecting SDK functions: " + e.getMessage(), e);
        }
    }
    
    private void showLoadingIndicator(Activity activity) {
        if (currentContainer == null || activity == null) return;
        try {
            activity.runOnUiThread(() -> {
                try {
                    if (loadingIndicator != null && loadingIndicator.getParent() != null) {
                        ((ViewGroup)loadingIndicator.getParent()).removeView(loadingIndicator);
                    }
                    loadingIndicator = StashWebViewUtils.createAndShowLoading(activity, currentContainer);
                } catch (Exception e) {
                    Log.e(TAG, "Error showing loading indicator: " + e.getMessage(), e);
                }
            });
        } catch (Exception e) {
            Log.e(TAG, "Error scheduling loading indicator: " + e.getMessage(), e);
        }
    }
    
    private void hideLoadingIndicator(Activity activity) {
        if (loadingIndicator == null || activity == null) return;
        try {
            activity.runOnUiThread(() -> {
                try {
                    StashWebViewUtils.hideLoading(loadingIndicator);
                    loadingIndicator = null;
                } catch (Exception e) {
                    Log.e(TAG, "Error hiding loading indicator: " + e.getMessage(), e);
                    loadingIndicator = null;
                }
            });
        } catch (Exception e) {
            Log.e(TAG, "Error scheduling hide loading indicator: " + e.getMessage(), e);
        }
    }
    
    private void openWithChromeCustomTabs(String url, Activity activity) {
        try {
            if (isChromeCustomTabsAvailable()) {
                Log.d(TAG, "Opening URL with Chrome Custom Tabs");
                openWithReflectionChromeCustomTabs(url, activity);
            } else {
                Log.w(TAG, "Chrome Custom Tabs not available. Falling back to default browser.");
                openWithDefaultBrowser(url, activity);
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to open browser: " + e.getMessage());
            try {
                openWithDefaultBrowser(url, activity);
            } catch (Exception fallbackException) {
                Log.e(TAG, "Failed to open default browser: " + fallbackException.getMessage());
            }
        }
    }
    
    private boolean isChromeCustomTabsAvailable() {
        try {
            Class.forName("androidx.browser.customtabs.CustomTabsIntent");
            return true;
        } catch (ClassNotFoundException e) {
            return false;
        }
    }
    
    private void openWithReflectionChromeCustomTabs(String url, Activity activity) throws Exception {
        if (activity == null || url == null || url.isEmpty()) {
            throw new IllegalArgumentException("Invalid activity or URL");
        }

        Class<?> customTabsIntentClass = Class.forName("androidx.browser.customtabs.CustomTabsIntent");
        Class<?> builderClass = Class.forName("androidx.browser.customtabs.CustomTabsIntent$Builder");

        Object builder = builderClass.newInstance();
        java.lang.reflect.Method setToolbarColor = builderClass.getMethod("setToolbarColor", int.class);
        setToolbarColor.invoke(builder, Color.parseColor("#000000"));

        java.lang.reflect.Method setShowTitle = builderClass.getMethod("setShowTitle", boolean.class);
        setShowTitle.invoke(builder, true);

        java.lang.reflect.Method build = builderClass.getMethod("build");
        Object customTabsIntent = build.invoke(builder);

        java.lang.reflect.Method launchUrl = customTabsIntentClass.getMethod("launchUrl", 
            android.content.Context.class, Uri.class);
        launchUrl.invoke(customTabsIntent, activity, Uri.parse(url));

        isCurrentlyPresented = true;
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            try {
                if (listener != null) {
                    listener.onDialogDismissed();
                }
            } catch (Exception e) {
                Log.e(TAG, "Error sending dialog dismissed: " + e.getMessage(), e);
            }
        }, 1000);
    }
    
    private void openWithDefaultBrowser(String url, Activity activity) {
        if (activity == null || url == null || url.isEmpty()) {
            Log.e(TAG, "Invalid activity or URL in openWithDefaultBrowser");
            return;
        }

        try {
            Intent browserIntent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
            browserIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            activity.startActivity(browserIntent);
            isCurrentlyPresented = true;

            new Handler(Looper.getMainLooper()).postDelayed(() -> {
                try {
                    if (listener != null) {
                        listener.onDialogDismissed();
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error sending dialog dismissed: " + e.getMessage(), e);
                }
            }, 1000);
        } catch (Exception e) {
            Log.e(TAG, "Error opening default browser: " + e.getMessage(), e);
            isCurrentlyPresented = false;
        }
    }
    
    private void dismissCurrentDialog() {
        try {
            if (currentDialog != null) {
                dismissPopupDialog();
            }
        } catch (Exception e) {
            Log.e(TAG, "Error in dismissCurrentDialog: " + e.getMessage(), e);
            cleanupAllViews();
        }
    }
    
    private void cleanupAllViews() {
        try {
            if (loadingIndicator != null) {
                try {
                    if (loadingIndicator.getParent() != null) {
                        ((ViewGroup)loadingIndicator.getParent()).removeView(loadingIndicator);
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error cleaning up loading indicator: " + e.getMessage());
                }
                loadingIndicator = null;
            }
            
            if (currentDialog != null) {
                if (currentDialog.isShowing()) {
                    currentDialog.dismiss();
                }
                currentDialog = null;
            }
            
            if (webView != null) {
                try {
                    if (webView.getParent() != null) {
                        ((ViewGroup)webView.getParent()).removeView(webView);
                    }
                    webView.stopLoading();
                    webView.destroy();
                } catch (Exception e) {
                    Log.e(TAG, "Error cleaning up WebView: " + e.getMessage());
                }
                webView = null;
            }
            
            // Don't clean up pre-warmed WebView here - it should persist for reuse
            // Only clean it up if it's not being used (it will be null if already used)
            if (preWarmedWebView != null && preWarmedWebView != webView) {
                // Pre-warmed WebView exists but wasn't used - keep it for next time
                // Don't clean it up
            }
            
            // Re-pre-warm WebView for next use (if enabled and not already pre-warmed)
            rePreWarmWebViewIfNeeded();
            
            if (currentContainer != null) {
                try {
                    if (orientationChangeListener != null && currentContainer.getParent() != null) {
                        View parent = (View) currentContainer.getParent();
                        if (parent.getViewTreeObserver().isAlive()) {
                            parent.getViewTreeObserver().removeOnGlobalLayoutListener(orientationChangeListener);
                        }
                    }
                    if (currentContainer.getParent() != null) {
                        ((ViewGroup)currentContainer.getParent()).removeView(currentContainer);
                    }
                    currentContainer.removeAllViews();
                } catch (Exception e) {
                    Log.e(TAG, "Error cleaning up container: " + e.getMessage());
                }
                currentContainer = null;
            }
            
            orientationChangeListener = null;
        } catch (Exception e) {
            Log.e(TAG, "Error during cleanup: " + e.getMessage());
        }
        
        isPurchaseProcessing = false;
        usePopupPresentation = false;
    }
    
    private int[] calculatePopupDimensions(Activity activity) {
        if (activity == null) {
            Log.e(TAG, "Activity is null in calculatePopupDimensions");
            return new int[]{800, 600};
        }

        try {
            DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
            boolean isLandscape = activity.getResources().getConfiguration().orientation == Configuration.ORIENTATION_LANDSCAPE;
            
            int smallerDimension = Math.min(metrics.widthPixels, metrics.heightPixels);
            boolean isTablet = StashWebViewUtils.isTablet(activity);
            int baseSize = Math.max(
                isTablet ? StashWebViewUtils.dpToPx(activity, 400) : StashWebViewUtils.dpToPx(activity, 300),
                Math.min(isTablet ? StashWebViewUtils.dpToPx(activity, 500) : StashWebViewUtils.dpToPx(activity, 500), (int)(smallerDimension * (isTablet ? 0.5f : 0.75f)))
            );
            
            float widthMultiplier = isLandscape ? 
                (useCustomSize ? customLandscapeWidthMultiplier : 1.2275445f) :
                (useCustomSize ? customPortraitWidthMultiplier : 1.0285f);
            float heightMultiplier = isLandscape ? 
                (useCustomSize ? customLandscapeHeightMultiplier : 1.1385f) :
                (useCustomSize ? customPortraitHeightMultiplier : 1.485f);

            int popupWidth = (int)(baseSize * widthMultiplier);
            int popupHeight = (int)(baseSize * heightMultiplier);

            return new int[]{popupWidth, popupHeight};
        } catch (Exception e) {
            Log.e(TAG, "Error calculating popup dimensions: " + e.getMessage(), e);
            try {
                DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
                return new int[]{
                    (int)(metrics.widthPixels * 0.9f),
                    (int)(metrics.heightPixels * 0.7f)
                };
            } catch (Exception e2) {
                Log.e(TAG, "Error getting fallback dimensions: " + e2.getMessage(), e2);
                return new int[]{800, 600};
            }
        }
    }
}
