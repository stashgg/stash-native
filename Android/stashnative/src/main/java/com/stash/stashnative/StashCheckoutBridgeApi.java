package com.stash.stashnative;

/**
 * Method-shape contract for the {@code window.stash_sdk} native bridge. Implemented by
 * {@link StashNativeCardPlugin}'s {@code StashJavaScriptInterface} (the popup dialog) and
 * {@link StashNativeCardPortraitActivity}'s {@code JSInterface} (the card and modal).
 *
 * <p>{@code @JavascriptInterface} is not inherited. Each concrete implementation method carries its
 * own {@code @JavascriptInterface} annotation; an unannotated method is invisible to the WebView in
 * release (R8) builds.
 */
interface StashCheckoutBridgeApi {

  void onPaymentSuccess(String order);

  void onPaymentFailure();

  void onPurchaseProcessing();

  void setPaymentChannel(String optinType);

  void expand();

  void collapse();

  void requestCloseFromPage();

  void openExternalBrowser(String url);
}
