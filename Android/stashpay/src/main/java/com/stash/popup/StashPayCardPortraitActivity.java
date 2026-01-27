package com.stash.popup;

import android.app.Activity;
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
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewOutlineProvider;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.CookieManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.net.Uri;

/**
 * Activity that displays the Stash Pay checkout as a card or popup overlay.
 */
public class StashPayCardPortraitActivity extends Activity {
    private static final String TAG = "StashPayCard";
    private static final float CARD_HEIGHT_NORMAL = 0.68f;
    private static final float CARD_HEIGHT_EXPANDED = 0.95f;

    private FrameLayout rootLayout;
    private View backdropView;
    private FrameLayout cardContainer;
    private WebView webView;
    private ProgressBar loadingIndicator;
    private Button homeButton;
    
    private String url;
    private String initialURL;
    private boolean usePopup;
    private boolean isExpanded;
    private boolean wasLandscapeBeforePortrait;
    private boolean isDismissing;
    private boolean callbackSent;
    private boolean googlePayRedirectHandled;
    private boolean isPurchaseProcessing;
    private boolean isVeryLowEnd; // Cache low-end detection
    
    // Cached values to avoid repeated calls (optimization)
    private boolean cachedIsDarkTheme;
    private boolean cachedIsTablet;
    private DisplayMetrics cachedDisplayMetrics;
    private StashPayCardPlugin cachedPlugin; // Cache plugin instance
    private int cachedDarkBgColor; // Cache parsed colors
    private int cachedWhiteColor;
    private int cachedDragHandleColor; // Cache more colors
    private int cachedHomeTextColor;
    private int cachedDarkStrokeColor;
    private int cachedLightStrokeColor;
    private int cachedLightBgColor;
    private int cachedDimBgColor;
    
    private static final String COLOR_LIGHT_BG = "#F2F2F7";
    private static final String COLOR_DARK_STROKE = "#38383A";
    private static final String COLOR_LIGHT_STROKE = "#E5E5EA";
    private static final String COLOR_DRAG_HANDLE = "#D1D1D6";
    private static final String COLOR_HOME_TEXT = "#8E8E93";
    
    private static final int ANIMATION_DURATION_SHORT = 200;
    private static final int ANIMATION_DURATION_MEDIUM = 300;
    private static final int ANIMATION_DURATION_LONG = 400;
    private static final float CORNER_RADIUS_DP = 12f;
    private static final float ELEVATION_DP = 24f;

    private long activityCreateStartTime;
    private long webViewCreateStartTime;
    private long loadUrlCallTime;
    private long pageLoadStartTime;
    private long uiVisibleTime;
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        activityCreateStartTime = System.currentTimeMillis();
        cachedPlugin = StashPayCardPlugin.getInstance(); // Cache plugin
        if (cachedPlugin.enableTimingLogs) {
            Log.d(TAG, "⏱️ [TIMING] Activity.onCreate() started");
        }
        
        try {
            Intent intent = getIntent();
            if (intent == null) {
                Log.e(TAG, "Intent is null in onCreate");
                finish();
                return;
            }
            
            url = intent.getStringExtra("url");
            initialURL = intent.getStringExtra("initialURL");
            usePopup = intent.getBooleanExtra("usePopup", false);
            wasLandscapeBeforePortrait = intent.getBooleanExtra("wasLandscape", false);
            
            if (url == null || url.isEmpty()) {
                finish();
                return;
            }
            
            // Cache frequently accessed values to avoid repeated system calls (optimization)
            try {
                cachedIsDarkTheme = StashWebViewUtils.isDarkTheme(this);
                cachedIsTablet = StashWebViewUtils.isTablet(this);
                cachedDisplayMetrics = getResources().getDisplayMetrics();
                // Cache parsed colors (saves ~5-10ms per use)
                cachedDarkBgColor = Color.parseColor(StashWebViewUtils.COLOR_DARK_BG);
                cachedWhiteColor = Color.WHITE;
                cachedDragHandleColor = Color.parseColor(COLOR_DRAG_HANDLE);
                cachedHomeTextColor = Color.parseColor(COLOR_HOME_TEXT);
                cachedDarkStrokeColor = Color.parseColor(COLOR_DARK_STROKE);
                cachedLightStrokeColor = Color.parseColor(COLOR_LIGHT_STROKE);
                cachedLightBgColor = Color.parseColor(COLOR_LIGHT_BG);
                cachedDimBgColor = Color.parseColor(StashWebViewUtils.COLOR_BACKGROUND_DIM);
            } catch (Exception e) {
                Log.e(TAG, "Error caching values: " + e.getMessage(), e);
                // Fallback values
                cachedIsDarkTheme = false;
                cachedIsTablet = false;
                cachedDisplayMetrics = getResources().getDisplayMetrics();
                cachedDarkBgColor = Color.parseColor(StashWebViewUtils.COLOR_DARK_BG);
                cachedWhiteColor = Color.WHITE;
            }
            
            // Cache low-end detection for performance optimizations
            try {
                isVeryLowEnd = StashWebViewUtils.isVeryLowEndDevice(this);
                if (isVeryLowEnd) {
                    Log.d(TAG, "Very low-end device detected - enabling performance optimizations");
                }
            } catch (Exception e) {
                Log.e(TAG, "Error checking low-end device: " + e.getMessage(), e);
                isVeryLowEnd = false;
            }
            
            try {
                if (usePopup) {
                    setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR);
                } else if (!cachedIsTablet) {
                    setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT);
                }
            } catch (Exception e) {
                Log.e(TAG, "Error setting orientation: " + e.getMessage(), e);
            }
            
            Window window = getWindow();
            if (window != null) {
                try {
                    // Always use transparent window - we use our own backdrop view
                    window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
                    
                    requestWindowFeature(Window.FEATURE_NO_TITLE);
                    window.addFlags(WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED);
                    window.addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS);
                } catch (Exception e) {
                    Log.e(TAG, "Error configuring window: " + e.getMessage(), e);
                }
            }
            
            createUI();
            
            if (cachedPlugin.enableTimingLogs) {
                long onCreateTime = System.currentTimeMillis() - activityCreateStartTime;
                Log.d(TAG, "⏱️ [TIMING] Activity.onCreate() completed in: " + onCreateTime + "ms");
            }
        } catch (Exception e) {
            Log.e(TAG, "Error in onCreate: " + e.getMessage(), e);
            finish();
        }
    }
    
    private void createUI() {
        try {
            rootLayout = new FrameLayout(this);
            rootLayout.setBackgroundColor(Color.TRANSPARENT);
            
            // Use cached value instead of calling isTablet() again
            boolean isTablet = cachedIsTablet;
            
            // Create separate backdrop view for independent fade animation
            backdropView = new View(this);
            backdropView.setLayoutParams(new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, 
                FrameLayout.LayoutParams.MATCH_PARENT));
            try {
                if (wasLandscapeBeforePortrait && !isTablet && !usePopup) {
                    backdropView.setBackgroundColor(Color.BLACK);
                } else {
                    backdropView.setBackgroundColor(cachedDimBgColor);
                }
            } catch (Exception e) {
                Log.e(TAG, "Error setting background color: " + e.getMessage(), e);
                backdropView.setBackgroundColor(Color.parseColor("#80000000"));
            }
            rootLayout.addView(backdropView);
            
            try {
                if (usePopup) {
                    createPopup();
                } else {
                    createCard();
                }
            } catch (Exception e) {
                Log.e(TAG, "Error creating UI: " + e.getMessage(), e);
                finish();
                return;
            }
            
            if (!usePopup && cardContainer != null) {
                // Make backdrop dismiss when tapped
                backdropView.setOnClickListener(v -> {
                    try {
                        if (!isDismissing && !isPurchaseProcessing) {
                            dismissWithAnimation();
                        }
                    } catch (Exception e) {
                        Log.e(TAG, "Error in backdrop click handler: " + e.getMessage(), e);
                    }
                });
                cardContainer.setOnClickListener(v -> {});
            }
            
            setContentView(rootLayout);
        } catch (Exception e) {
            Log.e(TAG, "Error in createUI: " + e.getMessage(), e);
            finish();
        }
    }
    
    private void configureCardContainer(boolean isTablet, int cardWidth, int cardHeight) {
        cardContainer = new FrameLayout(this);
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(cardWidth, cardHeight);
        params.gravity = isTablet ? Gravity.CENTER : (Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        cardContainer.setLayoutParams(params);
        
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(cachedIsDarkTheme ? cachedDarkBgColor : cachedWhiteColor);
        float radius = StashWebViewUtils.dpToPx(this, (int)CORNER_RADIUS_DP);
        
        if (isTablet) {
            bg.setCornerRadius(radius);
        } else {
            bg.setCornerRadii(new float[]{radius, radius, radius, radius, 0, 0, 0, 0});
        }
        cardContainer.setBackground(bg);
        
        // Reduce elevation on low-end devices (expensive to render)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            float elevation = isVeryLowEnd ? 
                StashWebViewUtils.dpToPx(this, 8) : // Reduced from 24dp
                StashWebViewUtils.dpToPx(this, (int)ELEVATION_DP);
            cardContainer.setElevation(elevation);
            
            // Simplify corner radius on very low-end (reduce complexity)
            if (!isVeryLowEnd) {
                cardContainer.setOutlineProvider(new ViewOutlineProvider() {
                    @Override
                    public void getOutline(View view, Outline outline) {
                        if (isTablet) {
                            outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), radius);
                        } else {
                            outline.setRoundRect(0, 0, view.getWidth(), view.getHeight() + (int)radius, radius);
                        }
                    }
                });
                cardContainer.setClipToOutline(true);
            }
        }
    }

    private int[] calculateTabletCardSize(DisplayMetrics metrics) {
        int landscapeWidth = Math.max(metrics.widthPixels, metrics.heightPixels);
        int landscapeHeight = Math.min(metrics.widthPixels, metrics.heightPixels);
        
        float targetAspectRatio = 0.75f;
        
        float maxCardWidth = landscapeWidth * 0.8f;
        float maxCardHeight = landscapeHeight * 0.75f;
        
        if (maxCardWidth <= 0 || maxCardHeight <= 0) {
            return new int[]{600, 700};
        }
        
        int cardWidth, cardHeight;
        
        if (maxCardWidth / targetAspectRatio <= maxCardHeight) {
            cardWidth = (int)maxCardWidth;
            cardHeight = (int)(cardWidth / targetAspectRatio);
        } else {
            cardHeight = (int)maxCardHeight;
            cardWidth = (int)(cardHeight * targetAspectRatio);
        }
        
        if (cardWidth < 400 || cardHeight < 500) {
            return new int[]{600, 700};
        }
        
        return new int[]{cardWidth, cardHeight};
    }
    
    private void createCard() {
        // Use cached DisplayMetrics and isTablet (optimization)
        DisplayMetrics metrics = cachedDisplayMetrics;
        boolean isTablet = cachedIsTablet;
        
        int cardWidth, cardHeight;
        
        if (isTablet) {
            int[] cardSize = calculateTabletCardSize(metrics);
            cardWidth = cardSize[0];
            cardHeight = cardSize[1];
            isExpanded = true;
        } else {
            float effectiveHeightRatio;
            if (wasLandscapeBeforePortrait) {
                effectiveHeightRatio = CARD_HEIGHT_EXPANDED;
                isExpanded = true;
            } else {
                effectiveHeightRatio = CARD_HEIGHT_NORMAL;
                isExpanded = false;
            }
            cardHeight = (int)(metrics.heightPixels * effectiveHeightRatio);
            cardWidth = FrameLayout.LayoutParams.MATCH_PARENT;
        }
        
        configureCardContainer(cachedIsTablet, cardWidth, cardHeight);
        
        addWebView();
        
        // Defer non-critical UI for ALL devices (optimization - saves 30-80ms)
        // WebView starts loading immediately, UI elements appear shortly after
        cardContainer.postDelayed(() -> {
            addDragHandle();
            addHomeButton();
        }, 200); // Small delay - user won't notice, but saves critical path time
        
        rootLayout.addView(cardContainer);
        
        // Skip animations on very low-end devices for faster display
        if (isVeryLowEnd) {
            // Show immediately without animation
            cardContainer.setAlpha(1f);
            cardContainer.setTranslationY(0);
            if (cachedPlugin.enableTimingLogs) {
                uiVisibleTime = System.currentTimeMillis();
                long timeToVisible = uiVisibleTime - activityCreateStartTime;
                Log.d(TAG, "⏱️ [TIMING] UI visible (no animation, low-end): " + timeToVisible + "ms");
            }
        } else if (isTablet) {
            animateFadeIn();
        } else {
            animateSlideUp();
        }
    }
    
    private void createPopup() {
        // Use cached DisplayMetrics (saves ~1-2ms)
        DisplayMetrics metrics = cachedDisplayMetrics != null ? cachedDisplayMetrics : getResources().getDisplayMetrics();
        int size = (int)(Math.min(metrics.widthPixels, metrics.heightPixels) * 0.75f);
        
        configureCardContainer(true, size, size);
        
        addWebView();
        rootLayout.addView(cardContainer);
        animateFadeIn();
    }
    
    private void addDragHandle() {
        LinearLayout dragArea = new LinearLayout(this);
        dragArea.setOrientation(LinearLayout.VERTICAL);
        dragArea.setGravity(Gravity.CENTER_HORIZONTAL);
        dragArea.setPadding(StashWebViewUtils.dpToPx(this, 20), StashWebViewUtils.dpToPx(this, 16), StashWebViewUtils.dpToPx(this, 20), StashWebViewUtils.dpToPx(this, 16));
        
        View handle = new View(this);
        GradientDrawable handleBg = new GradientDrawable();
        handleBg.setColor(cachedDragHandleColor);
        handleBg.setCornerRadius(StashWebViewUtils.dpToPx(this, 2));
        handle.setBackground(handleBg);
        handle.setLayoutParams(new LinearLayout.LayoutParams(StashWebViewUtils.dpToPx(this, 36), StashWebViewUtils.dpToPx(this, 5)));
        dragArea.addView(handle);
        
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
            StashWebViewUtils.dpToPx(this, 120), FrameLayout.LayoutParams.WRAP_CONTENT);
        params.gravity = Gravity.TOP | Gravity.CENTER_HORIZONTAL;
        dragArea.setLayoutParams(params);
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            dragArea.setElevation(StashWebViewUtils.dpToPx(this, 8));
        }
        
        addDragTouchHandling(dragArea);
        cardContainer.addView(dragArea);
    }
    
    private class DragHandleTouchListener implements View.OnTouchListener {
        private float initialY;
        private float initialTranslationY;
        private boolean isDragging;
        
        @Override
        public boolean onTouch(View v, MotionEvent event) {
            if (cardContainer == null) return false;
            
            if (isPurchaseProcessing) {
                return false;
            }
            
            boolean isTablet = StashWebViewUtils.isTablet(StashPayCardPortraitActivity.this);
            
            switch (event.getAction()) {
                case MotionEvent.ACTION_DOWN:
                    initialY = event.getRawY();
                    initialTranslationY = cardContainer.getTranslationY();
                    isDragging = false;
                    return true;
                
                case MotionEvent.ACTION_MOVE:
                    float deltaY = event.getRawY() - initialY;
                    
                    if (Math.abs(deltaY) > StashWebViewUtils.dpToPx(StashPayCardPortraitActivity.this, 10)) {
                        isDragging = true;
                        
                        // On tablets, only allow drag down (dismiss), not drag up (expand)
                        if (deltaY > 0) {
                            float newTranslationY = initialTranslationY + deltaY;
                            cardContainer.setTranslationY(newTranslationY);
                            // Use cached DisplayMetrics (saves ~1-2ms)
                            DisplayMetrics metrics = cachedDisplayMetrics != null ? cachedDisplayMetrics : getResources().getDisplayMetrics();
                            float progress = Math.min(deltaY / metrics.heightPixels, 1.0f);
                            cardContainer.setAlpha(1.0f - (progress * 0.5f));
                        } else if (deltaY < 0 && !isTablet && !isExpanded && !wasLandscapeBeforePortrait) {
                            // Drag up to expand - disabled for tablets
                            float dragProgress = Math.min(Math.abs(deltaY) / StashWebViewUtils.dpToPx(StashPayCardPortraitActivity.this, 100), 1.0f);
                            cardContainer.setScaleX(1.0f + (dragProgress * 0.02f));
                            cardContainer.setScaleY(1.0f + (dragProgress * 0.02f));
                        }
                    }
                    return true;
                
                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_CANCEL:
                    if (isDragging) {
                        float finalDeltaY = event.getRawY() - initialY;
                        // Use cached DisplayMetrics (saves ~1-2ms)
        DisplayMetrics metrics = cachedDisplayMetrics != null ? cachedDisplayMetrics : getResources().getDisplayMetrics();
                        
                        if (finalDeltaY > 0) {
                            int dismissThreshold = isTablet ? (int)(metrics.heightPixels * 0.15f) 
                                                             : (int)(metrics.heightPixels * 0.25f);
                            if (finalDeltaY > dismissThreshold) {
                                if (isTablet) {
                                    // For tablets, use fade dismiss animation
                                    animateTabletDismiss();
                                } else {
                                animateDismiss();
                                }
                            } else {
                                animateSnapBack();
                            }
                        } else if (finalDeltaY < 0 && !isTablet && !isExpanded && !wasLandscapeBeforePortrait) {
                            // Drag up to expand - only for phones, not tablets
                            if (Math.abs(finalDeltaY) > StashWebViewUtils.dpToPx(StashPayCardPortraitActivity.this, 80)) {
                                animateExpand();
                            } else {
                                animateSnapBack();
                            }
                        } else {
                            cardContainer.setScaleX(1.0f);
                            cardContainer.setScaleY(1.0f);
                            animateSnapBack();
                        }
                    }
                    return true;
            }
            return false;
        }
    }

    private void addDragTouchHandling(View dragArea) {
        dragArea.setOnTouchListener(new DragHandleTouchListener());
    }
    
    private void animateDismiss() {
        if (cardContainer == null) return;
        if (isPurchaseProcessing) return;
        int height = cardContainer.getHeight();
        if (height == 0) {
            // Use cached DisplayMetrics (saves ~1-2ms)
            DisplayMetrics metrics = cachedDisplayMetrics != null ? cachedDisplayMetrics : getResources().getDisplayMetrics();
            height = (int)(metrics.heightPixels * CARD_HEIGHT_NORMAL);
        }
        
        // Fade out the backdrop independently
        if (backdropView != null) {
            backdropView.animate()
                .alpha(0f)
                .setDuration(250)
                .setInterpolator(new android.view.animation.AccelerateInterpolator())
                .start();
        }
        
        cardContainer.animate()
            .translationY(height)
            .setDuration(300)
            .setInterpolator(new android.view.animation.AccelerateInterpolator())
            .withEndAction(this::finish)
            .start();
    }
    
    private void animateTabletDismiss() {
        if (cardContainer == null) return;
        if (isPurchaseProcessing) return;
        
        isDismissing = true;
        
        // Fade out the backdrop
        if (backdropView != null) {
            backdropView.animate()
                .alpha(0f)
                .setDuration(200)
                .setInterpolator(new android.view.animation.AccelerateInterpolator())
                .start();
        }
        
        // Scale down and fade out the card for a seamless tablet dismiss
        cardContainer.animate()
            .alpha(0f)
            .scaleX(0.9f)
            .scaleY(0.9f)
            .setDuration(200)
            .setInterpolator(new android.view.animation.AccelerateInterpolator())
            .withEndAction(this::finishActivityWithNoAnimation)
            .start();
    }
    
    /**
     * Gets appropriate interpolator based on device capabilities.
     * Uses simpler interpolators on low-end devices for better performance.
     */
    private android.view.animation.Interpolator getInterpolator() {
        if (isVeryLowEnd) {
            // Use simple linear interpolator on very low-end devices
            return new android.view.animation.LinearInterpolator();
        }
        // Use spring interpolator on capable devices for smooth animations
        return new SpringInterpolator();
    }
    
    private void animateCardHeight(int targetHeight, int duration) {
        FrameLayout.LayoutParams params = (FrameLayout.LayoutParams)cardContainer.getLayoutParams();
        android.animation.ValueAnimator heightAnimator = android.animation.ValueAnimator.ofInt(params.height, targetHeight);
        heightAnimator.setDuration(duration);
        heightAnimator.setInterpolator(getInterpolator());
        heightAnimator.addUpdateListener(animation -> {
            params.height = (Integer)animation.getAnimatedValue();
            cardContainer.setLayoutParams(params);
        });
        heightAnimator.start();
    }

    private void animateCardWidth(int targetWidth, int duration) {
        FrameLayout.LayoutParams params = (FrameLayout.LayoutParams)cardContainer.getLayoutParams();
        android.animation.ValueAnimator widthAnimator = android.animation.ValueAnimator.ofInt(params.width, targetWidth);
        widthAnimator.setDuration(duration);
        widthAnimator.setInterpolator(getInterpolator());
        widthAnimator.addUpdateListener(animation -> {
            params.width = (Integer)animation.getAnimatedValue();
            cardContainer.setLayoutParams(params);
        });
        widthAnimator.start();
    }

    private void animateExpand() {
        if (cardContainer == null) return;
        // Use cached DisplayMetrics and isTablet (optimization)
        DisplayMetrics metrics = cachedDisplayMetrics != null ? cachedDisplayMetrics : getResources().getDisplayMetrics();
        boolean isTablet = cachedIsTablet;
        
        FrameLayout.LayoutParams params = (FrameLayout.LayoutParams)cardContainer.getLayoutParams();
        
        int expandedHeight = (int)(metrics.heightPixels * CARD_HEIGHT_EXPANDED);
        int expandedWidth;
        
        if (isTablet) {
            int[] cardSize = calculateTabletCardSize(metrics);
            expandedWidth = cardSize[0];
            expandedHeight = cardSize[1];
        } else {
            expandedWidth = params.width;
        }
        
        animateCardHeight(expandedHeight, isTablet ? 350 : 450);
        
        if (isTablet) {
            animateCardWidth(expandedWidth, 350);
        }
        
        cardContainer.animate()
            .translationY(0)
            .alpha(1f)
            .scaleX(1f)
            .scaleY(1f)
            .setDuration(isTablet ? 350 : 450)
            .setInterpolator(getInterpolator())
            .start();
        
        isExpanded = true;
    }
    
    private void animateCollapse() {
        if (cardContainer == null || !isExpanded) return;
        // Use cached DisplayMetrics and isTablet (optimization)
        DisplayMetrics metrics = cachedDisplayMetrics != null ? cachedDisplayMetrics : getResources().getDisplayMetrics();
        boolean isTablet = cachedIsTablet;
        
        FrameLayout.LayoutParams params = (FrameLayout.LayoutParams)cardContainer.getLayoutParams();
        
        int collapsedHeight;
        int collapsedWidth;
        
        if (isTablet) {
            int[] defaultCardSize = calculateTabletCardSize(metrics);
            collapsedWidth = (int)(defaultCardSize[0] * 0.7f);
            collapsedHeight = (int)(defaultCardSize[1] * 0.7f);
            
            animateCardWidth(collapsedWidth, 320);
        } else {
            collapsedHeight = (int)(metrics.heightPixels * CARD_HEIGHT_NORMAL);
            collapsedWidth = params.width;
        }
        
        animateCardHeight(collapsedHeight, isTablet ? 320 : 380);
        
        cardContainer.animate()
            .translationY(0)
            .alpha(1f)
            .scaleX(1f)
            .scaleY(1f)
            .setDuration(isTablet ? 320 : 380)
            .setInterpolator(getInterpolator())
            .start();
        
        isExpanded = false;
    }
    
    private void animateSnapBack() {
        if (cardContainer == null) return;
        // Use cached DisplayMetrics (saves ~1-2ms)
        DisplayMetrics metrics = cachedDisplayMetrics != null ? cachedDisplayMetrics : getResources().getDisplayMetrics();
        boolean isTablet = StashWebViewUtils.isTablet(this);
        
        int targetHeight;
        if (wasLandscapeBeforePortrait && !isTablet) {
            targetHeight = (int)(metrics.heightPixels * CARD_HEIGHT_EXPANDED);
            isExpanded = true;
        } else if (isExpanded) {
            targetHeight = (int)(metrics.heightPixels * CARD_HEIGHT_EXPANDED);
        } else {
            targetHeight = (int)(metrics.heightPixels * CARD_HEIGHT_NORMAL);
        }
        
        FrameLayout.LayoutParams params = (FrameLayout.LayoutParams)cardContainer.getLayoutParams();
        if (params.height != targetHeight) {
            animateCardHeight(targetHeight, 450);
        }
        
        cardContainer.animate()
            .translationY(0)
            .alpha(1f)
            .scaleX(1f)
            .scaleY(1f)
            .setDuration(450)
            .setInterpolator(getInterpolator())
            .start();
    }

    private void addWebView() {
        if (url == null || url.isEmpty() || cardContainer == null) {
            Log.e(TAG, "Invalid parameters in addWebView");
            return;
        }
        
        try {
            // Use cached plugin instance (saves ~2-5ms per call)
            if (cachedPlugin == null) cachedPlugin = StashPayCardPlugin.getInstance();
            if (cachedPlugin.enableTimingLogs) {
                webViewCreateStartTime = System.currentTimeMillis();
                Log.d(TAG, "⏱️ [TIMING] Starting WebView creation");
            }
            
            // Try to reuse pre-warmed WebView from plugin, otherwise create new
            webView = cachedPlugin.getOrCreateWebView(this);
            
            // Set hardware acceleration immediately for faster rendering
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
                webView.setLayerType(View.LAYER_TYPE_HARDWARE, null);
            }
            
            // Apply only CRITICAL WebView settings before load (optimization - saves 20-50ms)
            // Non-critical settings will be applied after page starts loading
            try {
                WebSettings settings = webView.getSettings();
                // Critical settings only
                settings.setJavaScriptEnabled(true);
                settings.setDomStorageEnabled(true);
                settings.setLoadWithOverviewMode(true);
                settings.setUseWideViewPort(true);
                
                // Use cached theme value
                boolean isLowEnd = StashWebViewUtils.isLowEndDevice() || isVeryLowEnd;
                
                // Aggressive optimizations for low-memory devices (when pre-warming is disabled)
                if (isLowEnd || isVeryLowEnd) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                        settings.setLoadsImagesAutomatically(false);
                    }
                    
                    // Disable safe browsing to reduce network overhead (saves 50-100ms)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        settings.setSafeBrowsingEnabled(false);
                    }
                    
                    // Set high render priority for faster rendering
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        settings.setRenderPriority(WebSettings.RenderPriority.HIGH);
                    }
                    
                    // Disable mixed content checking (saves processing)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
                    }
                }
                
                // Apply remaining settings after load starts (non-blocking)
                // Cache settings reference to avoid repeated getSettings() calls
                final WebSettings finalSettings = settings;
                final boolean finalIsLowEnd = isLowEnd;
                webView.post(() -> {
                    try {
                        StashWebViewUtils.configureWebViewSettings(webView, cachedIsDarkTheme, finalIsLowEnd);
                        if (finalIsLowEnd && Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                            webView.postDelayed(() -> {
                                try {
                                    finalSettings.setLoadsImagesAutomatically(true);
                                } catch (Exception e) {
                                    Log.e(TAG, "Error re-enabling images: " + e.getMessage(), e);
                                }
                            }, 1000);
                        }
                    } catch (Exception e) {
                        Log.e(TAG, "Error applying deferred WebView settings: " + e.getMessage(), e);
                    }
                });
            } catch (Exception e) {
                Log.e(TAG, "Error configuring WebView settings: " + e.getMessage(), e);
            }
        
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
                try {
                    super.onPageStarted(view, url, favicon);
                    
                    StashPayCardPlugin plugin = StashPayCardPlugin.getInstance();
                    if (plugin.enableTimingLogs) {
                        pageLoadStartTime = System.currentTimeMillis();
                        long webViewSetupTime = pageLoadStartTime - webViewCreateStartTime;
                        long timeFromLoadUrlToStart = pageLoadStartTime - loadUrlCallTime;
                        long totalTime = pageLoadStartTime - activityCreateStartTime;
                        Log.d(TAG, "⏱️ [TIMING] WebView setup completed: " + webViewSetupTime + "ms");
                        Log.d(TAG, "⏱️ [TIMING] Time from loadUrl() to onPageStarted(): " + timeFromLoadUrlToStart + "ms");
                        Log.d(TAG, "⏱️ [TIMING] Real page load started (total time from onCreate: " + totalTime + "ms)");
                    }
                    
                    showLoading();
                    injectSDK(view);
                    checkProvider(url);
                    checkGooglePayRedirect(url);
                } catch (Exception e) {
                    Log.e(TAG, "Error in onPageStarted: " + e.getMessage(), e);
                }
            }
            
            @Override
            public void onPageFinished(WebView view, String url) {
                try {
                    // Skip super call if not needed (saves ~1-2ms)
                    if (cachedPlugin == null) cachedPlugin = StashPayCardPlugin.getInstance();
                    if (cachedPlugin.enableTimingLogs && pageLoadStartTime > 0) {
                        long pageLoadTime = System.currentTimeMillis() - pageLoadStartTime;
                        long totalTime = System.currentTimeMillis() - activityCreateStartTime;
                        Log.d(TAG, "⏱️ [TIMING] Page load completed: " + pageLoadTime + "ms");
                        Log.d(TAG, "⏱️ [TIMING] ⭐ TOTAL TIME (onCreate to page loaded): " + totalTime + "ms");
                    }
                    
                    hideLoading();
                    // Removed redundant injectSDK() call - already injected in onPageStarted (optimization)
                    checkProvider(url);
                    checkGooglePayRedirect(url);
                } catch (Exception e) {
                    Log.e(TAG, "Error in onPageFinished: " + e.getMessage(), e);
                }
            }
            
            @Override
            public void onReceivedError(WebView view, android.webkit.WebResourceRequest request, 
                                        android.webkit.WebResourceError error) {
                // Skip super call and only log if error exists (saves ~1-2ms)
                if (error != null) {
                    try {
                        Log.e(TAG, "WebView error: " + error.getDescription());
                    } catch (Exception e) {
                        // Ignore logging errors
                    }
                }
            }
        });
        
            try {
                // Pre-compute URL with theme (using cached value - optimization)
                String urlWithTheme;
                try {
                    urlWithTheme = StashWebViewUtils.appendThemeQueryParameter(url, cachedIsDarkTheme);
                } catch (Exception e) {
                    Log.e(TAG, "Error appending theme parameter: " + e.getMessage(), e);
                    urlWithTheme = url;
                }
                
                // Set up WebView clients BEFORE loading (required for callbacks)
                webView.setWebChromeClient(new WebChromeClient());
                webView.addJavascriptInterface(new JSInterface(), "StashAndroid");
                webView.setBackgroundColor(cachedIsDarkTheme ? cachedDarkBgColor : cachedWhiteColor);
                
                FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
                webView.setLayoutParams(params);
                
                // Add to view hierarchy BEFORE loading (WebView needs to be attached)
                cardContainer.addView(webView);
                
                // CRITICAL: Load URL immediately after adding to hierarchy (saves 50-100ms)
                if (cachedPlugin.enableTimingLogs) {
                    long timeToLoadUrl = System.currentTimeMillis() - webViewCreateStartTime;
                    Log.d(TAG, "⏱️ [TIMING] Calling loadUrl() (time since WebView creation: " + timeToLoadUrl + "ms)");
                }
                webView.loadUrl(urlWithTheme);
                loadUrlCallTime = System.currentTimeMillis();
            } catch (Exception e) {
                Log.e(TAG, "Error setting up WebView: " + e.getMessage(), e);
                finish();
            }
        } catch (Exception e) {
            Log.e(TAG, "Error creating WebView: " + e.getMessage(), e);
            finish();
        }
    }
    
    private void addHomeButton() {
        homeButton = new Button(this);
        homeButton.setText("⌂");
        homeButton.setTextSize(18);
        homeButton.setTextColor(cachedHomeTextColor);
        homeButton.setGravity(Gravity.CENTER);
        homeButton.setPadding(0, 0, 0, 0);
        
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(cachedIsDarkTheme ? cachedDarkBgColor : cachedLightBgColor);
        bg.setCornerRadius(StashWebViewUtils.dpToPx(this, 20));
        bg.setStroke(StashWebViewUtils.dpToPx(this, 1), cachedIsDarkTheme ? cachedDarkStrokeColor : cachedLightStrokeColor);
        homeButton.setBackground(bg);
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            homeButton.setElevation(StashWebViewUtils.dpToPx(this, 6));
        }
        
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(StashWebViewUtils.dpToPx(this, 36), StashWebViewUtils.dpToPx(this, 36));
        params.gravity = Gravity.TOP | Gravity.START;
        params.setMargins(StashWebViewUtils.dpToPx(this, 12), StashWebViewUtils.dpToPx(this, 12), 0, 0);
        homeButton.setLayoutParams(params);
        homeButton.setVisibility(View.GONE);
        homeButton.setOnClickListener(v -> {
            if (initialURL != null && webView != null) {
                String urlWithTheme = StashWebViewUtils.appendThemeQueryParameter(initialURL, cachedIsDarkTheme);
                webView.loadUrl(urlWithTheme);
            }
        });
        
        cardContainer.addView(homeButton);
    }
    
    private void injectSDK(WebView view) {
        view.evaluateJavascript(StashWebViewUtils.JS_SDK_SCRIPT, null);
    }
    
    private void checkProvider(String url) {
        if (homeButton == null || url == null) return;
        // Optimize: cache toLowerCase result and use indexOf instead of contains (faster)
        int len = url.length();
        if (len < 5) return; // Too short to contain provider names
        String lower = url.toLowerCase();
        boolean show = lower.indexOf("klarna") >= 0 || lower.indexOf("paypal") >= 0 || lower.indexOf("stripe") >= 0;
        // Already on UI thread - remove runOnUiThread overhead (saves ~2-5ms)
        homeButton.setVisibility(show ? View.VISIBLE : View.GONE);
    }
    
    private void checkGooglePayRedirect(String url) {
        if (url == null || googlePayRedirectHandled || initialURL == null || initialURL.isEmpty()) {
            return;
        }
        
        // Optimize: use indexOf instead of contains (faster)
        if (url.toLowerCase().indexOf("pay.google.com") >= 0) {
            googlePayRedirectHandled = true;
            openGooglePayInBrowser(initialURL);
        }
    }
    
    private void openGooglePayInBrowser(String url) {
        try {
            // Optimize: Use indexOf instead of Uri parsing (saves ~5-10ms)
            String urlWithParam;
            if (url != null && !url.isEmpty()) {
                String separator = url.indexOf('?') >= 0 ? "&" : "?";
                urlWithParam = url + separator + "dpm=gpay";
            } else {
                urlWithParam = url;
            }
            
            openWithChromeCustomTabs(urlWithParam, this);
            dismissWithAnimation();
        } catch (Exception e) {
            Log.e(TAG, "Failed to open Google Pay URL: " + e.getMessage());
        }
    }
    
    private void openWithChromeCustomTabs(String url, Activity activity) {
        try {
            if (isChromeCustomTabsAvailable()) {
                Log.d(TAG, "Opening Google Pay URL with Chrome Custom Tabs");
                openWithReflectionChromeCustomTabs(url, activity);
            } else {
                Log.w(TAG, "Chrome Custom Tabs not available. Falling back to default browser.");
                openInSystemBrowser(url);
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to open browser: " + e.getMessage());
            try {
                openInSystemBrowser(url);
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
    }
    
    private void openInSystemBrowser(String url) {
        try {
            Intent browserIntent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
            browserIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(browserIntent);
            dismissWithAnimation();
        } catch (Exception e) {
            Log.e(TAG, "Failed to open URL in system browser: " + e.getMessage());
        }
    }
    
    private void showLoading() {
        // Already on UI thread - remove runOnUiThread overhead (saves ~2-5ms)
        if (loadingIndicator != null && loadingIndicator.getParent() != null) {
            ((ViewGroup)loadingIndicator.getParent()).removeView(loadingIndicator);
        }
        
        if (cardContainer != null) {
            loadingIndicator = StashWebViewUtils.createAndShowLoading(this, cardContainer);
            if (loadingIndicator != null) {
                loadingIndicator.setVisibility(View.VISIBLE);
                loadingIndicator.requestLayout();
            }
        }
    }
    
    private void hideLoading() {
        // Already on UI thread - remove runOnUiThread overhead (saves ~2-5ms)
        StashWebViewUtils.hideLoading(loadingIndicator);
        loadingIndicator = null;
    }
    
    private void animateSlideUp() {
        // Use cached DisplayMetrics (saves ~1-2ms)
        DisplayMetrics metrics = cachedDisplayMetrics != null ? cachedDisplayMetrics : getResources().getDisplayMetrics();
        cardContainer.setTranslationY(metrics.heightPixels);
        
        cardContainer.post(() -> {
            if (cachedPlugin.enableTimingLogs) {
                uiVisibleTime = System.currentTimeMillis();
                long timeToVisible = uiVisibleTime - activityCreateStartTime;
                Log.d(TAG, "⏱️ [TIMING] UI visible (onCreate to visible): " + timeToVisible + "ms");
            }
            
            // Use faster, simpler animation on low-end devices
            int duration = isVeryLowEnd ? 150 : 300;
            android.view.animation.Interpolator interpolator = isVeryLowEnd ?
                new android.view.animation.LinearInterpolator() : // Simpler, faster
                new android.view.animation.AccelerateDecelerateInterpolator();
            
            cardContainer.animate()
                .translationY(0)
                .setDuration(duration)
                .setInterpolator(interpolator)
                .start();
        });
    }
    
    private void animateFadeIn() {
        cardContainer.setAlpha(0f);
        cardContainer.setScaleX(0.9f);
        cardContainer.setScaleY(0.9f);
        
        if (cachedPlugin.enableTimingLogs) {
            uiVisibleTime = System.currentTimeMillis();
            long timeToVisible = uiVisibleTime - activityCreateStartTime;
            Log.d(TAG, "⏱️ [TIMING] UI visible (onCreate to visible): " + timeToVisible + "ms");
        }
        
        // Use faster, simpler animation on low-end devices
        int duration = isVeryLowEnd ? 100 : 200;
        android.view.animation.Interpolator interpolator = isVeryLowEnd ?
            new android.view.animation.LinearInterpolator() : // Simpler, faster
            new android.view.animation.AccelerateDecelerateInterpolator();
        
        cardContainer.animate()
            .alpha(1f)
            .scaleX(1f)
            .scaleY(1f)
            .setDuration(duration)
            .setInterpolator(interpolator)
            .start();
    }
    
    private void dismissWithAnimation() {
        if (isDismissing) return;
        isDismissing = true;
        
        try {
            try {
                setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LOCKED);
            } catch (Exception e) {
                Log.e(TAG, "Error locking orientation: " + e.getMessage(), e);
            }
            
            if (cardContainer == null) {
                finishActivityWithNoAnimation();
                return;
            }
            
            // Fade out the backdrop independently
            if (backdropView != null) {
                backdropView.animate()
                    .alpha(0f)
                    .setDuration(350)
                    .setInterpolator(new android.view.animation.AccelerateInterpolator())
                    .start();
            }
            
            // Use cached isTablet value (optimization)
            boolean isTablet = cachedIsTablet;
            
            if (usePopup || isTablet) {
                // Use fade animation for popups and tablets
                try {
                    cardContainer.animate()
                        .alpha(0f)
                        .scaleX(0.9f)
                        .scaleY(0.9f)
                        .setDuration(200)
                        .setInterpolator(new android.view.animation.AccelerateInterpolator())
                        .withEndAction(() -> {
                            try {
                                finishActivityWithNoAnimation();
                            } catch (Exception e) {
                                Log.e(TAG, "Error in animation end action: " + e.getMessage(), e);
                                finish();
                            }
                        })
                        .start();
                } catch (Exception e) {
                    Log.e(TAG, "Error animating popup dismissal: " + e.getMessage(), e);
                    finishActivityWithNoAnimation();
                }
            } else {
                // Use slide animation for phones
                try {
                    cardContainer.animate()
                        .translationY(cardContainer.getHeight())
                        .setDuration(300)
                        .setInterpolator(new android.view.animation.AccelerateInterpolator())
                        .withEndAction(() -> {
                            try {
                                finishActivityWithNoAnimation();
                            } catch (Exception e) {
                                Log.e(TAG, "Error in animation end action: " + e.getMessage(), e);
                                finish();
                            }
                        })
                        .start();
                } catch (Exception e) {
                    Log.e(TAG, "Error animating card dismissal: " + e.getMessage(), e);
                    finishActivityWithNoAnimation();
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Error in dismissWithAnimation: " + e.getMessage(), e);
            try {
                finish();
            } catch (Exception e2) {
                Log.e(TAG, "Error finishing activity: " + e2.getMessage(), e2);
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
    
    private void notifyListenerAndDismiss(String messageType, String messageBody, boolean success) {
        try {
            runOnUiThread(() -> {
                try {
                    if (success) {
                        callbackSent = true;
                        isPurchaseProcessing = false;
                    }
                    
                    StashPayCard.StashPayListener listener = StashPayCard.getInstance().getListener();
                    if (listener != null) {
                        switch (messageType) {
                            case "success":
                                listener.onPaymentSuccess();
                                break;
                            case "failure":
                                listener.onPaymentFailure();
                                break;
                            case "optin":
                                listener.onOptInResponse(messageBody);
                                break;
                        }
                    }
                    
                    dismissWithAnimation();
                } catch (Exception e) {
                    Log.e(TAG, "Error in notifyListenerAndDismiss UI thread: " + e.getMessage(), e);
                    try {
                        finish();
                    } catch (Exception e2) {
                        Log.e(TAG, "Error finishing activity: " + e2.getMessage(), e2);
                    }
                }
            });
        } catch (Exception e) {
            Log.e(TAG, "Error scheduling notifyListenerAndDismiss: " + e.getMessage(), e);
        }
    }

    private class JSInterface {
        @JavascriptInterface
        public void onPaymentSuccess() {
            try {
                notifyListenerAndDismiss("success", "", true);
            } catch (Exception e) {
                Log.e(TAG, "Error in onPaymentSuccess: " + e.getMessage(), e);
            }
        }
        
        @JavascriptInterface
        public void onPaymentFailure() {
            try {
                notifyListenerAndDismiss("failure", "", true);
            } catch (Exception e) {
                Log.e(TAG, "Error in onPaymentFailure: " + e.getMessage(), e);
            }
        }
        
        @JavascriptInterface
        public void onPurchaseProcessing() {
            try {
                runOnUiThread(() -> {
                    try {
                        isPurchaseProcessing = true;
                    } catch (Exception e) {
                        Log.e(TAG, "Error setting purchase processing: " + e.getMessage(), e);
                    }
                });
            } catch (Exception e) {
                Log.e(TAG, "Error in onPurchaseProcessing: " + e.getMessage(), e);
            }
        }
        
        @JavascriptInterface
        public void setPaymentChannel(String optinType) {
            try {
                notifyListenerAndDismiss("optin", optinType != null ? optinType : "", false);
            } catch (Exception e) {
                Log.e(TAG, "Error in setPaymentChannel: " + e.getMessage(), e);
            }
        }
        
        @JavascriptInterface
        public void expand() {
            try {
                runOnUiThread(() -> {
                    try {
                        if (!usePopup && !isExpanded) {
                            animateExpand();
                        }
                    } catch (Exception e) {
                        Log.e(TAG, "Error in expand UI thread: " + e.getMessage(), e);
                    }
                });
            } catch (Exception e) {
                Log.e(TAG, "Error in expand: " + e.getMessage(), e);
            }
        }
        
        @JavascriptInterface
        public void collapse() {
            try {
                runOnUiThread(() -> {
                    try {
                        if (!usePopup && isExpanded) {
                            animateCollapse();
                        }
                    } catch (Exception e) {
                        Log.e(TAG, "Error in collapse UI thread: " + e.getMessage(), e);
                    }
                });
            } catch (Exception e) {
                Log.e(TAG, "Error in collapse: " + e.getMessage(), e);
            }
        }
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
        if (webView != null) {
            webView.onResume();
        }
    }
    
    @Override
    protected void onDestroy() {
        try {
            super.onDestroy();
            
            if (webView != null) {
                try {
                    webView.destroy();
                } catch (Exception e) {
                    Log.e(TAG, "Error destroying WebView: " + e.getMessage(), e);
                }
                webView = null;
            }
            
            if (!callbackSent) {
                callbackSent = true;
                try {
                    StashPayCard.StashPayListener listener = StashPayCard.getInstance().getListener();
                    if (listener != null) {
                        listener.onDialogDismissed();
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error sending dialog dismissed: " + e.getMessage(), e);
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Error in onDestroy: " + e.getMessage(), e);
        }
    }
    
    @Override
    public void onBackPressed() {
        if (isPurchaseProcessing) {
            return;
        }
        dismissWithAnimation();
    }
    
    @Override
    public void onConfigurationChanged(Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        
        if (!usePopup && cardContainer != null && rootLayout != null) {
            boolean isTablet = StashWebViewUtils.isTablet(this);
            if (isTablet) {
                rootLayout.removeAllViews();
                createUI();
            } else {
                if (wasLandscapeBeforePortrait) {
                    if (!isExpanded) {
                        animateExpand();
                    } else {
                        // Use cached DisplayMetrics (saves ~1-2ms)
        DisplayMetrics metrics = cachedDisplayMetrics != null ? cachedDisplayMetrics : getResources().getDisplayMetrics();
                        FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
                        int expandedHeight = (int)(metrics.heightPixels * CARD_HEIGHT_EXPANDED);
                        params.height = expandedHeight;
                        cardContainer.setLayoutParams(params);
                    }
                }
            }
        }
    }
}
