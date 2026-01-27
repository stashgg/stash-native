package com.stash.popup;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.Context;
import android.content.res.Configuration;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.widget.FrameLayout;
import android.widget.ProgressBar;

/**
 * Utility class for WebView configuration and common operations.
 */
public class StashWebViewUtils {
    private static final String TAG = "StashWebViewUtils";
    
    public static final String COLOR_BACKGROUND_DIM = "#20000000";
    public static final String COLOR_DARK_BG = "#1C1C1E";
    
    public static final String JS_SDK_SCRIPT = "(function() {" +
        "  window.stash_sdk = window.stash_sdk || {};" +
        "  window.stash_sdk.onPaymentSuccess = function(data) {" +
        "    try { StashAndroid.onPaymentSuccess(); } catch(e) {}" +
        "  };" +
        "  window.stash_sdk.onPaymentFailure = function(data) {" +
        "    try { StashAndroid.onPaymentFailure(); } catch(e) {}" +
        "  };" +
        "  window.stash_sdk.onPurchaseProcessing = function(data) {" +
        "    try { StashAndroid.onPurchaseProcessing(); } catch(e) {}" +
        "  };" +
        "  window.stash_sdk.setPaymentChannel = function(optinType) {" +
        "    try { StashAndroid.setPaymentChannel(optinType || ''); } catch(e) {}" +
        "  };" +
        "  window.stash_sdk.expand = function() {" +
        "    try { StashAndroid.expand(); } catch(e) {}" +
        "  };" +
        "  window.stash_sdk.collapse = function() {" +
        "    try { StashAndroid.collapse(); } catch(e) {}" +
        "  };" +
        "})();";

    public static boolean isDarkTheme(Context context) {
        if (context == null) return false;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            int nightModeFlags = context.getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK;
            return nightModeFlags == Configuration.UI_MODE_NIGHT_YES;
        }
        return false;
    }

    public static int dpToPx(Context context, int dp) {
        if (context == null) return 0;
        return Math.round(dp * context.getResources().getDisplayMetrics().density);
    }

    public static boolean isTablet(Activity activity) {
        if (activity == null) return false;
        DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
        int smallerDimension = Math.min(metrics.widthPixels, metrics.heightPixels);
        float smallerDp = smallerDimension / metrics.density;
        
        boolean isTabletBySize = smallerDp >= 600;
        
        boolean isTabletByConfig = false;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB_MR2) {
            int screenSize = activity.getResources().getConfiguration().screenLayout & Configuration.SCREENLAYOUT_SIZE_MASK;
            isTabletByConfig = (screenSize == Configuration.SCREENLAYOUT_SIZE_LARGE || 
                               screenSize == Configuration.SCREENLAYOUT_SIZE_XLARGE);
        }
        
        float aspectRatio = (float)Math.max(metrics.widthPixels, metrics.heightPixels) / 
                           Math.min(metrics.widthPixels, metrics.heightPixels);
        boolean isTabletByAspect = aspectRatio < 2.0f && smallerDp >= 500;
        
        return isTabletBySize || isTabletByConfig || isTabletByAspect;
    }

    public static void configureWebViewSettings(WebView webView, boolean isDarkTheme) {
        if (webView == null) return;
        WebSettings settings = webView.getSettings();
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);
        settings.setBuiltInZoomControls(false);
        settings.setDisplayZoomControls(false);
        settings.setSupportZoom(false);
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true);
        }
        CookieManager.getInstance().setAcceptCookie(true);
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            settings.setForceDark(isDarkTheme ? WebSettings.FORCE_DARK_ON : WebSettings.FORCE_DARK_OFF);
        }
    }

    public static String appendThemeQueryParameter(String url, boolean isDarkTheme) {
        if (url == null || url.isEmpty()) {
            return url;
        }
        
        // Optimize: Fast path - check if theme already exists (saves Uri parsing)
        String themeLower = "theme=";
        int themeIndex = url.toLowerCase().indexOf(themeLower);
        if (themeIndex >= 0) {
            // Theme already exists, skip appending
            return url;
        }
        
        try {
            // Optimize: Use indexOf instead of contains (faster)
            String separator = url.indexOf('?') >= 0 ? "&" : "?";
            String theme = isDarkTheme ? "dark" : "light";
            return url + separator + "theme=" + theme;
        } catch (Exception e) {
            Log.e(TAG, "Error appending theme parameter: " + e.getMessage());
            // Fallback: simple string concatenation
            String separator = url.indexOf('?') >= 0 ? "&" : "?";
            String theme = isDarkTheme ? "dark" : "light";
            return url + separator + "theme=" + theme;
        }
    }
    
    /**
     * Extracts the base URL (scheme + authority) from a full URL.
     * Example: "https://example.com/path?query=1" -> "https://example.com"
     * 
     * @param url The full URL
     * @return The base URL, or null if parsing fails
     */
    public static String extractBaseUrl(String url) {
        if (url == null || url.isEmpty()) {
            return null;
        }
        
        try {
            Uri uri = Uri.parse(url);
            String scheme = uri.getScheme();
            String authority = uri.getAuthority();
            
            if (scheme != null && authority != null) {
                return scheme + "://" + authority;
            }
            return null;
        } catch (Exception e) {
            Log.e(TAG, "Error extracting base URL: " + e.getMessage());
            return null;
        }
    }

    public static int getThemeBackgroundColor(Context context) {
        if (context == null) return Color.WHITE;
        return isDarkTheme(context) ? Color.parseColor(COLOR_DARK_BG) : Color.WHITE;
    }

    public static ProgressBar createAndShowLoading(Context context, ViewGroup container) {
        if (context == null || container == null) return null;
        
        try {
            ProgressBar loadingIndicator = new ProgressBar(context);
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
                loadingIndicator.setLayerType(View.LAYER_TYPE_HARDWARE, null);
            }
            
            loadingIndicator.setIndeterminate(true);
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                loadingIndicator.setIndeterminateTintList(
                    android.content.res.ColorStateList.valueOf(isDarkTheme(context) ? Color.WHITE : Color.DKGRAY));
            }
            
            FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(dpToPx(context, 48), dpToPx(context, 48));
            params.gravity = Gravity.CENTER;
            loadingIndicator.setLayoutParams(params);
            
            container.addView(loadingIndicator);
            loadingIndicator.bringToFront();
            
            return loadingIndicator;
        } catch (Exception e) {
            Log.e(TAG, "Error showing loading: " + e.getMessage());
            return null;
        }
    }

    public static void hideLoading(final ProgressBar loadingIndicator) {
        if (loadingIndicator == null) return;
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
            loadingIndicator.animate()
                .alpha(0.0f)
                .setDuration(200)
                .withEndAction(() -> {
                    if (loadingIndicator.getParent() != null) {
                        ((ViewGroup)loadingIndicator.getParent()).removeView(loadingIndicator);
                    }
                })
                .start();
        } else {
            if (loadingIndicator.getParent() != null) {
                ((ViewGroup)loadingIndicator.getParent()).removeView(loadingIndicator);
            }
        }
    }
    
    /**
     * Checks if the device has sufficient memory for WebView pre-warming.
     * WebView instances can consume 20-50MB+, so we only pre-warm on devices
     * with at least 2GB total RAM and 200MB available.
     * 
     * @param context The context to check memory
     * @return true if device has sufficient memory for pre-warming
     */
    public static boolean hasSufficientMemoryForPreWarming(Context context) {
        if (context == null) return false;
        
        try {
            android.app.ActivityManager.MemoryInfo memInfo = new android.app.ActivityManager.MemoryInfo();
            android.app.ActivityManager activityManager = (android.app.ActivityManager) 
                context.getSystemService(Context.ACTIVITY_SERVICE);
            
            if (activityManager == null) return false;
            
            activityManager.getMemoryInfo(memInfo);
            
            // Check total RAM (in bytes)
            long totalRam = 0;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
                totalRam = memInfo.totalMem;
            } else {
                // Fallback for older devices - check system property
                try {
                    java.io.BufferedReader reader = new java.io.BufferedReader(
                        new java.io.FileReader("/proc/meminfo"));
                    String line = reader.readLine();
                    reader.close();
                    if (line != null) {
                        String[] parts = line.split("\\s+");
                        if (parts.length >= 2) {
                            totalRam = Long.parseLong(parts[1]) * 1024; // Convert KB to bytes
                        }
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error reading meminfo: " + e.getMessage());
                }
            }
            
            // Require at least 2GB total RAM
            long minTotalRam = 2L * 1024 * 1024 * 1024; // 2GB in bytes
            if (totalRam < minTotalRam) {
                Log.d(TAG, "Device has insufficient total RAM for pre-warming: " + 
                    (totalRam / (1024 * 1024)) + "MB");
                return false;
            }
            
            // Require at least 200MB available memory
            long availableMem = memInfo.availMem;
            long minAvailableMem = 200L * 1024 * 1024; // 200MB in bytes
            
            if (availableMem < minAvailableMem) {
                Log.d(TAG, "Device has insufficient available memory for pre-warming: " + 
                    (availableMem / (1024 * 1024)) + "MB");
                return false;
            }
            
            // Check if device is low on memory
            if (memInfo.lowMemory) {
                Log.d(TAG, "Device is low on memory, skipping pre-warming");
                return false;
            }
            
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Error checking memory: " + e.getMessage());
            // Fail safe: don't pre-warm if we can't check memory
            return false;
        }
    }
    
    /**
     * Checks if device is considered "low-end" based on RAM and API level.
     * Low-end devices should avoid pre-warming to prevent OOM errors.
     * 
     * @return true if device is considered low-end
     */
    public static boolean isLowEndDevice() {
        try {
            // Devices with Android 5.0-6.0 (API 21-23) are more likely to be low-end
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
                return true;
            }
            
            // Additional checks can be added here (e.g., CPU cores, screen size)
            return false;
        } catch (Exception e) {
            Log.e(TAG, "Error checking device type: " + e.getMessage());
            // Fail safe: assume low-end if we can't determine
            return true;
        }
    }
    
    /**
     * Checks if device is very low-end (needs aggressive optimizations).
     * Based on RAM, API level, and available memory.
     * 
     * @param context The context to check
     * @return true if device needs aggressive optimizations
     */
    public static boolean isVeryLowEndDevice(Context context) {
        if (context == null) return true; // Fail safe
        
        try {
            // Android < 7.0 is considered very low-end
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
                return true;
            }
            
            // Check total RAM
            android.app.ActivityManager.MemoryInfo memInfo = new android.app.ActivityManager.MemoryInfo();
            android.app.ActivityManager activityManager = (android.app.ActivityManager) 
                context.getSystemService(Context.ACTIVITY_SERVICE);
            
            if (activityManager == null) return true;
            activityManager.getMemoryInfo(memInfo);
            
            long totalRam = 0;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
                totalRam = memInfo.totalMem;
            }
            
            // Very low-end: < 1.5GB RAM
            long minRam = 1536L * 1024 * 1024; // 1.5GB
            if (totalRam > 0 && totalRam < minRam) {
                return true;
            }
            
            // Very low-end: < 100MB available memory
            if (memInfo.availMem < 100L * 1024 * 1024) {
                return true;
            }
            
            // Very low-end: System reports low memory
            if (memInfo.lowMemory) {
                return true;
            }
            
            return false;
        } catch (Exception e) {
            Log.e(TAG, "Error checking very low-end device: " + e.getMessage(), e);
            return true; // Fail safe
        }
    }
    
    /**
     * Configures WebView settings optimized for low-end devices.
     * Disables non-essential features to improve performance.
     * 
     * @param webView The WebView to configure
     * @param isDarkTheme Whether dark theme is enabled
     * @param isLowEnd Whether device is low-end (enables optimizations)
     */
    public static void configureWebViewSettings(WebView webView, boolean isDarkTheme, boolean isLowEnd) {
        if (webView == null) return;
        WebSettings settings = webView.getSettings();
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);
        settings.setBuiltInZoomControls(false);
        settings.setDisplayZoomControls(false);
        settings.setSupportZoom(false);
        
        // Low-end optimizations
        if (isLowEnd) {
            // Disable image loading initially (can be enabled after page loads)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                settings.setLoadsImagesAutomatically(false);
            }
            
            // Reduce cache size
            settings.setCacheMode(WebSettings.LOAD_DEFAULT);
            
            // Disable database storage (saves memory)
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.KITKAT) {
                settings.setDatabaseEnabled(false);
            }
            
            // Disable geolocation
            settings.setGeolocationEnabled(false);
            
            // Additional optimizations for low-memory devices
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                // Disable mixed content (saves processing)
                settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
            }
            
            // Disable safe browsing (saves network requests and processing)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                settings.setSafeBrowsingEnabled(false);
            }
            
            // Disable media playback (saves resources)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
                settings.setMediaPlaybackRequiresUserGesture(true);
            }
            
            // Use minimal rendering mode (Android 7.0+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                settings.setRenderPriority(WebSettings.RenderPriority.HIGH);
            }
        } else {
            // Normal settings for capable devices
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                settings.setLoadsImagesAutomatically(true);
            }
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true);
        }
        CookieManager.getInstance().setAcceptCookie(true);
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            settings.setForceDark(isDarkTheme ? WebSettings.FORCE_DARK_ON : WebSettings.FORCE_DARK_OFF);
        }
    }
    
    /**
     * Generates a structural stub HTML page that matches the checkout page layout.
     * This provides instant visual feedback with the actual page structure, then gets
     * replaced by the real page content when it loads. Works even when pre-warming is disabled.
     * 
     * @param isDarkTheme Whether to use dark theme styling
     * @return HTML string for the structural stub page
     */
    public static String generateStubLoadingPage(boolean isDarkTheme) {
        String bgColor = isDarkTheme ? COLOR_DARK_BG : "#FFFFFF";
        String textColor = isDarkTheme ? "#FFFFFF" : "#000000";
        String cardBg = isDarkTheme ? "#2C2C2E" : "#F2F2F7";
        String borderColor = isDarkTheme ? "#38383A" : "#E5E5EA";
        String skeletonColor = isDarkTheme ? "#3A3A3C" : "#E0E0E0";
        String skeletonShimmer = isDarkTheme ? "#4A4A4C" : "#F0F0F0";
        
        return "<!DOCTYPE html>" +
            "<html><head>" +
            "<meta charset='utf-8'>" +
            "<meta name='viewport' content='width=device-width, initial-scale=1.0'>" +
            "<title>Loading...</title>" +
            "<style>" +
            "* { box-sizing: border-box; }" +
            "body { margin: 0; padding: 16px; background: " + bgColor + "; color: " + textColor + "; " +
            "font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; " +
            "min-height: 100vh; }" +
            ".container { max-width: 600px; margin: 0 auto; }" +
            ".card { background: " + cardBg + "; border-radius: 12px; padding: 24px; margin-bottom: 16px; " +
            "border: 1px solid " + borderColor + "; }" +
            ".skeleton { background: linear-gradient(90deg, " + skeletonColor + " 25%, " + skeletonShimmer + " 50%, " + skeletonColor + " 75%); " +
            "background-size: 200% 100%; animation: shimmer 1.5s infinite; border-radius: 8px; }" +
            ".skeleton-title { height: 24px; width: 60%; margin-bottom: 16px; }" +
            ".skeleton-text { height: 16px; width: 100%; margin-bottom: 12px; }" +
            ".skeleton-text.short { width: 80%; }" +
            ".skeleton-button { height: 48px; width: 100%; margin-top: 24px; border-radius: 8px; }" +
            ".skeleton-line { height: 1px; width: 100%; margin: 16px 0; background: " + borderColor + "; }" +
            "@keyframes shimmer { 0% { background-position: -200% 0; } 100% { background-position: 200% 0; } }" +
            "</style></head><body>" +
            "<div class='container'>" +
            "<div class='card'>" +
            "<div class='skeleton skeleton-title'></div>" +
            "<div class='skeleton skeleton-text'></div>" +
            "<div class='skeleton skeleton-text short'></div>" +
            "<div class='skeleton-line'></div>" +
            "<div class='skeleton skeleton-text'></div>" +
            "<div class='skeleton skeleton-text short'></div>" +
            "<div class='skeleton skeleton-button'></div>" +
            "</div>" +
            "</div>" +
            "<script>" +
            "// This stub will be automatically replaced when real page loads" +
            "// The WebView navigation will replace this content seamlessly" +
            "</script>" +
            "</body></html>";
    }
}
