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
import android.net.Uri;

/**
 * Activity that displays the Stash Pay checkout as a card or popup overlay.
 */
public class StashPayCardPortraitActivity extends Activity {
    private static final String TAG = "StashPayCard";

    private FrameLayout rootLayout;
    private View backdropView;
    private FrameLayout cardContainer;
    private WebView webView;
    private View loadingView;
    private Button homeButton;
    
    private String url;
    private String initialURL;
    private boolean usePopup;
    private boolean useModal;
    private boolean isExpanded;
    private boolean wasLandscapeBeforePortrait;
    private boolean isDismissing;
    private boolean callbackSent;
    private boolean googlePayRedirectHandled;
    private boolean isPurchaseProcessing;
    private boolean modalInitialLoadComplete;
    private boolean initialPageLoadComplete;
    private boolean networkErrorHandled;
    private boolean mainFrameErrorReceived;
    private android.os.Handler networkTimeoutHandler;
    private Runnable networkTimeoutRunnable;
    private static final long NETWORK_TIMEOUT_MS = 5000;
    
    // Phone card: only height is configurable (card is always portrait, full width)
    private float cardHeightRatioPortrait = CardConstants.DEFAULT_CARD_HEIGHT_RATIO;
    
    // Modal configuration
    private boolean modalShowDragBar = true;
    private boolean modalAllowDismiss = true;
    private float modalPhoneWidthRatioPortrait = CardConstants.DEFAULT_MODAL_PHONE_WIDTH_RATIO_PORTRAIT;
    private float modalPhoneHeightRatioPortrait = CardConstants.DEFAULT_MODAL_PHONE_HEIGHT_RATIO_PORTRAIT;
    private float modalPhoneWidthRatioLandscape = CardConstants.DEFAULT_MODAL_PHONE_WIDTH_RATIO_LANDSCAPE;
    private float modalPhoneHeightRatioLandscape = CardConstants.DEFAULT_MODAL_PHONE_HEIGHT_RATIO_LANDSCAPE;
    private float modalTabletWidthRatioPortrait = CardConstants.DEFAULT_MODAL_TABLET_WIDTH_RATIO_PORTRAIT;
    private float modalTabletHeightRatioPortrait = CardConstants.DEFAULT_MODAL_TABLET_HEIGHT_RATIO_PORTRAIT;
    private float modalTabletWidthRatioLandscape = CardConstants.DEFAULT_MODAL_TABLET_WIDTH_RATIO_LANDSCAPE;
    private float modalTabletHeightRatioLandscape = CardConstants.DEFAULT_MODAL_TABLET_HEIGHT_RATIO_LANDSCAPE;
    
    // Orientation-specific tablet card configuration
    private float tabletWidthRatioPortrait = CardConstants.DEFAULT_TABLET_WIDTH_RATIO_PORTRAIT;
    private float tabletHeightRatioPortrait = CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_PORTRAIT;
    private float tabletWidthRatioLandscape = CardConstants.DEFAULT_TABLET_WIDTH_RATIO_LANDSCAPE;
    private float tabletHeightRatioLandscape = CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_LANDSCAPE;

    /** Cached at activity start to avoid repeated theme/device lookups. */
    private boolean cachedIsDarkTheme;
    private boolean cachedIsTablet;

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
            wasLandscapeBeforePortrait = intent.getBooleanExtra(CardConstants.INTENT_EXTRA_WAS_LANDSCAPE, false);
            
            cardHeightRatioPortrait = intent.getFloatExtra(CardConstants.INTENT_EXTRA_CARD_HEIGHT_RATIO_PORTRAIT, CardConstants.DEFAULT_CARD_HEIGHT_RATIO);
            tabletWidthRatioPortrait = intent.getFloatExtra(CardConstants.INTENT_EXTRA_TABLET_WIDTH_RATIO_PORTRAIT, CardConstants.DEFAULT_TABLET_WIDTH_RATIO_PORTRAIT);
            tabletHeightRatioPortrait = intent.getFloatExtra(CardConstants.INTENT_EXTRA_TABLET_HEIGHT_RATIO_PORTRAIT, CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_PORTRAIT);
            tabletWidthRatioLandscape = intent.getFloatExtra(CardConstants.INTENT_EXTRA_TABLET_WIDTH_RATIO_LANDSCAPE, CardConstants.DEFAULT_TABLET_WIDTH_RATIO_LANDSCAPE);
            tabletHeightRatioLandscape = intent.getFloatExtra(CardConstants.INTENT_EXTRA_TABLET_HEIGHT_RATIO_LANDSCAPE, CardConstants.DEFAULT_TABLET_HEIGHT_RATIO_LANDSCAPE);
            
            // Read modal configuration
            if (useModal) {
                modalShowDragBar = intent.getBooleanExtra(CardConstants.INTENT_EXTRA_MODAL_SHOW_DRAG_BAR, true);
                modalAllowDismiss = intent.getBooleanExtra(CardConstants.INTENT_EXTRA_MODAL_ALLOW_DISMISS, true);
                modalPhoneWidthRatioPortrait = intent.getFloatExtra(CardConstants.INTENT_EXTRA_MODAL_PHONE_WIDTH_RATIO_PORTRAIT, CardConstants.DEFAULT_MODAL_PHONE_WIDTH_RATIO_PORTRAIT);
                modalPhoneHeightRatioPortrait = intent.getFloatExtra(CardConstants.INTENT_EXTRA_MODAL_PHONE_HEIGHT_RATIO_PORTRAIT, CardConstants.DEFAULT_MODAL_PHONE_HEIGHT_RATIO_PORTRAIT);
                modalPhoneWidthRatioLandscape = intent.getFloatExtra(CardConstants.INTENT_EXTRA_MODAL_PHONE_WIDTH_RATIO_LANDSCAPE, CardConstants.DEFAULT_MODAL_PHONE_WIDTH_RATIO_LANDSCAPE);
                modalPhoneHeightRatioLandscape = intent.getFloatExtra(CardConstants.INTENT_EXTRA_MODAL_PHONE_HEIGHT_RATIO_LANDSCAPE, CardConstants.DEFAULT_MODAL_PHONE_HEIGHT_RATIO_LANDSCAPE);
                modalTabletWidthRatioPortrait = intent.getFloatExtra(CardConstants.INTENT_EXTRA_MODAL_TABLET_WIDTH_RATIO_PORTRAIT, CardConstants.DEFAULT_MODAL_TABLET_WIDTH_RATIO_PORTRAIT);
                modalTabletHeightRatioPortrait = intent.getFloatExtra(CardConstants.INTENT_EXTRA_MODAL_TABLET_HEIGHT_RATIO_PORTRAIT, CardConstants.DEFAULT_MODAL_TABLET_HEIGHT_RATIO_PORTRAIT);
                modalTabletWidthRatioLandscape = intent.getFloatExtra(CardConstants.INTENT_EXTRA_MODAL_TABLET_WIDTH_RATIO_LANDSCAPE, CardConstants.DEFAULT_MODAL_TABLET_WIDTH_RATIO_LANDSCAPE);
                modalTabletHeightRatioLandscape = intent.getFloatExtra(CardConstants.INTENT_EXTRA_MODAL_TABLET_HEIGHT_RATIO_LANDSCAPE, CardConstants.DEFAULT_MODAL_TABLET_HEIGHT_RATIO_LANDSCAPE);
            }
            
            if (url == null || url.isEmpty()) {
                finish();
                return;
            }
            
            cachedIsDarkTheme = StashWebViewUtils.isDarkTheme(this);
            try {
                cachedIsTablet = StashWebViewUtils.isTablet(this);
            } catch (Exception e) {
                Log.e(TAG, "Error checking if tablet: " + e.getMessage(), e);
            }
            
            try {
                if (usePopup || useModal) {
                    // Modal and popup allow all orientations
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
        } catch (Exception e) {
            Log.e(TAG, "Error in onCreate: " + e.getMessage(), e);
            finish();
        }
    }
    
    private void createUI() {
        try {
            rootLayout = new FrameLayout(this);
            rootLayout.setBackgroundColor(Color.TRANSPARENT);
            
            // Create separate backdrop view for independent fade animation
            backdropView = new View(this);
            backdropView.setLayoutParams(new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, 
                FrameLayout.LayoutParams.MATCH_PARENT));
            try {
                if (wasLandscapeBeforePortrait && !cachedIsTablet && !usePopup) {
                    backdropView.setBackgroundColor(Color.BLACK);
                } else {
                    backdropView.setBackgroundColor(Color.parseColor(StashWebViewUtils.COLOR_BACKGROUND_DIM));
                }
            } catch (Exception e) {
                Log.e(TAG, "Error setting background color: " + e.getMessage(), e);
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
                Log.e(TAG, "Error creating UI: " + e.getMessage(), e);
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
        bg.setColor(cachedIsDarkTheme ? Color.parseColor(StashWebViewUtils.COLOR_DARK_BG) : Color.WHITE);
        float radius = StashWebViewUtils.dpToPx(this, (int)CardConstants.CORNER_RADIUS_DP);
        
        if (isTablet) {
            bg.setCornerRadius(radius);
        } else {
            bg.setCornerRadii(new float[]{radius, radius, radius, radius, 0, 0, 0, 0});
        }
        cardContainer.setBackground(bg);
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            cardContainer.setElevation(StashWebViewUtils.dpToPx(this, (int)CardConstants.ELEVATION_DP));
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
            return new int[]{CardConstants.FALLBACK_TABLET_CARD_WIDTH, CardConstants.FALLBACK_TABLET_CARD_HEIGHT};
        }
        
        // Enforce minimum sizes for usability
        int minWidth = (int) CardConstants.MIN_TABLET_CARD_WIDTH_DP;
        int minHeight = (int) CardConstants.MIN_TABLET_CARD_HEIGHT_DP;
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
                effectiveHeightRatio = CardConstants.EXPANDED_CARD_HEIGHT_RATIO;
                isExpanded = true;
            } else {
                effectiveHeightRatio = cardHeightRatioPortrait;
                isExpanded = false;
            }
            cardHeight = (int)(metrics.heightPixels * effectiveHeightRatio);
            // Phone card is always full width
            cardWidth = FrameLayout.LayoutParams.MATCH_PARENT;
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
    
    private void createModal() {
        DisplayMetrics metrics = getResources().getDisplayMetrics();
        int[] cardSize = calculateModalCardSize(metrics);
        int cardWidth = cardSize[0];
        int cardHeight = cardSize[1];
        
        // Modal is always centered (like tablet mode)
        configureCardContainer(true, cardWidth, cardHeight);
        
        addWebView();
        if (modalShowDragBar) {
            // Modal uses visual-only drag handle (no gestures)
            addVisualOnlyDragHandle();
        }
        addHomeButton();
        rootLayout.addView(cardContainer);
        
        // Modal waits for page load before showing - start completely hidden (including backdrop)
        modalInitialLoadComplete = false;
        cardContainer.setAlpha(0f);
        cardContainer.setScaleX(0.9f);
        cardContainer.setScaleY(0.9f);
        if (backdropView != null) {
            backdropView.setAlpha(0f);
        }
        
        // Modal is always considered expanded
        isExpanded = true;
    }
    
    /**
     * Adds a visual-only drag handle for modal presentation.
     * Unlike addDragHandle(), this version has no touch handling - purely decorative.
     */
    private void addVisualOnlyDragHandle() {
        LinearLayout dragArea = new LinearLayout(this);
        dragArea.setOrientation(LinearLayout.VERTICAL);
        dragArea.setGravity(Gravity.CENTER_HORIZONTAL);
        dragArea.setPadding(StashWebViewUtils.dpToPx(this, 20), StashWebViewUtils.dpToPx(this, 16), StashWebViewUtils.dpToPx(this, 20), StashWebViewUtils.dpToPx(this, 16));
        
        View handle = new View(this);
        GradientDrawable handleBg = new GradientDrawable();
        handleBg.setColor(Color.parseColor(CardConstants.COLOR_DRAG_HANDLE));
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
        
        // No touch handling - purely visual
        cardContainer.addView(dragArea);
    }
    
    private int[] calculateModalCardSize(DisplayMetrics metrics) {
        int screenWidth = metrics.widthPixels;
        int screenHeight = metrics.heightPixels;
        boolean isLandscape = screenWidth > screenHeight;
        boolean isTablet = cachedIsTablet;
        
        float widthRatio, heightRatio;
        if (isTablet) {
            if (isLandscape) {
                widthRatio = modalTabletWidthRatioLandscape;
                heightRatio = modalTabletHeightRatioLandscape;
            } else {
                widthRatio = modalTabletWidthRatioPortrait;
                heightRatio = modalTabletHeightRatioPortrait;
            }
        } else {
            if (isLandscape) {
                widthRatio = modalPhoneWidthRatioLandscape;
                heightRatio = modalPhoneHeightRatioLandscape;
            } else {
                widthRatio = modalPhoneWidthRatioPortrait;
                heightRatio = modalPhoneHeightRatioPortrait;
            }
        }
        
        int cardWidth = (int)(screenWidth * widthRatio);
        int cardHeight = (int)(screenHeight * heightRatio);
        
        // Apply minimum sizes
        int minWidth = isTablet ? (int) CardConstants.MIN_TABLET_CARD_WIDTH_DP : (int) CardConstants.MIN_PHONE_CARD_WIDTH_DP;
        int minHeight = isTablet ? (int) CardConstants.MIN_TABLET_CARD_HEIGHT_DP : (int) CardConstants.MIN_PHONE_CARD_WIDTH_DP;
        
        if (cardWidth < minWidth) cardWidth = minWidth;
        if (cardHeight < minHeight) cardHeight = minHeight;
        
        return new int[]{cardWidth, cardHeight};
    }
    
    private void addDragHandle() {
        LinearLayout dragArea = new LinearLayout(this);
        dragArea.setOrientation(LinearLayout.VERTICAL);
        dragArea.setGravity(Gravity.CENTER_HORIZONTAL);
        dragArea.setPadding(StashWebViewUtils.dpToPx(this, 20), StashWebViewUtils.dpToPx(this, 16), StashWebViewUtils.dpToPx(this, 20), StashWebViewUtils.dpToPx(this, 16));
        
        View handle = new View(this);
        GradientDrawable handleBg = new GradientDrawable();
        handleBg.setColor(Color.parseColor(CardConstants.COLOR_DRAG_HANDLE));
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
        /** Cached for the current touch sequence to avoid repeated getDisplayMetrics() calls. */
        private DisplayMetrics displayMetrics;
        
        /** Applies drag-down feedback: translation and alpha fade. Shared by tablet and phone. */
        private void applyDragDownFeedback(float deltaY) {
            if (displayMetrics == null) return;
            float newTranslationY = initialTranslationY + deltaY;
            cardContainer.setTranslationY(newTranslationY);
            float progress = Math.min(deltaY / displayMetrics.heightPixels, 1.0f);
            cardContainer.setAlpha(1.0f - (progress * CardConstants.ALPHA_FADE_MULTIPLIER));
        }
        
        @Override
        public boolean onTouch(View v, MotionEvent event) {
            if (cardContainer == null) return false;
            
            if (isPurchaseProcessing) {
                return false;
            }
            
            // Modal mode never supports drag gestures (only visual drag bar)
            if (useModal) {
                return false;
            }
            
            boolean isTablet = cachedIsTablet;
            
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
                        // Tablet or Modal: only treat as drag when moving downward (dismiss gesture)
                        isDragging = (isTablet || useModal) ? (deltaY > 0) : true;
                        
                        if (deltaY > 0) {
                            // Drag down: same feedback for tablet, modal, and phone
                            applyDragDownFeedback(deltaY);
                        } else if (!isTablet && !useModal && !isExpanded && !wasLandscapeBeforePortrait) {
                            // Phone only (not modal): drag up to expand
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
                        DisplayMetrics metrics = displayMetrics != null ? displayMetrics : getResources().getDisplayMetrics();
                        float cardHeight = cardContainer.getHeight();
                        
                        if (isTablet || useModal) {
                            // Tablet or Modal: Dismiss only (no expand/collapse)
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
            height = (int)(getResources().getDisplayMetrics().heightPixels * cardHeightRatioPortrait);
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
        if (cardContainer == null) return;
        if (isPurchaseProcessing) return;
        
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

    private void animateExpand() {
        if (cardContainer == null) return;
        
        // Tablets use fixed sizing - ignore expand/collapse
        boolean isTablet = cachedIsTablet;
        if (isTablet) return;
        
        DisplayMetrics metrics = getResources().getDisplayMetrics();
        
        FrameLayout.LayoutParams params = (FrameLayout.LayoutParams)cardContainer.getLayoutParams();
        
        int expandedHeight = (int)(metrics.heightPixels * CardConstants.EXPANDED_CARD_HEIGHT_RATIO);
        int expandedWidth = params.width;
        
        animateCardHeight(expandedHeight, 450);
        
        cardContainer.animate()
            .translationY(0)
            .alpha(1f)
            .scaleX(1f)
            .scaleY(1f)
            .setDuration(CardConstants.ANIMATION_DURATION_SNAP_BACK)
            .setInterpolator(new SpringInterpolator())
            .start();
        
        isExpanded = true;
    }
    
    private void animateCollapse() {
        if (cardContainer == null || !isExpanded) return;
        
        // Tablets use fixed sizing - ignore expand/collapse
        boolean isTablet = cachedIsTablet;
        if (isTablet) return;
        
        DisplayMetrics metrics = getResources().getDisplayMetrics();
        
        int collapsedHeight = (int)(metrics.heightPixels * cardHeightRatioPortrait);
        
        animateCardHeight(collapsedHeight, CardConstants.ANIMATION_DURATION_COLLAPSE);
        
        cardContainer.animate()
            .translationY(0)
            .alpha(1f)
            .scaleX(1f)
            .scaleY(1f)
            .setDuration(CardConstants.ANIMATION_DURATION_COLLAPSE)
            .setInterpolator(new SpringInterpolator())
            .start();
        
        isExpanded = false;
    }
    
    private void animateSnapBack() {
        if (cardContainer == null) return;
        DisplayMetrics metrics = getResources().getDisplayMetrics();
        boolean isTablet = cachedIsTablet;
        
        FrameLayout.LayoutParams params = (FrameLayout.LayoutParams)cardContainer.getLayoutParams();
        int targetHeight;
        if (isTablet) {
            // Tablet: single fixed size - keep current height, only reset translation/alpha/scale
            targetHeight = params.height;
        } else if (wasLandscapeBeforePortrait) {
            targetHeight = (int)(metrics.heightPixels * CardConstants.EXPANDED_CARD_HEIGHT_RATIO);
            isExpanded = true;
        } else if (isExpanded) {
            targetHeight = (int)(metrics.heightPixels * CardConstants.EXPANDED_CARD_HEIGHT_RATIO);
        } else {
            targetHeight = (int)(metrics.heightPixels * cardHeightRatioPortrait);
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

    private void addWebView() {
        if (url == null || url.isEmpty() || cardContainer == null) {
            Log.e(TAG, "Invalid parameters in addWebView");
            return;
        }
        
        try {
            webView = new WebView(this);
            try {
                StashWebViewUtils.configureWebViewSettings(webView, cachedIsDarkTheme);
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
                    
                    // Don't mark as complete if network error already handled or main frame error received
                    if (networkErrorHandled || mainFrameErrorReceived) {
                        return;
                    }
                    
                    // Mark initial load as complete and cancel timeout
                    if (!initialPageLoadComplete) {
                        initialPageLoadComplete = true;
                        cancelNetworkTimeout();
                    }
                    
                    hideLoading();
                    injectSDK(view);
                    checkProvider(url);
                    checkGooglePayRedirect(url);
                    
                    // Modal: show card and backdrop after initial page load
                    if (useModal && !modalInitialLoadComplete) {
                        modalInitialLoadComplete = true;
                        // Fade in backdrop
                        if (backdropView != null) {
                            backdropView.animate()
                                .alpha(1f)
                                .setDuration(200)
                                .setInterpolator(new android.view.animation.AccelerateDecelerateInterpolator())
                                .start();
                        }
                        animateFadeIn();
                    }
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
                    
                    // Check if this is the main frame and initial load hasn't completed
                    if (request != null && request.isForMainFrame() && !initialPageLoadComplete) {
                        Log.e(TAG, "Network error on main frame during initial load");
                        mainFrameErrorReceived = true;
                        handleNetworkError();
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error in onReceivedError: " + e.getMessage(), e);
                }
            }
            
            @Override
            public void onReceivedHttpError(WebView view, android.webkit.WebResourceRequest request,
                                           android.webkit.WebResourceResponse errorResponse) {
                try {
                    super.onReceivedHttpError(view, request, errorResponse);
                    
                    // Check if this is the main frame and initial load hasn't completed
                    if (request != null && request.isForMainFrame() && !initialPageLoadComplete) {
                        int statusCode = errorResponse != null ? errorResponse.getStatusCode() : 0;
                        Log.e(TAG, "HTTP error on main frame during initial load: " + statusCode);
                        mainFrameErrorReceived = true;
                        handleNetworkError();
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error in onReceivedHttpError: " + e.getMessage(), e);
                }
            }
        });
        
            try {
                webView.setWebChromeClient(new WebChromeClient());
                webView.addJavascriptInterface(new JSInterface(), StashWebViewUtils.JS_INTERFACE_NAME);
                webView.setBackgroundColor(cachedIsDarkTheme ? Color.parseColor(StashWebViewUtils.COLOR_DARK_BG) : Color.WHITE);
                
                FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
                webView.setLayoutParams(params);
                cardContainer.addView(webView);
                String urlWithTheme;
                try {
                    urlWithTheme = StashWebViewUtils.appendThemeQueryParameter(url, cachedIsDarkTheme);
                } catch (Exception e) {
                    Log.e(TAG, "Error appending theme parameter: " + e.getMessage(), e);
                    urlWithTheme = url;
                }
                webView.loadUrl(urlWithTheme);
                
                // Start network timeout timer
                startNetworkTimeout();
            } catch (Exception e) {
                Log.e(TAG, "Error setting up WebView: " + e.getMessage(), e);
                finish();
            }
        } catch (Exception e) {
            Log.e(TAG, "Error creating WebView: " + e.getMessage(), e);
            finish();
        }
    }
    
    private void startNetworkTimeout() {
        networkTimeoutHandler = new android.os.Handler(android.os.Looper.getMainLooper());
        networkTimeoutRunnable = () -> {
            if (!initialPageLoadComplete && !networkErrorHandled && !isDismissing) {
                Log.e(TAG, "Network timeout: page did not load within " + NETWORK_TIMEOUT_MS + "ms");
                handleNetworkError();
            }
        };
        networkTimeoutHandler.postDelayed(networkTimeoutRunnable, NETWORK_TIMEOUT_MS);
    }
    
    private void cancelNetworkTimeout() {
        if (networkTimeoutHandler != null && networkTimeoutRunnable != null) {
            networkTimeoutHandler.removeCallbacks(networkTimeoutRunnable);
        }
    }
    
    private void handleNetworkError() {
        if (networkErrorHandled || isDismissing) return;
        networkErrorHandled = true;
        
        cancelNetworkTimeout();
        
        // Call the network error callback
        StashPayCard.StashPayListener listener = StashPayCard.getInstance().getListener();
        if (listener != null) {
            listener.onNetworkError();
        }
        
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
        bg.setColor(cachedIsDarkTheme ? Color.parseColor(CardConstants.COLOR_HOME_BUTTON_DARK_BG) : Color.parseColor(CardConstants.COLOR_LIGHT_BG));
        bg.setCornerRadius(StashWebViewUtils.dpToPx(this, 20));
        bg.setStroke(StashWebViewUtils.dpToPx(this, 1), cachedIsDarkTheme ? Color.parseColor(CardConstants.COLOR_DARK_STROKE) : Color.parseColor(CardConstants.COLOR_LIGHT_STROKE));
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
        String lower = url.toLowerCase();
        boolean show = lower.contains("klarna") || lower.contains("paypal") || lower.contains("stripe");
        runOnUiThread(() -> homeButton.setVisibility(show ? View.VISIBLE : View.GONE));
    }
    
    private void checkGooglePayRedirect(String url) {
        if (url == null || googlePayRedirectHandled || initialURL == null || initialURL.isEmpty()) {
            return;
        }
        
        String lower = url.toLowerCase();
        if (lower.contains(CardConstants.GOOGLE_PAY_DOMAIN)) {
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
                    urlWithParam = url + CardConstants.GOOGLE_PAY_PARAM_PREFIX_AMP;
                } else {
                    urlWithParam = url + CardConstants.GOOGLE_PAY_PARAM_PREFIX_QUERY;
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
            if (StashWebViewUtils.isChromeCustomTabsAvailable(activity)) {
                Log.d(TAG, "Opening Google Pay URL with Chrome Custom Tabs");
                StashWebViewUtils.openWithChromeCustomTabs(activity, url);
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
            if (loadingView != null && loadingView.getParent() != null) {
                ((ViewGroup)loadingView.getParent()).removeView(loadingView);
            }
            
            if (cardContainer != null) {
                loadingView = StashWebViewUtils.createAndShowLoadingView(getApplicationContext(), cardContainer);
                if (loadingView != null) {
                    loadingView.setVisibility(View.VISIBLE);
                }
            }
        });
    }
    
    private void hideLoading() {
        runOnUiThread(() -> {
            if (loadingView != null) {
                loadingView.animate()
                    .alpha(0.0f)
                    .setDuration(200)
                    .withEndAction(() -> {
                        if (loadingView != null && loadingView.getParent() != null) {
                            ((ViewGroup)loadingView.getParent()).removeView(loadingView);
                        }
                        loadingView = null;
                    })
                    .start();
            }
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
                        .setDuration(CardConstants.ANIMATION_DURATION_ENTRY)
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
                            case CardConstants.MESSAGE_TYPE_SUCCESS:
                                listener.onPaymentSuccess();
                                break;
                            case CardConstants.MESSAGE_TYPE_FAILURE:
                                listener.onPaymentFailure();
                                break;
                            case CardConstants.MESSAGE_TYPE_OPTIN:
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
                notifyListenerAndDismiss(CardConstants.MESSAGE_TYPE_SUCCESS, "", true);
            } catch (Exception e) {
                Log.e(TAG, "Error in onPaymentSuccess: " + e.getMessage(), e);
            }
        }
        
        @JavascriptInterface
        public void onPaymentFailure() {
            try {
                notifyListenerAndDismiss(CardConstants.MESSAGE_TYPE_FAILURE, "", true);
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
                notifyListenerAndDismiss(CardConstants.MESSAGE_TYPE_OPTIN, optinType != null ? optinType : "", false);
            } catch (Exception e) {
                Log.e(TAG, "Error in setPaymentChannel: " + e.getMessage(), e);
            }
        }
        
        @JavascriptInterface
        public void expand() {
            // Modal does not support expand/collapse
            if (useModal) return;
            
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
            // Modal does not support expand/collapse
            if (useModal) return;
            
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
    @SuppressWarnings("deprecation") // minSdk 21; use OnBackPressedDispatcher when targeting API 33+ with ComponentActivity
    public void onBackPressed() {
        if (isPurchaseProcessing) {
            return;
        }
        dismissWithAnimation();
    }
    
    @Override
    public void onConfigurationChanged(Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        
        if (useModal && cardContainer != null && rootLayout != null) {
            // Modal mode: always animate resize on rotation
            animateModalRotation();
        } else if (!usePopup && cardContainer != null && rootLayout != null) {
            boolean isTablet = cachedIsTablet;
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
                        int expandedHeight = (int)(metrics.heightPixels * CardConstants.EXPANDED_CARD_HEIGHT_RATIO);
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
            widthAnim.setDuration(CardConstants.ANIMATION_DURATION_DEFAULT);
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
            heightAnim.setDuration(CardConstants.ANIMATION_DURATION_DEFAULT);
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
    
    private void animateModalRotation() {
        DisplayMetrics metrics = getResources().getDisplayMetrics();
        int[] newSize = calculateModalCardSize(metrics);
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
                    p.width = (int) animation.getAnimatedValue();
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
                    p.height = (int) animation.getAnimatedValue();
                    cardContainer.setLayoutParams(p);
                }
            });
            heightAnim.start();
        }
    }
}
