package com.stash.popup;

import android.animation.ValueAnimator;
import android.app.Activity;
import android.app.ActivityManager;
import android.app.Application;
import android.app.Dialog;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import com.stash.popup.keepalive.StashKeepAliveManager;
import android.graphics.Color;
import android.graphics.Outline;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Gravity;
import android.view.MotionEvent;
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
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.net.Uri;

import java.lang.ref.WeakReference;

/**
 * Internal plugin class that handles the WebView and dialog management.
 * Use {@link StashPayCard} for the public API.
 * 
 * Memory optimization: Uses WeakReference for Activity to prevent leaks.
 */
public class StashPayCardPlugin {
    private static final String TAG = "StashPayCard";

    /** Thread-safe lazy singleton holder. */
    private static class Holder {
        static final StashPayCardPlugin INSTANCE = new StashPayCardPlugin();
    }
    
    // Use WeakReference to prevent Activity memory leaks
    private WeakReference<Activity> activityRef;
    private StashPayCard.StashPayListener listener;

    private Dialog currentDialog;
    private WebView webView;
    private FrameLayout currentContainer;
    private ProgressBar loadingIndicator;
    private ViewTreeObserver.OnGlobalLayoutListener orientationChangeListener;
    
    // Phone card: only height is configurable in portrait (full width); landscape ratios when not forcing portrait
    private float cardHeightRatioPortrait = CardConstants.DEFAULT_CARD_HEIGHT_RATIO;
    private boolean forcePortraitOnCheckout = false;
    private float cardWidthRatioLandscape = CardConstants.DEFAULT_CARD_WIDTH_RATIO_LANDSCAPE;
    private float cardHeightRatioLandscape = CardConstants.DEFAULT_CARD_HEIGHT_RATIO_LANDSCAPE;
    
    // Orientation-specific tablet card configuration
    private float tabletWidthRatioPortrait = CardConstants.DEFAULT_TABLET_WIDTH_RATIO_PORTRAIT;
    private float tabletHeightRatioPortrait = CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_PORTRAIT;
    private float tabletWidthRatioLandscape = CardConstants.DEFAULT_TABLET_WIDTH_RATIO_LANDSCAPE;
    private float tabletHeightRatioLandscape = CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_LANDSCAPE;
    
    /** Accessed from UI and JS threads; volatile for visibility. */
    private volatile boolean isCurrentlyPresented;
    /** Accessed from UI and JS threads; volatile for visibility. */
    private volatile boolean paymentSuccessHandled;
    /** Accessed from UI and JS threads; volatile for visibility. */
    private volatile boolean isPurchaseProcessing;
    private boolean usePopupPresentation;
    private boolean useModalPresentation;
    private boolean useCheckoutOverlayPresentation;
    /** When true, checkout overlay (no force portrait) is expanded to ~95% height. Reset on rotation. */
    private boolean isCheckoutOverlayExpanded = false;
    private boolean forceSafariViewController;
    private int lastOrientation = Configuration.ORIENTATION_UNDEFINED;
    
    // Modal configuration (used when useModalPresentation is true)
    private StashPayCard.ModalConfig currentModalConfig;
    
    private boolean useCustomSize;
    private float customPortraitWidthMultiplier = CardConstants.POPUP_PORTRAIT_WIDTH_MULTIPLIER;
    private float customPortraitHeightMultiplier = CardConstants.POPUP_PORTRAIT_HEIGHT_MULTIPLIER;
    private float customLandscapeWidthMultiplier = CardConstants.POPUP_LANDSCAPE_WIDTH_MULTIPLIER;
    private float customLandscapeHeightMultiplier = CardConstants.POPUP_LANDSCAPE_HEIGHT_MULTIPLIER;
    
    private long pageLoadStartTime;
    
    /**
     * Runs the given runnable on the main thread if activity is available. No-op if activity is null.
     */
    private void runOnMainSafely(Runnable r) {
        Activity a = getActivity();
        if (a != null) a.runOnUiThread(r);
    }

    /**
     * Runs the given runnable on the main thread and then dismisses the current dialog.
     * Used by JS interface handlers to avoid duplicating post + listener + dismiss logic.
     */
    private void runOnMainAndDismiss(Runnable beforeDismiss) {
        new Handler(Looper.getMainLooper()).post(() -> {
            try {
                if (beforeDismiss != null) beforeDismiss.run();
                dismissCurrentDialog();
            } catch (Exception e) {
                Log.e(TAG, "Error in runOnMainAndDismiss: " + e.getMessage());
                cleanupAllViews();
            }
        });
    }

    private class StashJavaScriptInterface {
        @JavascriptInterface
        public void onPaymentSuccess() {
            if (paymentSuccessHandled) return;
            paymentSuccessHandled = true;
            isPurchaseProcessing = false;
            runOnMainAndDismiss(() -> {
                if (listener != null) listener.onPaymentSuccess();
            });
        }
        
        @JavascriptInterface
        public void onPaymentFailure() {
            if (paymentSuccessHandled) return;
            paymentSuccessHandled = true;
            isPurchaseProcessing = false;
            runOnMainAndDismiss(() -> {
                if (listener != null) listener.onPaymentFailure();
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
            runOnMainAndDismiss(() -> {
                if (listener != null) listener.onOptInResponse(optinType != null ? optinType : "");
            });
        }

        @JavascriptInterface
        public void expand() {
            runOnMainSafely(() -> {
                try {
                    if (!useCheckoutOverlayPresentation) return;
                    Activity a = getActivity();
                    if (a == null || currentContainer == null || currentDialog == null || !currentDialog.isShowing()) return;
                    if (!isCheckoutOverlayExpanded) {
                        animateCheckoutOverlayExpand(a);
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error in expand from WebView: " + e.getMessage(), e);
                }
            });
        }

        @JavascriptInterface
        public void collapse() {
            runOnMainSafely(() -> {
                try {
                    if (!useCheckoutOverlayPresentation) return;
                    Activity a = getActivity();
                    if (a == null || currentContainer == null || currentDialog == null || !currentDialog.isShowing()) return;
                    if (isCheckoutOverlayExpanded) {
                        animateCheckoutOverlayCollapse(a);
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error in collapse from WebView: " + e.getMessage(), e);
                }
            });
        }
    }
    
    public static StashPayCardPlugin getInstance() {
        return Holder.INSTANCE;
    }
    
    private StashPayCardPlugin() {
    }
    
    /**
     * Sets the Activity reference using WeakReference to prevent memory leaks.
     * @param activity The activity to use for UI operations
     */
    void setActivity(Activity activity) {
        this.activityRef = new WeakReference<>(activity);
    }
    
    /**
     * Gets the Activity if still available, or null if it was garbage collected.
     * Always check for null before using.
     * @return The activity or null if no longer available
     */
    private Activity getActivity() {
        return activityRef != null ? activityRef.get() : null;
    }
    
    void setListener(StashPayCard.StashPayListener listener) {
        this.listener = listener;
    }
    
    public void openCheckout(String url) {
        try {
            usePopupPresentation = false;
            useModalPresentation = false;
            openURLInternal(url);
        } catch (Exception e) {
            Log.e(TAG, "Error in openCheckout: " + e.getMessage(), e);
            cleanupAllViews();
        }
    }
    
    public void openPopup(String url) {
        try {
            usePopupPresentation = true;
            useModalPresentation = false;
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
            useModalPresentation = false;
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
    
    public void openModal(String url, StashPayCard.ModalConfig config) {
        try {
            usePopupPresentation = false;
            useModalPresentation = true;
            currentModalConfig = config != null ? config : new StashPayCard.ModalConfig();
            openURLInternal(url);
        } catch (Exception e) {
            Log.e(TAG, "Error in openModal: " + e.getMessage(), e);
            cleanupAllViews();
        }
    }
    
    public void dismissDialog() {
        runOnMainSafely(() -> {
            try {
                dismissCurrentDialog();
            } catch (Exception e) {
                Log.e(TAG, "Error dismissing dialog: " + e.getMessage());
                cleanupAllViews();
            }
        });
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
    
    // ============================================================================
    // Orientation-Specific Phone Card Size Configuration
    // ============================================================================
    
    public float getCardHeightRatioPortrait() {
        return cardHeightRatioPortrait;
    }
    
    public void setCardHeightRatioPortrait(float ratio) {
        try {
            this.cardHeightRatioPortrait = clampRatio(ratio);
        } catch (Exception e) {
            Log.e(TAG, "Error in setCardHeightRatioPortrait: " + e.getMessage(), e);
        }
    }
    
    public boolean isForcePortraitOnCheckout() {
        return forcePortraitOnCheckout;
    }
    
    public void setForcePortraitOnCheckout(boolean force) {
        this.forcePortraitOnCheckout = force;
    }
    
    public float getCardWidthRatioLandscape() {
        return cardWidthRatioLandscape;
    }
    
    public void setCardWidthRatioLandscape(float ratio) {
        try {
            this.cardWidthRatioLandscape = clampRatio(ratio);
        } catch (Exception e) {
            Log.e(TAG, "Error in setCardWidthRatioLandscape: " + e.getMessage(), e);
        }
    }
    
    public float getCardHeightRatioLandscape() {
        return cardHeightRatioLandscape;
    }
    
    public void setCardHeightRatioLandscape(float ratio) {
        try {
            this.cardHeightRatioLandscape = clampRatio(ratio);
        } catch (Exception e) {
            Log.e(TAG, "Error in setCardHeightRatioLandscape: " + e.getMessage(), e);
        }
    }
    
    // ============================================================================
    // Orientation-Specific Tablet Card Size Configuration
    // ============================================================================
    
    public float getTabletWidthRatioPortrait() {
        return tabletWidthRatioPortrait;
    }
    
    public void setTabletWidthRatioPortrait(float ratio) {
        try {
            this.tabletWidthRatioPortrait = clampRatio(ratio);
        } catch (Exception e) {
            Log.e(TAG, "Error in setTabletWidthRatioPortrait: " + e.getMessage(), e);
        }
    }
    
    public float getTabletHeightRatioPortrait() {
        return tabletHeightRatioPortrait;
    }
    
    public void setTabletHeightRatioPortrait(float ratio) {
        try {
            this.tabletHeightRatioPortrait = clampRatio(ratio);
        } catch (Exception e) {
            Log.e(TAG, "Error in setTabletHeightRatioPortrait: " + e.getMessage(), e);
        }
    }
    
    public float getTabletWidthRatioLandscape() {
        return tabletWidthRatioLandscape;
    }
    
    public void setTabletWidthRatioLandscape(float ratio) {
        try {
            this.tabletWidthRatioLandscape = clampRatio(ratio);
        } catch (Exception e) {
            Log.e(TAG, "Error in setTabletWidthRatioLandscape: " + e.getMessage(), e);
        }
    }
    
    public float getTabletHeightRatioLandscape() {
        return tabletHeightRatioLandscape;
    }
    
    public void setTabletHeightRatioLandscape(float ratio) {
        try {
            this.tabletHeightRatioLandscape = clampRatio(ratio);
        } catch (Exception e) {
            Log.e(TAG, "Error in setTabletHeightRatioLandscape: " + e.getMessage(), e);
        }
    }
    
    private float clampRatio(float ratio) {
        return Math.max(0.1f, Math.min(1.0f, ratio));
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
            Activity activity = getActivity();
            if (activity == null || url == null || url.isEmpty()) {
                Log.e(TAG, "Invalid activity or URL");
                return;
            }

            if (!url.startsWith("http://") && !url.startsWith("https://")) {
                url = "https://" + url;
            }

            try {
                url = StashWebViewUtils.appendThemeQueryParameter(url, StashWebViewUtils.isDarkTheme(activity));
            } catch (Exception e) {
                Log.e(TAG, "Error appending theme parameter: " + e.getMessage(), e);
            }

            final String finalUrl = url;
            final Activity finalActivity = activity;

            activity.runOnUiThread(() -> {
                try {
                    if (usePopupPresentation) {
                        createAndShowPopupDialog(finalUrl, finalActivity);
                    } else if (useModalPresentation) {
                        // Modal always opens in-app; force web view (Chrome Custom Tabs) is for checkout only
                        createAndShowModalDialog(finalUrl, finalActivity);
                    } else if (forceSafariViewController) {
                        openWithChromeCustomTabs(finalUrl, finalActivity);
                    } else {
                        boolean isTablet = false;
                        try {
                            isTablet = StashWebViewUtils.isTablet(finalActivity);
                        } catch (Exception e) {
                            Log.e(TAG, "Error checking tablet: " + e.getMessage(), e);
                        }
                        if (!isTablet && !forcePortraitOnCheckout) {
                            createAndShowCheckoutOverlay(finalUrl, finalActivity);
                        } else {
                            launchPortraitActivity(finalUrl, finalActivity);
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
    
    private void launchPortraitActivity(String url, Activity activity) {
        try {
            int rotation;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                android.view.Display display = activity.getDisplay();
                rotation = display != null ? display.getRotation() : Surface.ROTATION_0;
            } else {
                @SuppressWarnings("deprecation")
                android.view.Display display = activity.getWindowManager().getDefaultDisplay();
                rotation = display.getRotation();
            }
            boolean isLandscape = (rotation == Surface.ROTATION_90 || rotation == Surface.ROTATION_270);
            
            Intent intent = new Intent();
            intent.setClassName(activity, StashPayCardPortraitActivity.class.getName());
            intent.putExtra(CardConstants.INTENT_EXTRA_URL, url);
            intent.putExtra(CardConstants.INTENT_EXTRA_INITIAL_URL, url);
            intent.putExtra(CardConstants.INTENT_EXTRA_CARD_HEIGHT_RATIO_PORTRAIT, cardHeightRatioPortrait);
            intent.putExtra(CardConstants.INTENT_EXTRA_FORCE_PORTRAIT_ON_CHECKOUT, forcePortraitOnCheckout);
            intent.putExtra(CardConstants.INTENT_EXTRA_CARD_WIDTH_RATIO_LANDSCAPE, cardWidthRatioLandscape);
            intent.putExtra(CardConstants.INTENT_EXTRA_CARD_HEIGHT_RATIO_LANDSCAPE, cardHeightRatioLandscape);
            intent.putExtra(CardConstants.INTENT_EXTRA_TABLET_WIDTH_RATIO_PORTRAIT, tabletWidthRatioPortrait);
            intent.putExtra(CardConstants.INTENT_EXTRA_TABLET_HEIGHT_RATIO_PORTRAIT, tabletHeightRatioPortrait);
            intent.putExtra(CardConstants.INTENT_EXTRA_TABLET_WIDTH_RATIO_LANDSCAPE, tabletWidthRatioLandscape);
            intent.putExtra(CardConstants.INTENT_EXTRA_TABLET_HEIGHT_RATIO_LANDSCAPE, tabletHeightRatioLandscape);
            intent.putExtra(CardConstants.INTENT_EXTRA_USE_POPUP, usePopupPresentation);
            intent.putExtra(CardConstants.INTENT_EXTRA_USE_MODAL, useModalPresentation);
            intent.putExtra(CardConstants.INTENT_EXTRA_WAS_LANDSCAPE, isLandscape);
            intent.putExtra(CardConstants.INTENT_EXTRA_FORCE_SAFARI_VIEW_CONTROLLER, forceSafariViewController);
            
            // Pass modal config if in modal mode
            if (useModalPresentation && currentModalConfig != null) {
                intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_SHOW_DRAG_BAR, currentModalConfig.showDragBar);
                intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_ALLOW_DISMISS, currentModalConfig.allowDismiss);
                intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_PHONE_WIDTH_RATIO_PORTRAIT, currentModalConfig.phoneWidthRatioPortrait);
                intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_PHONE_HEIGHT_RATIO_PORTRAIT, currentModalConfig.phoneHeightRatioPortrait);
                intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_PHONE_WIDTH_RATIO_LANDSCAPE, currentModalConfig.phoneWidthRatioLandscape);
                intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_PHONE_HEIGHT_RATIO_LANDSCAPE, currentModalConfig.phoneHeightRatioLandscape);
                intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_TABLET_WIDTH_RATIO_PORTRAIT, currentModalConfig.tabletWidthRatioPortrait);
                intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_TABLET_HEIGHT_RATIO_PORTRAIT, currentModalConfig.tabletHeightRatioPortrait);
                intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_TABLET_WIDTH_RATIO_LANDSCAPE, currentModalConfig.tabletWidthRatioLandscape);
                intent.putExtra(CardConstants.INTENT_EXTRA_MODAL_TABLET_HEIGHT_RATIO_LANDSCAPE, currentModalConfig.tabletHeightRatioLandscape);
            }
            
            intent.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
            
            activity.startActivity(intent);
            activity.overridePendingTransition(0, 0);
            isCurrentlyPresented = true;
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
                            int[] newDimensions;
                            if (useCheckoutOverlayPresentation) {
                                newDimensions = calculateCheckoutOverlayDimensions(activity);
                            } else if (useModalPresentation) {
                                newDimensions = calculateModalDimensions(activity);
                            } else {
                                newDimensions = calculatePopupDimensions(activity);
                            }
                            FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) currentContainer.getLayoutParams();
                            
                            if (useCheckoutOverlayPresentation) {
                                isCheckoutOverlayExpanded = false;
                                params.width = newDimensions[0];
                                params.height = newDimensions[1];
                                params.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
                                currentContainer.setLayoutParams(params);
                            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
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

    /**
     * Touch listener for checkout overlay drag bar: expand (drag up), collapse (drag down when expanded), dismiss (drag down when collapsed).
     */
    private class CheckoutOverlayDragTouchListener implements View.OnTouchListener {
        private final Activity activity;
        private float initialY;
        private int initialHeight;
        private boolean isDragging;
        private long lastMoveTime;
        private float lastMoveY;
        private float velocity;
        private DisplayMetrics displayMetrics;

        CheckoutOverlayDragTouchListener(Activity activity) {
            this.activity = activity;
        }

        @Override
        public boolean onTouch(View v, MotionEvent event) {
            if (currentContainer == null || currentDialog == null || !currentDialog.isShowing() || !useCheckoutOverlayPresentation) return false;
            if (isPurchaseProcessing) return false;

            switch (event.getAction()) {
                case MotionEvent.ACTION_DOWN:
                    initialY = event.getRawY();
                    FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) currentContainer.getLayoutParams();
                    initialHeight = params.height;
                    isDragging = false;
                    lastMoveTime = System.currentTimeMillis();
                    lastMoveY = event.getRawY();
                    velocity = 0;
                    displayMetrics = activity.getResources().getDisplayMetrics();
                    return true;

                case MotionEvent.ACTION_MOVE:
                    float deltaY = event.getRawY() - initialY;
                    long currentTime = System.currentTimeMillis();
                    float timeDelta = (currentTime - lastMoveTime) / 1000f;
                    if (timeDelta > 0) velocity = (event.getRawY() - lastMoveY) / timeDelta;
                    lastMoveTime = currentTime;
                    lastMoveY = event.getRawY();

                    if (Math.abs(deltaY) > StashWebViewUtils.dpToPx(activity, 10)) {
                        isDragging = true;
                        if (deltaY > 0) {
                            if (isCheckoutOverlayExpanded) {
                                float cardHeight = currentContainer.getHeight();
                                float collapseThreshold = cardHeight * CardConstants.COLLAPSE_DISTANCE_THRESHOLD;
                                float progress = Math.min(deltaY / collapseThreshold, 1.0f);
                                int[] collapsed = calculateCheckoutOverlayDimensions(activity);
                                int expandedHeight = (int)(displayMetrics.heightPixels * CardConstants.EXPANDED_CARD_HEIGHT_RATIO);
                                int newHeight = (int)(expandedHeight - progress * (expandedHeight - collapsed[1]));
                                params = (FrameLayout.LayoutParams) currentContainer.getLayoutParams();
                                params.height = Math.max(newHeight, collapsed[1]);
                                currentContainer.setLayoutParams(params);
                            } else {
                                float newTranslationY = deltaY;
                                currentContainer.setTranslationY(newTranslationY);
                                float progress = Math.min(deltaY / displayMetrics.heightPixels, 1.0f);
                                currentContainer.setAlpha(1.0f - (progress * CardConstants.ALPHA_FADE_MULTIPLIER));
                            }
                        } else if (!isCheckoutOverlayExpanded) {
                            float cardHeight = currentContainer.getHeight();
                            float expandThreshold = cardHeight * CardConstants.EXPAND_DISTANCE_THRESHOLD;
                            float dragProgress = Math.min(Math.abs(deltaY) / expandThreshold, 1.0f);
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
                                currentContainer.setScaleX(1.0f + (dragProgress * 0.02f));
                                currentContainer.setScaleY(1.0f + (dragProgress * 0.02f));
                            }
                        }
                    }
                    return true;

                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_CANCEL:
                    if (isDragging) {
                        float finalDeltaY = event.getRawY() - initialY;
                        DisplayMetrics metrics = displayMetrics != null ? activity.getResources().getDisplayMetrics() : activity.getResources().getDisplayMetrics();
                        int cardHeight = currentContainer.getHeight();

                        if (finalDeltaY > 0) {
                            if (isCheckoutOverlayExpanded) {
                                float dismissThreshold = metrics.heightPixels * CardConstants.DISMISS_DISTANCE_THRESHOLD_TABLET;
                                float collapseThreshold = cardHeight * CardConstants.COLLAPSE_DISTANCE_THRESHOLD;
                                if (finalDeltaY > dismissThreshold && velocity > CardConstants.DISMISS_VELOCITY_THRESHOLD) {
                                    animateCheckoutOverlayDismiss();
                                } else if (finalDeltaY > collapseThreshold || velocity > CardConstants.COLLAPSE_VELOCITY_THRESHOLD) {
                                    animateCheckoutOverlayCollapse(activity);
                                } else {
                                    animateCheckoutOverlaySnapBackExpand(activity);
                                }
                            } else {
                                float dismissThreshold = metrics.heightPixels * CardConstants.DISMISS_DISTANCE_THRESHOLD_PHONE;
                                if (finalDeltaY > dismissThreshold || velocity > CardConstants.DISMISS_VELOCITY_THRESHOLD) {
                                    animateCheckoutOverlayDismiss();
                                } else {
                                    animateCheckoutOverlaySnapBackCollapsed(activity);
                                }
                            }
                        } else if (finalDeltaY < 0 && !isCheckoutOverlayExpanded) {
                            float expandThreshold = cardHeight * CardConstants.EXPAND_DISTANCE_THRESHOLD;
                            if (Math.abs(finalDeltaY) > expandThreshold || velocity < CardConstants.EXPAND_VELOCITY_THRESHOLD) {
                                animateCheckoutOverlayExpand(activity);
                            } else {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
                                    currentContainer.animate().scaleX(1f).scaleY(1f).setDuration(CardConstants.ANIMATION_DURATION_SNAP_BACK).setInterpolator(new SpringInterpolator()).start();
                                }
                            }
                        } else {
                            if (isCheckoutOverlayExpanded) {
                                animateCheckoutOverlaySnapBackExpand(activity);
                            } else {
                                animateCheckoutOverlaySnapBackCollapsed(activity);
                            }
                        }
                    }
                    return true;
            }
            return false;
        }
    }

    private void animateCheckoutOverlayExpand(Activity activity) {
        if (currentContainer == null || activity == null) return;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
            currentContainer.animate().scaleX(1f).scaleY(1f).setDuration(100).start();
        }
        FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) currentContainer.getLayoutParams();
        int expandedHeight = (int)(activity.getResources().getDisplayMetrics().heightPixels * CardConstants.EXPANDED_CARD_HEIGHT_RATIO);
        ValueAnimator heightAnimator = ValueAnimator.ofInt(params.height, expandedHeight);
        heightAnimator.setDuration(CardConstants.ANIMATION_DURATION_EXPAND);
        heightAnimator.setInterpolator(new SpringInterpolator());
        heightAnimator.addUpdateListener(animation -> {
            if (currentContainer != null) {
                FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) currentContainer.getLayoutParams();
                p.height = (Integer) animation.getAnimatedValue();
                currentContainer.setLayoutParams(p);
            }
        });
        heightAnimator.start();
        currentContainer.setTranslationY(0);
        currentContainer.setAlpha(1f);
        isCheckoutOverlayExpanded = true;
    }

    private void animateCheckoutOverlayCollapse(Activity activity) {
        if (currentContainer == null || activity == null || !isCheckoutOverlayExpanded) return;
        int[] dims = calculateCheckoutOverlayDimensions(activity);
        FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) currentContainer.getLayoutParams();
        ValueAnimator heightAnimator = ValueAnimator.ofInt(params.height, dims[1]);
        heightAnimator.setDuration(CardConstants.ANIMATION_DURATION_COLLAPSE);
        heightAnimator.setInterpolator(new SpringInterpolator());
        heightAnimator.addUpdateListener(animation -> {
            if (currentContainer != null) {
                FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) currentContainer.getLayoutParams();
                p.height = (Integer) animation.getAnimatedValue();
                currentContainer.setLayoutParams(p);
            }
        });
        heightAnimator.start();
        currentContainer.setTranslationY(0);
        currentContainer.setAlpha(1f);
        isCheckoutOverlayExpanded = false;
    }

    private void animateCheckoutOverlaySnapBackExpand(Activity activity) {
        if (currentContainer == null) return;
        int expandedHeight = (int)(activity.getResources().getDisplayMetrics().heightPixels * CardConstants.EXPANDED_CARD_HEIGHT_RATIO);
        FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) currentContainer.getLayoutParams();
        ValueAnimator heightAnimator = ValueAnimator.ofInt(params.height, expandedHeight);
        heightAnimator.setDuration(CardConstants.ANIMATION_DURATION_SNAP_BACK);
        heightAnimator.setInterpolator(new SpringInterpolator());
        heightAnimator.addUpdateListener(animation -> {
            if (currentContainer != null) {
                FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) currentContainer.getLayoutParams();
                p.height = (Integer) animation.getAnimatedValue();
                currentContainer.setLayoutParams(p);
            }
        });
        heightAnimator.start();
        currentContainer.setTranslationY(0);
        currentContainer.setAlpha(1f);
    }

    private void animateCheckoutOverlaySnapBackCollapsed(Activity activity) {
        if (currentContainer == null || activity == null) return;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
            currentContainer.animate().scaleX(1f).scaleY(1f).setDuration(CardConstants.ANIMATION_DURATION_SNAP_BACK).setInterpolator(new SpringInterpolator()).start();
        }
        currentContainer.setTranslationY(0);
        currentContainer.setAlpha(1f);
    }

    private void animateCheckoutOverlayDismiss() {
        if (currentDialog == null || currentContainer == null) return;
        Activity a = getActivity();
        int height = currentContainer.getHeight();
        if (height <= 0 && a != null) height = (int)(a.getResources().getDisplayMetrics().heightPixels * cardHeightRatioPortrait);
        if (height <= 0) height = 800;
        final int finalHeight = height;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
            currentContainer.animate()
                .translationY(finalHeight)
                .setDuration(CardConstants.ANIMATION_DURATION_ENTRY)
                .setInterpolator(new android.view.animation.AccelerateInterpolator())
                .withEndAction(() -> {
                    if (currentDialog != null) currentDialog.dismiss();
                })
                .start();
        } else {
            currentDialog.dismiss();
        }
        isCheckoutOverlayExpanded = false;
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
                mainFrame.setBackgroundColor(Color.parseColor(CardConstants.COLOR_BACKGROUND_DIM));
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
                float radius = StashWebViewUtils.dpToPx(activity, (int) CardConstants.CORNER_RADIUS_DP);
                popupBg.setCornerRadius(radius);
                currentContainer.setBackground(popupBg);
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    currentContainer.setElevation(StashWebViewUtils.dpToPx(activity, (int) CardConstants.ELEVATION_DP));
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
            } catch (Exception e) {
                Log.e(TAG, "Error setting container background: " + e.getMessage(), e);
            }
            
            try {
                webView = new WebView(activity);
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
                    windowParams.dimAmount = CardConstants.OVERLAY_ALPHA;
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
    
    private void createAndShowModalDialog(String url, final Activity activity) {
        if (activity == null || url == null || url.isEmpty()) {
            Log.e(TAG, "Invalid activity or URL in createAndShowModalDialog");
            return;
        }
        if (currentModalConfig == null) {
            currentModalConfig = new StashPayCard.ModalConfig();
        }

        cleanupAllViews();
        useModalPresentation = true;
        paymentSuccessHandled = false;

        try {
            currentDialog = new Dialog(activity, android.R.style.Theme_Translucent_NoTitleBar_Fullscreen);
            currentDialog.requestWindowFeature(Window.FEATURE_NO_TITLE);

            FrameLayout mainFrame = new FrameLayout(activity);
            try {
                mainFrame.setBackgroundColor(Color.parseColor(StashWebViewUtils.COLOR_BACKGROUND_DIM));
            } catch (Exception e) {
                Log.e(TAG, "Error setting background color: " + e.getMessage(), e);
                mainFrame.setBackgroundColor(Color.parseColor(CardConstants.COLOR_BACKGROUND_DIM));
            }

            mainFrame.setOnClickListener(v -> {
                try {
                    if (currentModalConfig.allowDismiss && !isPurchaseProcessing && currentDialog != null && currentDialog.isShowing() && v == mainFrame) {
                        currentDialog.dismiss();
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error in click handler: " + e.getMessage(), e);
                }
            });

            int[] dimensions;
            try {
                dimensions = calculateModalDimensions(activity);
            } catch (Exception e) {
                Log.e(TAG, "Error calculating modal dimensions: " + e.getMessage(), e);
                DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
                dimensions = new int[]{
                    (int)(metrics.widthPixels * 0.9f),
                    (int)(metrics.heightPixels * 0.5f)
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
                float radius = StashWebViewUtils.dpToPx(activity, (int) CardConstants.CORNER_RADIUS_DP);
                popupBg.setCornerRadius(radius);
                currentContainer.setBackground(popupBg);

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    currentContainer.setElevation(StashWebViewUtils.dpToPx(activity, (int) CardConstants.ELEVATION_DP));
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
            } catch (Exception e) {
                Log.e(TAG, "Error setting container background: " + e.getMessage(), e);
            }

            try {
                webView = new WebView(activity);
                FrameLayout.LayoutParams webViewParams = new FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
                webView.setLayoutParams(webViewParams);
                currentContainer.addView(webView);
                if (currentModalConfig.showDragBar) {
                    addVisualDragBarToContainer(activity, currentContainer);
                }
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
                    windowParams.dimAmount = CardConstants.OVERLAY_ALPHA;
                    window.setAttributes(windowParams);
                } catch (Exception e) {
                    Log.e(TAG, "Error configuring window: " + e.getMessage(), e);
                }
            }

            currentContainer.setOnClickListener(v -> {});

            currentDialog.setCanceledOnTouchOutside(currentModalConfig.allowDismiss && !isPurchaseProcessing);
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
                Log.e(TAG, "Error showing modal dialog: " + e.getMessage(), e);
                cleanupAllViews();
            }
        } catch (Exception e) {
            Log.e(TAG, "Error creating modal: " + e.getMessage(), e);
            cleanupAllViews();
        }
    }

    private void animateFadeIn() {
        try {
            if (currentContainer != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
                currentContainer.setAlpha(0.0f);
                currentContainer.setScaleX(0.9f);
                currentContainer.setScaleY(0.9f);
                currentContainer.animate()
                    .alpha(1.0f)
                    .scaleX(1.0f)
                    .scaleY(1.0f)
                    .setDuration(CardConstants.ANIMATION_DURATION_POPUP)
                    .setInterpolator(new android.view.animation.AccelerateDecelerateInterpolator())
                    .start();
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
                        .setDuration(CardConstants.ANIMATION_DURATION_FAST)
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
            StashWebViewUtils.configureWebViewSettings(webView, StashWebViewUtils.isDarkTheme(activity));
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
                    }, CardConstants.HIDE_LOADING_DELAY_MS);
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
            webView.addJavascriptInterface(new StashJavaScriptInterface(), StashWebViewUtils.JS_INTERFACE_NAME);
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
    
    /**
     * Registers activity lifecycle callbacks to log when the app goes to background
     * (e.g. CCT/browser in foreground) and when the user returns. Unregisters automatically
     * when the launch activity is started again or destroyed.
     */
    private void registerBrowserLifecycleLogging(Activity launchActivity, String source) {
        if (launchActivity == null) return;
        Application app = launchActivity.getApplication();
        if (app == null) return;
        final Activity activity = launchActivity;
        final String sourceLabel = source;
        Application.ActivityLifecycleCallbacks callbacks = new Application.ActivityLifecycleCallbacks() {
            @Override
            public void onActivityCreated(Activity a, android.os.Bundle savedInstanceState) {}
            @Override
            public void onActivityStarted(Activity a) {
                if (a == activity) {
                    Log.d(TAG, "App resumed (returned from " + sourceLabel + ")");
                    app.unregisterActivityLifecycleCallbacks(this);
                }
            }
            @Override
            public void onActivityResumed(Activity a) {}
            @Override
            public void onActivityPaused(Activity a) {
                if (a == activity) {
                    Log.d(TAG, "App paused (" + sourceLabel + " in foreground)");
                }
            }
            @Override
            public void onActivityStopped(Activity a) {
                if (a == activity) {
                    Log.d(TAG, "App in background (" + sourceLabel + " visible)");
                }
            }
            @Override
            public void onActivitySaveInstanceState(Activity a, android.os.Bundle outState) {}
            @Override
            public void onActivityDestroyed(Activity a) {
                if (a == activity) {
                    Log.d(TAG, "Launch activity destroyed, unregistering " + sourceLabel + " lifecycle logging");
                    app.unregisterActivityLifecycleCallbacks(this);
                }
            }
        };
        app.registerActivityLifecycleCallbacks(callbacks);
    }
    
    private void openWithChromeCustomTabs(String url, Activity activity) {
        try {
            // Start keep-alive service only if forceSafariViewController is enabled
            if (forceSafariViewController) {
                requestNotificationPermissionIfNeeded(activity);
                StashKeepAliveManager.start(activity, "checkout", 30000L);
            }
            
            if (StashWebViewUtils.isChromeCustomTabsAvailable(activity)) {
                Log.d(TAG, "Opening URL with Chrome Custom Tabs");
                StashWebViewUtils.openWithChromeCustomTabs(activity, url);
                registerBrowserLifecycleLogging(activity, "CCT");
                isCurrentlyPresented = true;
                new Handler(Looper.getMainLooper()).postDelayed(() -> {
                    try {
                        if (listener != null) {
                            listener.onDialogDismissed();
                        }
                    } catch (Exception e) {
                        Log.e(TAG, "Error sending dialog dismissed: " + e.getMessage(), e);
                    }
                }, CardConstants.DIALOG_DISMISS_DELAY_MS);
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
    
    private void openWithDefaultBrowser(String url, Activity activity) {
        if (activity == null || url == null || url.isEmpty()) {
            Log.e(TAG, "Invalid activity or URL in openWithDefaultBrowser");
            return;
        }

        try {
            // Start keep-alive service only if forceSafariViewController is enabled
            if (forceSafariViewController) {
                requestNotificationPermissionIfNeeded(activity);
                StashKeepAliveManager.start(activity, "checkout", 30000L);
            }
            
            Intent browserIntent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
            browserIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            activity.startActivity(browserIntent);
            registerBrowserLifecycleLogging(activity, "browser");
            isCurrentlyPresented = true;

            new Handler(Looper.getMainLooper()).postDelayed(() -> {
                try {
                    if (listener != null) {
                        listener.onDialogDismissed();
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error sending dialog dismissed: " + e.getMessage(), e);
                }
            }, CardConstants.DIALOG_DISMISS_DELAY_MS);
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
            useCheckoutOverlayPresentation = false;
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
        useModalPresentation = false;
    }
    
    private int[] calculatePopupDimensions(Activity activity) {
        if (activity == null) {
            Log.e(TAG, "Activity is null in calculatePopupDimensions");
            return new int[]{CardConstants.FALLBACK_POPUP_WIDTH, CardConstants.FALLBACK_POPUP_HEIGHT};
        }

        try {
            DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
            boolean isLandscape = activity.getResources().getConfiguration().orientation == Configuration.ORIENTATION_LANDSCAPE;
            
            int smallerDimension = Math.min(metrics.widthPixels, metrics.heightPixels);
            boolean isTablet = StashWebViewUtils.isTablet(activity);
            float sizeRatio = isTablet ? CardConstants.POPUP_SIZE_RATIO_TABLET : CardConstants.POPUP_SIZE_RATIO_PHONE;
            int minSize = isTablet ? StashWebViewUtils.dpToPx(activity, (int) CardConstants.MIN_TABLET_CARD_WIDTH_DP) : StashWebViewUtils.dpToPx(activity, (int) CardConstants.MIN_PHONE_CARD_WIDTH_DP);
            int maxSize = StashWebViewUtils.dpToPx(activity, (int) CardConstants.MIN_TABLET_CARD_HEIGHT_DP);
            int baseSize = Math.max(minSize, Math.min(maxSize, (int)(smallerDimension * sizeRatio)));
            
            float widthMultiplier = isLandscape ? 
                (useCustomSize ? customLandscapeWidthMultiplier : CardConstants.POPUP_LANDSCAPE_WIDTH_MULTIPLIER) :
                (useCustomSize ? customPortraitWidthMultiplier : CardConstants.POPUP_PORTRAIT_WIDTH_MULTIPLIER);
            float heightMultiplier = isLandscape ? 
                (useCustomSize ? customLandscapeHeightMultiplier : CardConstants.POPUP_LANDSCAPE_HEIGHT_MULTIPLIER) :
                (useCustomSize ? customPortraitHeightMultiplier : CardConstants.POPUP_PORTRAIT_HEIGHT_MULTIPLIER);

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
                return new int[]{CardConstants.FALLBACK_POPUP_WIDTH, CardConstants.FALLBACK_POPUP_HEIGHT};
            }
        }
    }

    private int[] calculateModalDimensions(Activity activity) {
        if (activity == null || currentModalConfig == null) {
            Log.e(TAG, "Activity or modal config is null in calculateModalDimensions");
            return new int[]{CardConstants.FALLBACK_POPUP_WIDTH, CardConstants.FALLBACK_POPUP_HEIGHT};
        }

        try {
            DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
            int screenWidth = metrics.widthPixels;
            int screenHeight = metrics.heightPixels;
            boolean isLandscape = screenWidth > screenHeight;
            boolean isTablet = StashWebViewUtils.isTablet(activity);

            float widthRatio, heightRatio;
            if (isTablet) {
                widthRatio = isLandscape ? currentModalConfig.tabletWidthRatioLandscape : currentModalConfig.tabletWidthRatioPortrait;
                heightRatio = isLandscape ? currentModalConfig.tabletHeightRatioLandscape : currentModalConfig.tabletHeightRatioPortrait;
            } else {
                widthRatio = isLandscape ? currentModalConfig.phoneWidthRatioLandscape : currentModalConfig.phoneWidthRatioPortrait;
                heightRatio = isLandscape ? currentModalConfig.phoneHeightRatioLandscape : currentModalConfig.phoneHeightRatioPortrait;
            }

            int cardWidth = (int) (screenWidth * widthRatio);
            int cardHeight = (int) (screenHeight * heightRatio);

            int minWidthPx = isTablet
                ? StashWebViewUtils.dpToPx(activity, (int) CardConstants.MIN_TABLET_CARD_WIDTH_DP)
                : StashWebViewUtils.dpToPx(activity, (int) CardConstants.MIN_PHONE_CARD_WIDTH_DP);
            int minHeightPx = isTablet
                ? StashWebViewUtils.dpToPx(activity, (int) CardConstants.MIN_TABLET_CARD_HEIGHT_DP)
                : StashWebViewUtils.dpToPx(activity, (int) CardConstants.MIN_PHONE_CARD_WIDTH_DP);

            if (cardWidth < minWidthPx) cardWidth = minWidthPx;
            if (cardHeight < minHeightPx) cardHeight = minHeightPx;

            return new int[]{cardWidth, cardHeight};
        } catch (Exception e) {
            Log.e(TAG, "Error calculating modal dimensions: " + e.getMessage(), e);
            try {
                DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
                return new int[]{
                    (int) (metrics.widthPixels * 0.9f),
                    (int) (metrics.heightPixels * 0.5f)
                };
            } catch (Exception e2) {
                Log.e(TAG, "Error getting fallback dimensions: " + e2.getMessage(), e2);
                return new int[]{CardConstants.FALLBACK_POPUP_WIDTH, CardConstants.FALLBACK_POPUP_HEIGHT};
            }
        }
    }
    
    private int[] calculateCheckoutOverlayDimensions(Activity activity) {
        if (activity == null) {
            return new int[]{CardConstants.FALLBACK_POPUP_WIDTH, CardConstants.FALLBACK_POPUP_HEIGHT};
        }
        try {
            DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
            int screenWidth = metrics.widthPixels;
            int screenHeight = metrics.heightPixels;
            boolean isLandscape = activity.getResources().getConfiguration().orientation == Configuration.ORIENTATION_LANDSCAPE;
            int cardWidth;
            int cardHeight;
            if (isLandscape) {
                int w = (int)(screenWidth * cardWidthRatioLandscape);
                int h = (int)(screenHeight * cardHeightRatioLandscape);
                int minPx = StashWebViewUtils.dpToPx(activity, (int) CardConstants.MIN_PHONE_CARD_WIDTH_DP);
                if (w < minPx) w = minPx;
                if (h < minPx) h = minPx;
                cardWidth = w;
                cardHeight = h;
            } else {
                cardWidth = screenWidth;
                cardHeight = (int)(screenHeight * cardHeightRatioPortrait);
            }
            return new int[]{cardWidth, cardHeight};
        } catch (Exception e) {
            Log.e(TAG, "Error calculating checkout overlay dimensions: " + e.getMessage(), e);
            try {
                DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
                return new int[]{
                    metrics.widthPixels,
                    (int)(metrics.heightPixels * CardConstants.DEFAULT_CARD_HEIGHT_RATIO)
                };
            } catch (Exception e2) {
                return new int[]{CardConstants.FALLBACK_POPUP_WIDTH, CardConstants.FALLBACK_POPUP_HEIGHT};
            }
        }
    }
    
    private void createAndShowCheckoutOverlay(String url, final Activity activity) {
        if (activity == null || url == null || url.isEmpty()) {
            Log.e(TAG, "Invalid activity or URL in createAndShowCheckoutOverlay");
            return;
        }
        cleanupAllViews();
        useCheckoutOverlayPresentation = true;
        paymentSuccessHandled = false;
        try {
            currentDialog = new Dialog(activity, android.R.style.Theme_Translucent_NoTitleBar_Fullscreen);
            currentDialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
            FrameLayout mainFrame = new FrameLayout(activity);
            try {
                mainFrame.setBackgroundColor(Color.parseColor(StashWebViewUtils.COLOR_BACKGROUND_DIM));
            } catch (Exception e) {
                mainFrame.setBackgroundColor(Color.parseColor(CardConstants.COLOR_BACKGROUND_DIM));
            }
            mainFrame.setOnClickListener(v -> {
                try {
                    if (!isPurchaseProcessing && currentDialog != null && currentDialog.isShowing() && v == mainFrame) {
                        currentDialog.dismiss();
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error in checkout overlay click handler: " + e.getMessage(), e);
                }
            });
            int[] dimensions;
            try {
                dimensions = calculateCheckoutOverlayDimensions(activity);
            } catch (Exception e) {
                Log.e(TAG, "Error calculating checkout overlay dimensions: " + e.getMessage(), e);
                DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
                dimensions = new int[]{
                    metrics.widthPixels,
                    (int)(metrics.heightPixels * cardHeightRatioPortrait)
                };
            }
            currentContainer = new FrameLayout(activity);
            FrameLayout.LayoutParams containerParams = new FrameLayout.LayoutParams(dimensions[0], dimensions[1]);
            containerParams.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
            currentContainer.setLayoutParams(containerParams);
            try {
                lastOrientation = activity.getResources().getConfiguration().orientation;
            } catch (Exception e) {
                lastOrientation = Configuration.ORIENTATION_PORTRAIT;
            }
            orientationChangeListener = new PopupOrientationListener(activity);
            try {
                mainFrame.getViewTreeObserver().addOnGlobalLayoutListener(orientationChangeListener);
            } catch (Exception e) {
                Log.e(TAG, "Error adding orientation listener: " + e.getMessage(), e);
            }
            try {
                GradientDrawable popupBg = new GradientDrawable();
                popupBg.setColor(StashWebViewUtils.getThemeBackgroundColor(activity));
                float radius = StashWebViewUtils.dpToPx(activity, (int) CardConstants.CORNER_RADIUS_DP);
                popupBg.setCornerRadius(radius);
                currentContainer.setBackground(popupBg);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    currentContainer.setElevation(StashWebViewUtils.dpToPx(activity, (int) CardConstants.ELEVATION_DP));
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
            } catch (Exception e) {
                Log.e(TAG, "Error setting container background: " + e.getMessage(), e);
            }
            try {
                webView = new WebView(activity);
                FrameLayout.LayoutParams webViewParams = new FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
                webView.setLayoutParams(webViewParams);
                currentContainer.addView(webView);
                addCheckoutOverlayDragBar(activity);
                View dragArea = currentContainer.getChildCount() > 0 ? currentContainer.getChildAt(currentContainer.getChildCount() - 1) : null;
                if (dragArea != null) {
                    dragArea.setOnTouchListener(new CheckoutOverlayDragTouchListener(activity));
                }
                setupPopupWebView(webView, url, activity);
            } catch (Exception e) {
                Log.e(TAG, "Error creating WebView in checkout overlay: " + e.getMessage(), e);
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
                    windowParams.dimAmount = CardConstants.OVERLAY_ALPHA;
                    window.setAttributes(windowParams);
                } catch (Exception e) {
                    Log.e(TAG, "Error configuring checkout overlay window: " + e.getMessage(), e);
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
                    Log.e(TAG, "Error in checkout overlay dismiss listener: " + e.getMessage(), e);
                }
                cleanupAllViews();
                isCurrentlyPresented = false;
            });
            currentDialog.show();
            DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
            currentContainer.setTranslationY(metrics.heightPixels);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
                currentContainer.animate()
                    .translationY(0)
                    .setDuration(CardConstants.ANIMATION_DURATION_DEFAULT)
                    .setInterpolator(new android.view.animation.DecelerateInterpolator())
                    .start();
            } else {
                currentContainer.setTranslationY(0);
            }
            isCurrentlyPresented = true;
        } catch (Exception e) {
            Log.e(TAG, "Error creating checkout overlay: " + e.getMessage(), e);
            cleanupAllViews();
        }
    }
    
    /** Adds the same visual drag bar as Activity cards (no touch handling) so checkout overlay matches other modes. */
    private void addCheckoutOverlayDragBar(Activity activity) {
        addVisualDragBarToContainer(activity, currentContainer);
    }

    /**
     * Requests POST_NOTIFICATIONS permission on Android 13+ if not already granted.
     * This is required for the keep-alive service notification to be visible.
     */
    private void requestNotificationPermissionIfNeeded(Activity activity) {
        if (activity == null) return;
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(activity, android.Manifest.permission.POST_NOTIFICATIONS)
                    != PackageManager.PERMISSION_GRANTED) {
                // Request permission if not granted
                // Note: This will show a system dialog. If user denies, service still runs but notification may not be visible.
                ActivityCompat.requestPermissions(activity,
                    new String[]{android.Manifest.permission.POST_NOTIFICATIONS},
                    1001);
            }
        }
    }
    
    /** Adds a visual-only drag bar to the given container (modal or overlay). No touch handling. */
    private void addVisualDragBarToContainer(Activity activity, FrameLayout container) {
        if (container == null || activity == null) return;
        try {
            LinearLayout dragArea = new LinearLayout(activity);
            dragArea.setOrientation(LinearLayout.VERTICAL);
            dragArea.setGravity(Gravity.CENTER_HORIZONTAL);
            dragArea.setPadding(StashWebViewUtils.dpToPx(activity, 20), StashWebViewUtils.dpToPx(activity, 16), StashWebViewUtils.dpToPx(activity, 20), StashWebViewUtils.dpToPx(activity, 16));
            View handle = new View(activity);
            GradientDrawable handleBg = new GradientDrawable();
            handleBg.setColor(Color.parseColor(CardConstants.COLOR_DRAG_HANDLE));
            handleBg.setCornerRadius(StashWebViewUtils.dpToPx(activity, 2));
            handle.setBackground(handleBg);
            handle.setLayoutParams(new LinearLayout.LayoutParams(StashWebViewUtils.dpToPx(activity, 36), StashWebViewUtils.dpToPx(activity, 5)));
            dragArea.addView(handle);
            FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                StashWebViewUtils.dpToPx(activity, 120), FrameLayout.LayoutParams.WRAP_CONTENT);
            params.gravity = Gravity.TOP | Gravity.CENTER_HORIZONTAL;
            dragArea.setLayoutParams(params);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                dragArea.setElevation(StashWebViewUtils.dpToPx(activity, 8));
            }
            container.addView(dragArea);
        } catch (Exception e) {
            Log.e(TAG, "Error adding visual drag bar: " + e.getMessage(), e);
        }
    }
}
