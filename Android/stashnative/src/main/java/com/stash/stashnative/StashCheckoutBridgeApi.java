package com.stash.stashnative;

/**
 * Compile-time contract for the {@code window.stash_sdk} native bridge. Both bridge
 * implementations -- {@link StashNativeCardPlugin}'s {@code StashJavaScriptInterface} (modal and
 * popup dialogs) and {@link StashNativeCardPortraitActivity}'s {@code JSInterface} (the portrait
 * card) -- implement this so the two cannot drift in method shape.
 *
 * <p>This enforces parity between the two Java bridges only. The actual JS surface is mirrored in
 * {@code StashWebViewUtils.JS_SDK_SCRIPT}, the iOS {@code stashSDKScript}, and
 * {@code docs/stash-sdk-js.md}; those remain the canonical spec.
 *
 * <p>{@code @JavascriptInterface} is not inherited, so every concrete implementation method must
 * keep its own {@code @JavascriptInterface} annotation -- declaring the methods here does not
 * annotate them, and an unannotated method is invisible to the WebView in release (R8) builds.
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
