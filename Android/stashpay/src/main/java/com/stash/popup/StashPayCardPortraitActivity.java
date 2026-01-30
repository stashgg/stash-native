package com.stash.popup;

import android.animation.ValueAnimator;
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
    
    // Card size configuration (legacy)
    private float cardHeightRatio = 0.68f;
    private float cardWidthRatio = 1.0f;
    private float tabletWidthRatio = 0.8f;
    private float tabletHeightRatio = 0.75f;
    
    // Orientation-specific phone card configuration
    private float cardHeightRatioPortrait = 0.68f;
    private float cardHeightRatioLandscape = 0.5f;
    private float cardWidthRatioPortrait = 1.0f;
    private float cardWidthRatioLandscape = 0.8f;
    
    // Orientation-specific tablet card configuration
    private float tabletWidthRatioPortrait = 0.6f;
    private float tabletHeightRatioPortrait = 0.8f;
    private float tabletWidthRatioLandscape = 0.8f;
    private float tabletHeightRatioLandscape = 0.65f;
    
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
            
            url = intent.getStringExtra("url");
            initialURL = intent.getStringExtra("initialURL");
            usePopup = intent.getBooleanExtra("usePopup", false);
            wasLandscapeBeforePortrait = intent.getBooleanExtra("wasLandscape", false);
            
            // Read card size configuration (legacy)
            cardHeightRatio = intent.getFloatExtra("cardHeightRatio", 0.68f);
            cardWidthRatio = intent.getFloatExtra("cardWidthRatio", 1.0f);
            tabletWidthRatio = intent.getFloatExtra("tabletWidthRatio", 0.8f);
            tabletHeightRatio = intent.getFloatExtra("tabletHeightRatio", 0.75f);
            
            // Read orientation-specific card size configuration
            cardHeightRatioPortrait = intent.getFloatExtra("cardHeightRatioPortrait", 0.68f);
            cardHeightRatioLandscape = intent.getFloatExtra("cardHeightRatioLandscape", 0.5f);
            cardWidthRatioPortrait = intent.getFloatExtra("cardWidthRatioPortrait", 1.0f);
            cardWidthRatioLandscape = intent.getFloatExtra("cardWidthRatioLandscape", 0.8f);
            tabletWidthRatioPortrait = intent.getFloatExtra("tabletWidthRatioPortrait", 0.6f);
            tabletHeightRatioPortrait = intent.getFloatExtra("tabletHeightRatioPortrait", 0.8f);
            tabletWidthRatioLandscape = intent.getFloatExtra("tabletWidthRatioLandscape", 0.8f);
            tabletHeightRatioLandscape = intent.getFloatExtra("tabletHeightRatioLandscape", 0.65f);
            
            if (url == null || url.isEmpty()) {
                finish();
                return;
            }
            
            boolean isTablet = false;
            try {
                isTablet = StashWebViewUtils.isTablet(this);
            } catch (Exception e) {
                Log.e(TAG, "Error checking if tablet: " + e.getMessage(), e);
            }
            
            try {
                if (usePopup) {
                    setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR);
                } else if (!isTablet) {
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
        } catch (Exception e) {
            Log.e(TAG, "Error in onCreate: " + e.getMessage(), e);
            finish();
        }
    }
    
    private void createUI() {
        try {
            rootLayout = new FrameLayout(this);
            rootLayout.setBackgroundColor(Color.TRANSPARENT);
            
            boolean isTablet = false;
            try {
                isTablet = StashWebViewUtils.isTablet(this);
            } catch (Exception e) {
                Log.e(TAG, "Error checking if tablet in createUI: " + e.getMessage(), e);
            }
            
            // Create separate backdrop view for independent fade animation
            backdropView = new View(this);
            backdropView.setLayoutParams(new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, 
                FrameLayout.LayoutParams.MATCH_PARENT));
            try {
                if (wasLandscapeBeforePortrait && !isTablet && !usePopup) {
                    backdropView.setBackgroundColor(Color.BLACK);
                } else {
                    backdropView.setBackgroundColor(Color.parseColor(StashWebViewUtils.COLOR_BACKGROUND_DIM));
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
        bg.setColor(StashWebViewUtils.isDarkTheme(this) ? Color.parseColor(StashWebViewUtils.COLOR_DARK_BG) : Color.WHITE);
        float radius = StashWebViewUtils.dpToPx(this, (int)CORNER_RADIUS_DP);
        
        if (isTablet) {
            bg.setCornerRadius(radius);
        } else {
            bg.setCornerRadii(new float[]{radius, radius, radius, radius, 0, 0, 0, 0});
        }
        cardContainer.setBackground(bg);
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            cardContainer.setElevation(StashWebViewUtils.dpToPx(this, (int)ELEVATION_DP));
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

    private int[] calculateTabletCardSize(DisplayMetrics metrics) {
        // Use actual current screen dimensions
        int screenWidth = metrics.widthPixels;
        int screenHeight = metrics.heightPixels;
        
        // Determine orientation and use appropriate ratios
        boolean isLandscape = screenWidth > screenHeight;
        
        float widthRatio, heightRatio;
        if (isLandscape) {
            widthRatio = tabletWidthRatioLandscape;
            heightRatio = tabletHeightRatioLandscape;
        } else {
            widthRatio = tabletWidthRatioPortrait;
            heightRatio = tabletHeightRatioPortrait;
        }
        
        // Apply orientation-specific tablet ratios to actual screen dimensions
        int cardWidth = (int)(screenWidth * widthRatio);
        int cardHeight = (int)(screenHeight * heightRatio);
        
        if (cardWidth <= 0 || cardHeight <= 0) {
            return new int[]{600, 700};
        }
        
        // Enforce minimum sizes for usability
        int minWidth = 400;
        int minHeight = 500;
        if (cardWidth < minWidth) {
            cardWidth = minWidth;
        }
        if (cardHeight < minHeight) {
            cardHeight = minHeight;
        }
        
        return new int[]{cardWidth, cardHeight};
    }
    
    private void createCard() {
        DisplayMetrics metrics = getResources().getDisplayMetrics();
        boolean isTablet = StashWebViewUtils.isTablet(this);
        
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
                // Use configurable card height ratio for phones
                effectiveHeightRatio = cardHeightRatio;
                isExpanded = false;
            }
            cardHeight = (int)(metrics.heightPixels * effectiveHeightRatio);
            // Use configurable card width ratio for phones
            if (cardWidthRatio < 1.0f) {
                cardWidth = (int)(metrics.widthPixels * cardWidthRatio);
            } else {
                cardWidth = FrameLayout.LayoutParams.MATCH_PARENT;
            }
        }
        
        configureCardContainer(isTablet, cardWidth, cardHeight);
        
        addWebView();
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
        handleBg.setColor(Color.parseColor(COLOR_DRAG_HANDLE));
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
                    lastMoveTime = System.currentTimeMillis();
                    lastMoveY = event.getRawY();
                    velocity = 0;
                    return true;
                
                case MotionEvent.ACTION_MOVE:
                    float deltaY = event.getRawY() - initialY;
                    
                    // Calculate velocity
                    long currentTime = System.currentTimeMillis();
                    float timeDelta = (currentTime - lastMoveTime) / 1000f;
                    if (timeDelta > 0) {
                        velocity = (event.getRawY() - lastMoveY) / timeDelta;
                    }
                    lastMoveTime = currentTime;
                    lastMoveY = event.getRawY();
                    
                    if (Math.abs(deltaY) > StashWebViewUtils.dpToPx(StashPayCardPortraitActivity.this, 10)) {
                        isDragging = true;
                        
                        // Tablet: Only allow downward drag (dismiss only)
                        if (isTablet) {
                            if (deltaY > 0) {
                                float newTranslationY = initialTranslationY + deltaY;
                                cardContainer.setTranslationY(newTranslationY);
                                DisplayMetrics metrics = getResources().getDisplayMetrics();
                                float progress = Math.min(deltaY / metrics.heightPixels, 1.0f);
                                cardContainer.setAlpha(1.0f - (progress * 0.5f));
                            }
                        } else {
                            // Phone: Allow both directions
                            if (deltaY > 0) {
                                // Drag down
                                float newTranslationY = initialTranslationY + deltaY;
                                cardContainer.setTranslationY(newTranslationY);
                                DisplayMetrics metrics = getResources().getDisplayMetrics();
                                float progress = Math.min(deltaY / metrics.heightPixels, 1.0f);
                                cardContainer.setAlpha(1.0f - (progress * 0.5f));
                            } else if (!isExpanded && !wasLandscapeBeforePortrait) {
                                // Drag up to expand (phone only)
                                float cardHeight = cardContainer.getHeight();
                                float expandThreshold = cardHeight * CardConstants.EXPAND_DISTANCE_THRESHOLD;
                                float dragProgress = Math.min(Math.abs(deltaY) / expandThreshold, 1.0f);
                                cardContainer.setScaleX(1.0f + (dragProgress * 0.02f));
                                cardContainer.setScaleY(1.0f + (dragProgress * 0.02f));
                            }
                        }
                    }
                    return true;
                
                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_CANCEL:
                    if (isDragging) {
                        float finalDeltaY = event.getRawY() - initialY;
                        DisplayMetrics metrics = getResources().getDisplayMetrics();
                        float cardHeight = cardContainer.getHeight();
                        
                        if (isTablet) {
                            // Tablet: Dismiss only
                            if (finalDeltaY > 0) {
                                float dismissThreshold = metrics.heightPixels * CardConstants.DISMISS_DISTANCE_THRESHOLD_TABLET;
                                if (finalDeltaY > dismissThreshold || velocity > CardConstants.DISMISS_VELOCITY_THRESHOLD_TABLET) {
                                    animateTabletDismiss();
                                } else {
                                    animateSnapBack();
                                }
                            } else {
                                animateSnapBack();
                            }
                        } else {
                            // Phone: Three-state system with velocity
                            if (finalDeltaY > 0) {
                                // Drag down
                                float dismissThreshold = metrics.heightPixels * CardConstants.DISMISS_DISTANCE_THRESHOLD_PHONE;
                                float collapseThreshold = cardHeight * CardConstants.COLLAPSE_DISTANCE_THRESHOLD;
                                
                                if (isExpanded) {
                                    // From expanded: collapse or dismiss
                                    if (finalDeltaY > dismissThreshold && velocity > CardConstants.DISMISS_VELOCITY_THRESHOLD) {
                                        animateDismiss();
                                    } else if (finalDeltaY > collapseThreshold || velocity > CardConstants.COLLAPSE_VELOCITY_THRESHOLD) {
                                        animateCollapse();
                                    } else {
                                        animateSnapBack();
                                    }
                                } else {
                                    // From collapsed: dismiss
                                    if (finalDeltaY > dismissThreshold || velocity > CardConstants.DISMISS_VELOCITY_THRESHOLD) {
                                        animateDismiss();
                                    } else {
                                        animateSnapBack();
                                    }
                                }
                            } else if (finalDeltaY < 0 && !isExpanded && !wasLandscapeBeforePortrait) {
                                // Drag up: expand (phone only)
                                float expandThreshold = cardHeight * CardConstants.EXPAND_DISTANCE_THRESHOLD;
                                if (Math.abs(finalDeltaY) > expandThreshold || velocity < CardConstants.EXPAND_VELOCITY_THRESHOLD) {
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
            height = (int)(getResources().getDisplayMetrics().heightPixels * cardHeightRatio);
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
    
    private void animateCardHeight(int targetHeight, int duration) {
        FrameLayout.LayoutParams params = (FrameLayout.LayoutParams)cardContainer.getLayoutParams();
        android.animation.ValueAnimator heightAnimator = android.animation.ValueAnimator.ofInt(params.height, targetHeight);
        heightAnimator.setDuration(duration);
        heightAnimator.setInterpolator(new SpringInterpolator());
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
        widthAnimator.setInterpolator(new SpringInterpolator());
        widthAnimator.addUpdateListener(animation -> {
            params.width = (Integer)animation.getAnimatedValue();
            cardContainer.setLayoutParams(params);
        });
        widthAnimator.start();
    }

    private void animateExpand() {
        if (cardContainer == null) return;
        DisplayMetrics metrics = getResources().getDisplayMetrics();
        boolean isTablet = StashWebViewUtils.isTablet(this);
        
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
            .setInterpolator(new SpringInterpolator())
            .start();
        
        isExpanded = true;
    }
    
    private void animateCollapse() {
        if (cardContainer == null || !isExpanded) return;
        DisplayMetrics metrics = getResources().getDisplayMetrics();
        boolean isTablet = StashWebViewUtils.isTablet(this);
        
        FrameLayout.LayoutParams params = (FrameLayout.LayoutParams)cardContainer.getLayoutParams();
        
        int collapsedHeight;
        int collapsedWidth;
        
        if (isTablet) {
            int[] defaultCardSize = calculateTabletCardSize(metrics);
            collapsedWidth = (int)(defaultCardSize[0] * 0.7f);
            collapsedHeight = (int)(defaultCardSize[1] * 0.7f);
            
            animateCardWidth(collapsedWidth, 320);
        } else {
            collapsedHeight = (int)(metrics.heightPixels * cardHeightRatio);
            collapsedWidth = params.width;
        }
        
        animateCardHeight(collapsedHeight, isTablet ? 320 : 380);
        
        cardContainer.animate()
            .translationY(0)
            .alpha(1f)
            .scaleX(1f)
            .scaleY(1f)
            .setDuration(isTablet ? 320 : 380)
            .setInterpolator(new SpringInterpolator())
            .start();
        
        isExpanded = false;
    }
    
    private void animateSnapBack() {
        if (cardContainer == null) return;
        DisplayMetrics metrics = getResources().getDisplayMetrics();
        boolean isTablet = StashWebViewUtils.isTablet(this);
        
        int targetHeight;
        if (wasLandscapeBeforePortrait && !isTablet) {
            targetHeight = (int)(metrics.heightPixels * CARD_HEIGHT_EXPANDED);
            isExpanded = true;
        } else if (isExpanded) {
            targetHeight = (int)(metrics.heightPixels * CARD_HEIGHT_EXPANDED);
        } else {
            targetHeight = (int)(metrics.heightPixels * cardHeightRatio);
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
            .setInterpolator(new SpringInterpolator())
            .start();
    }

    private void addWebView() {
        if (url == null || url.isEmpty() || cardContainer == null) {
            Log.e(TAG, "Invalid parameters in addWebView");
            return;
        }
        
        try {
            webView = new WebView(this);
            try {
                StashWebViewUtils.configureWebViewSettings(webView, StashWebViewUtils.isDarkTheme(this));
            } catch (Exception e) {
                Log.e(TAG, "Error configuring WebView settings: " + e.getMessage(), e);
            }
        
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
                try {
                    super.onPageStarted(view, url, favicon);
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
                    super.onPageFinished(view, url);
                    hideLoading();
                    injectSDK(view);
                    checkProvider(url);
                    checkGooglePayRedirect(url);
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
                webView.addJavascriptInterface(new JSInterface(), "StashAndroid");
                webView.setBackgroundColor(StashWebViewUtils.isDarkTheme(this) ? Color.parseColor(StashWebViewUtils.COLOR_DARK_BG) : Color.WHITE);
                
                FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
                webView.setLayoutParams(params);
                cardContainer.addView(webView);
                String urlWithTheme;
                try {
                    urlWithTheme = StashWebViewUtils.appendThemeQueryParameter(url, StashWebViewUtils.isDarkTheme(this));
                } catch (Exception e) {
                    Log.e(TAG, "Error appending theme parameter: " + e.getMessage(), e);
                    urlWithTheme = url;
                }
                webView.loadUrl(urlWithTheme);
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
        homeButton.setTextColor(Color.parseColor(COLOR_HOME_TEXT));
        homeButton.setGravity(Gravity.CENTER);
        homeButton.setPadding(0, 0, 0, 0);
        
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(StashWebViewUtils.isDarkTheme(this) ? Color.parseColor("#2C2C2E") : Color.parseColor(COLOR_LIGHT_BG));
        bg.setCornerRadius(StashWebViewUtils.dpToPx(this, 20));
        bg.setStroke(StashWebViewUtils.dpToPx(this, 1), StashWebViewUtils.isDarkTheme(this) ? Color.parseColor(COLOR_DARK_STROKE) : Color.parseColor(COLOR_LIGHT_STROKE));
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
                String urlWithTheme = StashWebViewUtils.appendThemeQueryParameter(initialURL, StashWebViewUtils.isDarkTheme(this));
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
        String lower = url.toLowerCase();
        boolean show = lower.contains("klarna") || lower.contains("paypal") || lower.contains("stripe");
        runOnUiThread(() -> homeButton.setVisibility(show ? View.VISIBLE : View.GONE));
    }
    
    private void checkGooglePayRedirect(String url) {
        if (url == null || googlePayRedirectHandled || initialURL == null || initialURL.isEmpty()) {
            return;
        }
        
        String lower = url.toLowerCase();
        if (lower.contains("pay.google.com")) {
            googlePayRedirectHandled = true;
            openGooglePayInBrowser(initialURL);
        }
    }
    
    private void openGooglePayInBrowser(String url) {
        try {
            String urlWithParam = url;
            if (url != null && !url.isEmpty()) {
                Uri uri = Uri.parse(url);
                String existingQuery = uri.getQuery();
                if (existingQuery != null && !existingQuery.isEmpty()) {
                    urlWithParam = url + "&dpm=gpay";
                } else {
                    urlWithParam = url + "?dpm=gpay";
                }
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
        runOnUiThread(() -> {
                if (loadingIndicator != null && loadingIndicator.getParent() != null) {
                    ((ViewGroup)loadingIndicator.getParent()).removeView(loadingIndicator);
                }
                
                if (cardContainer != null) {
                loadingIndicator = StashWebViewUtils.createAndShowLoading(getApplicationContext(), cardContainer);
                        if (loadingIndicator != null) {
                            loadingIndicator.setVisibility(View.VISIBLE);
                            loadingIndicator.requestLayout();
                        }
            }
        });
    }
    
    private void hideLoading() {
        runOnUiThread(() -> {
            StashWebViewUtils.hideLoading(loadingIndicator);
                        loadingIndicator = null;
        });
    }
    
    private void animateSlideUp() {
        DisplayMetrics metrics = getResources().getDisplayMetrics();
        cardContainer.setTranslationY(metrics.heightPixels);
        
        cardContainer.post(() -> {
            cardContainer.animate()
                .translationY(0)
                .setDuration(300)
                .setInterpolator(new android.view.animation.AccelerateDecelerateInterpolator())
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
            
            boolean isTablet = StashWebViewUtils.isTablet(this);
            
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
                // Seamless animation for tablet rotation
                animateTabletRotation();
            } else {
                if (wasLandscapeBeforePortrait) {
                    if (!isExpanded) {
                        animateExpand();
                    } else {
                        DisplayMetrics metrics = getResources().getDisplayMetrics();
                        FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
                        int expandedHeight = (int)(metrics.heightPixels * CARD_HEIGHT_EXPANDED);
                        params.height = expandedHeight;
                        cardContainer.setLayoutParams(params);
                    }
                }
            }
        }
    }
    
    private void animateTabletRotation() {
        DisplayMetrics metrics = getResources().getDisplayMetrics();
        int[] newSize = calculateTabletCardSize(metrics);
        int newWidth = newSize[0];
        int newHeight = newSize[1];
        
        FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
        int currentWidth = params.width;
        int currentHeight = params.height;
        
        // Animate width
        if (currentWidth != newWidth) {
            ValueAnimator widthAnim = ValueAnimator.ofInt(currentWidth, newWidth);
            widthAnim.setDuration(400);
            widthAnim.setInterpolator(new SpringInterpolator());
            widthAnim.addUpdateListener(animation -> {
                if (cardContainer != null) {
                    FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
                    p.width = (int) animation.getAnimatedValue();
                    cardContainer.setLayoutParams(p);
                }
            });
            widthAnim.start();
        }
        
        // Animate height
        if (currentHeight != newHeight) {
            ValueAnimator heightAnim = ValueAnimator.ofInt(currentHeight, newHeight);
            heightAnim.setDuration(400);
            heightAnim.setInterpolator(new SpringInterpolator());
            heightAnim.addUpdateListener(animation -> {
                if (cardContainer != null) {
                    FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) cardContainer.getLayoutParams();
                    p.height = (int) animation.getAnimatedValue();
                    cardContainer.setLayoutParams(p);
                }
            });
            heightAnim.start();
        }
    }
}
