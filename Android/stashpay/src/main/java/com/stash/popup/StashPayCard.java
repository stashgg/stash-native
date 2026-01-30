package com.stash.popup;

import android.app.Activity;

/**
 * StashPayCard - Native Android SDK for Stash Pay checkout integration.
 * 
 * This is the main entry point for integrating Stash Pay checkout into your Android app.
 * It provides methods to display checkout cards and popups, and handles payment callbacks.
 * 
 * Usage:
 * <pre>
 * StashPayCard.getInstance().setActivity(this);
 * StashPayCard.getInstance().setListener(new StashPayCard.StashPayListener() {
 *     @Override
 *     public void onPaymentSuccess() {
 *         // Handle successful payment
 *     }
 *     
 *     @Override
 *     public void onPaymentFailure() {
 *         // Handle failed payment
 *     }
 *     
 *     @Override
 *     public void onDialogDismissed() {
 *         // Handle dialog dismissed
 *     }
 *     
 *     @Override
 *     public void onOptInResponse(String optinType) {
 *         // Handle opt-in response
 *     }
 *     
 *     @Override
 *     public void onPageLoaded(long loadTimeMs) {
 *         // Handle page loaded
 *     }
 * });
 * 
 * StashPayCard.getInstance().openCheckout("https://your-checkout-url.com");
 * </pre>
 */
public class StashPayCard {
    private static StashPayCard instance;
    private StashPayCardPlugin plugin;
    private Activity activity;
    private StashPayListener listener;
    
    /**
     * Callback interface for Stash Pay events.
     */
    public interface StashPayListener {
        /**
         * Called when a payment completes successfully.
         */
        void onPaymentSuccess();
        
        /**
         * Called when a payment fails.
         */
        void onPaymentFailure();
        
        /**
         * Called when the checkout dialog is dismissed by the user.
         */
        void onDialogDismissed();
        
        /**
         * Called when an opt-in response is received.
         * @param optinType The type of opt-in response
         */
        void onOptInResponse(String optinType);
        
        /**
         * Called when the checkout page finishes loading.
         * @param loadTimeMs The page load time in milliseconds
         */
        void onPageLoaded(long loadTimeMs);
    }
    
    /**
     * Simple adapter class for StashPayListener with empty default implementations.
     * Extend this class if you only need to implement some callbacks.
     */
    public static class StashPayListenerAdapter implements StashPayListener {
        @Override public void onPaymentSuccess() {}
        @Override public void onPaymentFailure() {}
        @Override public void onDialogDismissed() {}
        @Override public void onOptInResponse(String optinType) {}
        @Override public void onPageLoaded(long loadTimeMs) {}
    }
    
    /**
     * Configuration for custom popup sizing.
     */
    public static class PopupSizeConfig {
        public float portraitWidthMultiplier = 1.0285f;
        public float portraitHeightMultiplier = 1.485f;
        public float landscapeWidthMultiplier = 1.2275445f;
        public float landscapeHeightMultiplier = 1.1385f;
        
        public PopupSizeConfig() {}
        
        public PopupSizeConfig(float portraitWidth, float portraitHeight, 
                               float landscapeWidth, float landscapeHeight) {
            this.portraitWidthMultiplier = portraitWidth;
            this.portraitHeightMultiplier = portraitHeight;
            this.landscapeWidthMultiplier = landscapeWidth;
            this.landscapeHeightMultiplier = landscapeHeight;
        }
    }
    
    private StashPayCard() {
        plugin = StashPayCardPlugin.getInstance();
    }
    
    /**
     * Gets the singleton instance of StashPayCard.
     * @return The StashPayCard instance
     */
    public static synchronized StashPayCard getInstance() {
        if (instance == null) {
            instance = new StashPayCard();
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
        this.activity = activity;
        plugin.setActivity(activity);
    }
    
    /**
     * Sets the listener for Stash Pay events.
     * 
     * @param listener The listener to receive callbacks
     */
    public void setListener(StashPayListener listener) {
        this.listener = listener;
        plugin.setListener(listener);
    }
    
    /**
     * Gets the current listener.
     * @return The current StashPayListener
     */
    public StashPayListener getListener() {
        return listener;
    }
    
    /**
     * Opens a Stash Pay checkout URL in a sliding card UI.
     * 
     * The card slides up from the bottom of the screen and displays the checkout page.
     * On tablets, the card appears centered on screen.
     * 
     * @param url The Stash Pay checkout URL to load
     */
    public void openCheckout(String url) {
        plugin.openCheckout(url);
    }
    
    /**
     * Opens a Stash Pay URL in a centered popup dialog.
     * 
     * The popup appears centered on screen with a semi-transparent background.
     * Uses default sizing appropriate for the device.
     * 
     * @param url The Stash Pay URL to load
     */
    public void openPopup(String url) {
        plugin.openPopup(url);
    }
    
    /**
     * Opens a Stash Pay URL in a centered popup dialog with custom sizing.
     * 
     * @param url The Stash Pay URL to load
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
     * @return true if a checkout UI is currently visible
     */
    public boolean isCurrentlyPresented() {
        return plugin.isCurrentlyPresented();
    }
    
    /**
     * Gets whether web-based checkout (Chrome Custom Tabs) is forced.
     * @return true if Chrome Custom Tabs is forced
     */
    public boolean isForceWebBasedCheckout() {
        return plugin.getForceSafariViewController();
    }
    
    /**
     * Sets whether to force web-based checkout using Chrome Custom Tabs.
     * 
     * When enabled, checkout URLs open in Chrome Custom Tabs instead of 
     * the in-app card UI.
     * 
     * @param force true to use Chrome Custom Tabs, false for in-app card UI
     */
    public void setForceWebBasedCheckout(boolean force) {
        plugin.setForceSafariViewController(force);
    }
    
    /**
     * Checks if a purchase is currently being processed.
     * 
     * When true, the checkout dialog cannot be dismissed by the user
     * to prevent interrupting the payment flow.
     * 
     * @return true if a purchase is being processed
     */
    public boolean isPurchaseProcessing() {
        return plugin.isPurchaseProcessing();
    }
    
    /**
     * Sets the card height ratio for checkout card presentation.
     * 
     * @param heightRatio Height ratio (0.0 to 1.0) relative to screen height
     * @param verticalPosition Vertical position ratio (0.0 = bottom, 1.0 = top)
     * @param widthRatio Width ratio (0.0 to 1.0) relative to screen width
     * @deprecated Use individual setters: setCardHeightRatio(), setCardWidthRatio(), etc.
     */
    @Deprecated
    public void setCardConfiguration(float heightRatio, float verticalPosition, float widthRatio) {
        plugin.setCardConfiguration(heightRatio, verticalPosition, widthRatio);
    }
    
    // ============================================================================
    // Phone Card Size Configuration
    // ============================================================================
    
    /**
     * Gets the card height ratio for phone checkout presentation.
     * 
     * @return Height ratio (0.1 to 1.0) relative to screen height
     */
    public float getCardHeightRatio() {
        return plugin.getCardHeightRatio();
    }
    
    /**
     * Sets the card height ratio for phone checkout presentation.
     * This controls how tall the checkout card appears on phones.
     * 
     * @param ratio Height ratio (0.1 to 1.0) relative to screen height. Default is 0.68.
     */
    public void setCardHeightRatio(float ratio) {
        plugin.setCardHeightRatio(ratio);
    }
    
    /**
     * Gets the card width ratio for phone checkout presentation.
     * 
     * @return Width ratio (0.1 to 1.0) relative to screen width
     */
    public float getCardWidthRatio() {
        return plugin.getCardWidthRatio();
    }
    
    /**
     * Sets the card width ratio for phone checkout presentation.
     * This controls how wide the checkout card appears on phones.
     * 
     * @param ratio Width ratio (0.1 to 1.0) relative to screen width. Default is 1.0 (full width).
     */
    public void setCardWidthRatio(float ratio) {
        plugin.setCardWidthRatio(ratio);
    }
    
    // ============================================================================
    // Tablet Card Size Configuration
    // ============================================================================
    
    /**
     * Gets the tablet width ratio for tablet checkout presentation.
     * 
     * @return Width ratio (0.1 to 1.0) relative to screen width
     */
    public float getTabletWidthRatio() {
        return plugin.getTabletWidthRatio();
    }
    
    /**
     * Sets the tablet width ratio for tablet checkout presentation.
     * This controls how wide the checkout card appears on tablets.
     * 
     * @param ratio Width ratio (0.1 to 1.0) relative to screen width. Default is 0.8.
     */
    public void setTabletWidthRatio(float ratio) {
        plugin.setTabletWidthRatio(ratio);
    }
    
    /**
     * Gets the tablet height ratio for tablet checkout presentation.
     * 
     * @return Height ratio (0.1 to 1.0) relative to screen height
     */
    public float getTabletHeightRatio() {
        return plugin.getTabletHeightRatio();
    }
    
    /**
     * Sets the tablet height ratio for tablet checkout presentation.
     * This controls how tall the checkout card appears on tablets.
     * 
     * @param ratio Height ratio (0.1 to 1.0) relative to screen height. Default is 0.75.
     */
    public void setTabletHeightRatio(float ratio) {
        plugin.setTabletHeightRatio(ratio);
    }
    
    // ============================================================================
    // Orientation-Specific Phone Card Size Configuration
    // ============================================================================
    
    /**
     * Gets the card height ratio for portrait orientation on phones.
     * @return Height ratio (0.1 to 1.0) relative to screen height
     */
    public float getCardHeightRatioPortrait() {
        return plugin.getCardHeightRatioPortrait();
    }
    
    /**
     * Sets the card height ratio for portrait orientation on phones.
     * @param ratio Height ratio (0.1 to 1.0). Default is 0.68.
     */
    public void setCardHeightRatioPortrait(float ratio) {
        plugin.setCardHeightRatioPortrait(ratio);
    }
    
    /**
     * Gets the card height ratio for landscape orientation on phones.
     * @return Height ratio (0.1 to 1.0) relative to screen height
     */
    public float getCardHeightRatioLandscape() {
        return plugin.getCardHeightRatioLandscape();
    }
    
    /**
     * Sets the card height ratio for landscape orientation on phones.
     * @param ratio Height ratio (0.1 to 1.0). Default is 0.5.
     */
    public void setCardHeightRatioLandscape(float ratio) {
        plugin.setCardHeightRatioLandscape(ratio);
    }
    
    /**
     * Gets the card width ratio for portrait orientation on phones.
     * @return Width ratio (0.1 to 1.0) relative to screen width
     */
    public float getCardWidthRatioPortrait() {
        return plugin.getCardWidthRatioPortrait();
    }
    
    /**
     * Sets the card width ratio for portrait orientation on phones.
     * @param ratio Width ratio (0.1 to 1.0). Default is 1.0.
     */
    public void setCardWidthRatioPortrait(float ratio) {
        plugin.setCardWidthRatioPortrait(ratio);
    }
    
    /**
     * Gets the card width ratio for landscape orientation on phones.
     * @return Width ratio (0.1 to 1.0) relative to screen width
     */
    public float getCardWidthRatioLandscape() {
        return plugin.getCardWidthRatioLandscape();
    }
    
    /**
     * Sets the card width ratio for landscape orientation on phones.
     * @param ratio Width ratio (0.1 to 1.0). Default is 0.8.
     */
    public void setCardWidthRatioLandscape(float ratio) {
        plugin.setCardWidthRatioLandscape(ratio);
    }
    
    // ============================================================================
    // Orientation-Specific Tablet Card Size Configuration
    // ============================================================================
    
    /**
     * Gets the tablet width ratio for portrait orientation.
     * @return Width ratio (0.1 to 1.0) relative to screen width
     */
    public float getTabletWidthRatioPortrait() {
        return plugin.getTabletWidthRatioPortrait();
    }
    
    /**
     * Sets the tablet width ratio for portrait orientation.
     * @param ratio Width ratio (0.1 to 1.0). Default is 0.6.
     */
    public void setTabletWidthRatioPortrait(float ratio) {
        plugin.setTabletWidthRatioPortrait(ratio);
    }
    
    /**
     * Gets the tablet height ratio for portrait orientation.
     * @return Height ratio (0.1 to 1.0) relative to screen height
     */
    public float getTabletHeightRatioPortrait() {
        return plugin.getTabletHeightRatioPortrait();
    }
    
    /**
     * Sets the tablet height ratio for portrait orientation.
     * @param ratio Height ratio (0.1 to 1.0). Default is 0.8.
     */
    public void setTabletHeightRatioPortrait(float ratio) {
        plugin.setTabletHeightRatioPortrait(ratio);
    }
    
    /**
     * Gets the tablet width ratio for landscape orientation.
     * @return Width ratio (0.1 to 1.0) relative to screen width
     */
    public float getTabletWidthRatioLandscape() {
        return plugin.getTabletWidthRatioLandscape();
    }
    
    /**
     * Sets the tablet width ratio for landscape orientation.
     * @param ratio Width ratio (0.1 to 1.0). Default is 0.8.
     */
    public void setTabletWidthRatioLandscape(float ratio) {
        plugin.setTabletWidthRatioLandscape(ratio);
    }
    
    /**
     * Gets the tablet height ratio for landscape orientation.
     * @return Height ratio (0.1 to 1.0) relative to screen height
     */
    public float getTabletHeightRatioLandscape() {
        return plugin.getTabletHeightRatioLandscape();
    }
    
    /**
     * Sets the tablet height ratio for landscape orientation.
     * @param ratio Height ratio (0.1 to 1.0). Default is 0.65.
     */
    public void setTabletHeightRatioLandscape(float ratio) {
        plugin.setTabletHeightRatioLandscape(ratio);
    }
}
