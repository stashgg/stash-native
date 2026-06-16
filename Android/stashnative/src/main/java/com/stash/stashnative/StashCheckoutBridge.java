package com.stash.stashnative;

import android.content.Context;
import android.content.Intent;

/**
 * Sends checkout lifecycle events from {@link StashNativeCardPortraitActivity} to
 * {@link StashNativeCardPlugin}'s receiver (same app process by default; package-local broadcasts).
 */
final class StashCheckoutBridge {

  private StashCheckoutBridge() {}

  private static Intent baseIntent(Context context, String action) {
    Context app = context.getApplicationContext();
    Intent intent = new Intent(action);
    intent.setPackage(app.getPackageName());
    return intent;
  }

  static void emitPaymentSuccess(Context context, String order) {
    Intent intent = baseIntent(context, CardConstants.BROADCAST_CHECKOUT_PAYMENT_SUCCESS);
    if (order != null && !order.isEmpty()) {
      intent.putExtra(CardConstants.BROADCAST_EXTRA_PAYMENT_ORDER, order);
    }
    context.getApplicationContext().sendBroadcast(intent);
  }

  static void emitPaymentFailure(Context context) {
    context.getApplicationContext().sendBroadcast(
        baseIntent(context, CardConstants.BROADCAST_CHECKOUT_PAYMENT_FAILURE));
  }

  static void emitOptIn(Context context, String optinType) {
    Intent intent = baseIntent(context, CardConstants.BROADCAST_CHECKOUT_OPT_IN);
    intent.putExtra(CardConstants.BROADCAST_EXTRA_OPTIN_TYPE, optinType != null ? optinType : "");
    context.getApplicationContext().sendBroadcast(intent);
  }

  static void emitNetworkError(Context context) {
    context.getApplicationContext().sendBroadcast(
        baseIntent(context, CardConstants.BROADCAST_CHECKOUT_NETWORK_ERROR));
  }

  static void emitDialogDismissed(Context context) {
    context.getApplicationContext().sendBroadcast(
        baseIntent(context, CardConstants.BROADCAST_CHECKOUT_DIALOG_DISMISSED));
  }

  static void emitPageLoaded(Context context, long loadTimeMs) {
    Intent intent = baseIntent(context, CardConstants.BROADCAST_CHECKOUT_PAGE_LOADED);
    intent.putExtra(CardConstants.BROADCAST_EXTRA_PAGE_LOAD_MS, loadTimeMs);
    context.getApplicationContext().sendBroadcast(intent);
  }
}
