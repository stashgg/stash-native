package com.stash.popup;

/**
 * Shared constants for card presentation, animations, and gestures.
 * Aligned with iOS for consistent cross-platform behavior.
 */
public final class CardConstants {
    private CardConstants() {} // Prevent instantiation
    
    // ============================================================================
    // Animation Durations (milliseconds)
    // ============================================================================
    
    /** Default animation duration */
    public static final int ANIMATION_DURATION_DEFAULT = 400;
    
    /** Fast animation duration */
    public static final int ANIMATION_DURATION_FAST = 250;
    
    /** Entry animation duration */
    public static final int ANIMATION_DURATION_ENTRY = 300;
    
    /** Popup fade animation duration */
    public static final int ANIMATION_DURATION_POPUP = 200;
    
    /** Card expand animation duration */
    public static final int ANIMATION_DURATION_EXPAND = 400;
    
    /** Card collapse animation duration */
    public static final int ANIMATION_DURATION_COLLAPSE = 380;
    
    /** Card dismiss animation duration */
    public static final int ANIMATION_DURATION_DISMISS = 250;
    
    /** Snap back animation duration */
    public static final int ANIMATION_DURATION_SNAP_BACK = 450;
    
    // ============================================================================
    // Spring Animation Parameters (aligned with iOS)
    // ============================================================================
    
    /** Default spring damping (0.0 - 1.0) */
    public static final float SPRING_DAMPING_DEFAULT = 0.85f;
    
    /** Tight spring damping for snappy animations */
    public static final float SPRING_DAMPING_TIGHT = 0.9f;
    
    /** Spring stiffness for Android SpringInterpolator */
    public static final float SPRING_STIFFNESS = 400f;
    
    /** Spring mass */
    public static final float SPRING_MASS = 1.0f;
    
    // ============================================================================
    // Gesture Thresholds (Velocity-based, aligned across platforms)
    // ============================================================================
    
    /** Upward velocity threshold to expand (pixels/second) */
    public static final float EXPAND_VELOCITY_THRESHOLD = -300f;
    
    /** Downward velocity threshold to collapse when expanded (pixels/second) */
    public static final float COLLAPSE_VELOCITY_THRESHOLD = 300f;
    
    /** Downward velocity threshold to dismiss when collapsed (pixels/second) */
    public static final float DISMISS_VELOCITY_THRESHOLD = 500f;
    
    /** iPad/Tablet dismiss velocity threshold */
    public static final float DISMISS_VELOCITY_THRESHOLD_TABLET = 1040f;
    
    // ============================================================================
    // Distance Thresholds (relative to card height)
    // ============================================================================
    
    /** Drag distance to trigger expand (15% of height) */
    public static final float EXPAND_DISTANCE_THRESHOLD = 0.15f;
    
    /** Drag distance to trigger collapse (25% of height) */
    public static final float COLLAPSE_DISTANCE_THRESHOLD = 0.25f;
    
    /** Drag distance to trigger dismiss on phone (25% of screen height - Android native feel) */
    public static final float DISMISS_DISTANCE_THRESHOLD_PHONE = 0.25f;
    
    /** Drag distance to trigger dismiss on tablet (15% of screen height) */
    public static final float DISMISS_DISTANCE_THRESHOLD_TABLET = 0.15f;
    
    // ============================================================================
    // Visual Constants
    // ============================================================================
    
    /** Default corner radius in dp */
    public static final float CORNER_RADIUS_DP = 12f;
    
    /** Expanded corner radius in dp */
    public static final float CORNER_RADIUS_EXPANDED_DP = 16f;
    
    /** Card elevation in dp */
    public static final float ELEVATION_DP = 24f;
    
    /** Drag handle width in dp */
    public static final float DRAG_HANDLE_WIDTH_DP = 36f;
    
    /** Drag handle height in dp */
    public static final float DRAG_HANDLE_HEIGHT_DP = 5f;
    
    /** Drag tray total height in dp */
    public static final float DRAG_TRAY_HEIGHT_DP = 44f;
    
    /** Minimum touch target size in dp */
    public static final float TOUCH_TARGET_MIN_DP = 120f;
    
    // ============================================================================
    // Overlay Opacity
    // ============================================================================
    
    /** Phone overlay opacity (0-255) */
    public static final int OVERLAY_OPACITY_PHONE = 90; // ~35%
    
    /** Tablet overlay opacity (0-255) */
    public static final int OVERLAY_OPACITY_TABLET = 64; // ~25%
    
    // ============================================================================
    // Default Size Ratios
    // ============================================================================
    
    /** Default phone card height ratio */
    public static final float DEFAULT_CARD_HEIGHT_RATIO = 0.68f;
    
    /** Default phone card width ratio */
    public static final float DEFAULT_CARD_WIDTH_RATIO = 1.0f;
    
    /** Expanded phone card height ratio */
    public static final float EXPANDED_CARD_HEIGHT_RATIO = 0.95f;
    
    /** Default tablet width ratio */
    public static final float DEFAULT_TABLET_WIDTH_RATIO = 0.8f;
    
    /** Default tablet height ratio */
    public static final float DEFAULT_TABLET_HEIGHT_RATIO = 0.75f;
    
    /** Minimum tablet card width in dp */
    public static final float MIN_TABLET_CARD_WIDTH_DP = 400f;
    
    /** Minimum tablet card height in dp */
    public static final float MIN_TABLET_CARD_HEIGHT_DP = 500f;
    
    /** Default tablet height ratio for portrait */
    public static final float DEFAULT_TABLET_HEIGHT_RATIO_PORTRAIT = 0.5f;
    
    /** Default tablet width ratio for portrait */
    public static final float DEFAULT_TABLET_WIDTH_RATIO_PORTRAIT = 0.4f;
    
    /** Default tablet height ratio for landscape */
    public static final float DEFAULT_TABLET_HEIGHT_RATIO_LANDSCAPE = 0.6f;
    
    /** Default tablet width ratio for landscape */
    public static final float DEFAULT_TABLET_WIDTH_RATIO_LANDSCAPE = 0.3f;
    
    // ============================================================================
    // Popup Size Multipliers
    // ============================================================================
    
    /** Default popup portrait width multiplier */
    public static final float POPUP_PORTRAIT_WIDTH_MULTIPLIER = 1.0285f;
    
    /** Default popup portrait height multiplier */
    public static final float POPUP_PORTRAIT_HEIGHT_MULTIPLIER = 1.485f;
    
    /** Default popup landscape width multiplier */
    public static final float POPUP_LANDSCAPE_WIDTH_MULTIPLIER = 1.2275445f;
    
    /** Default popup landscape height multiplier */
    public static final float POPUP_LANDSCAPE_HEIGHT_MULTIPLIER = 1.1385f;
    
    /** Popup size ratio for phone */
    public static final float POPUP_SIZE_RATIO_PHONE = 0.75f;
    
    /** Popup size ratio for tablet */
    public static final float POPUP_SIZE_RATIO_TABLET = 0.5f;
    
    /** Fallback popup width when calculation fails */
    public static final int FALLBACK_POPUP_WIDTH = 800;
    
    /** Fallback popup height when calculation fails */
    public static final int FALLBACK_POPUP_HEIGHT = 600;
    
    /** Fallback card width for tablet */
    public static final int FALLBACK_TABLET_CARD_WIDTH = 600;
    
    /** Fallback card height for tablet */
    public static final int FALLBACK_TABLET_CARD_HEIGHT = 700;
    
    // ============================================================================
    // Timing Constants
    // ============================================================================
    
    /** Dialog dismiss delay in milliseconds */
    public static final int DIALOG_DISMISS_DELAY_MS = 1000;
    
    // ============================================================================
    // Visual Effects
    // ============================================================================
    
    /** Alpha fade multiplier for drag feedback */
    public static final float ALPHA_FADE_MULTIPLIER = 0.5f;
    
    /** Tablet size threshold in dp */
    public static final int TABLET_SIZE_THRESHOLD_DP = 600;
    
    // ============================================================================
    // Colors
    // ============================================================================
    
    /** Background dim color (semi-transparent black) */
    public static final String COLOR_BACKGROUND_DIM = "#80000000";
    
    public static final String COLOR_LIGHT_BG = "#F2F2F7";
    public static final String COLOR_DARK_BG = "#000000";
    public static final String COLOR_DARK_STROKE = "#38383A";
    public static final String COLOR_LIGHT_STROKE = "#E5E5EA";
    public static final String COLOR_DRAG_HANDLE = "#D1D1D6";
    public static final String COLOR_HOME_TEXT = "#8E8E93";
}
