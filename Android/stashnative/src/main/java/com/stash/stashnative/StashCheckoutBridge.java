package com.stash.stashnative;

import android.content.Context;
import android.content.Intent;
import android.util.Log;

/**
 * Sends checkout lifecycle events from {@link StashCardActivity} to
 * {@link StashNativePlugin}'s receiver (same app process by default; package-local broadcasts).
 */
final class StashCheckoutBridge {
  private static final String TAG = "StashNative";
  static final String EXTRA_SESSION_ID = "com.stash.stashnative.SESSION_ID";

  /** Longest order payload broadcast to the host; 256 Ki chars stays under the Binder limit. */
  static final int MAX_PAYMENT_ORDER_CHARS = 256 * 1024;

  private StashCheckoutBridge() {}

  /** Truncates an oversized order payload so the success broadcast cannot fail. */
  static String capPaymentOrder(String order) {
    if (order == null || order.length() <= MAX_PAYMENT_ORDER_CHARS) {
      return order;
    }
    Log.w(TAG, "Payment order payload truncated from " + order.length() + " to "
        + MAX_PAYMENT_ORDER_CHARS + " chars");
    return order.substring(0, MAX_PAYMENT_ORDER_CHARS);
  }

  private static Intent baseIntent(Context context, String action) {
    Context app = context.getApplicationContext();
    Intent intent = new Intent(action);
    intent.setPackage(app.getPackageName());
    if (context instanceof StashCardActivity) {
      intent.putExtra(EXTRA_SESSION_ID,
          ((StashCardActivity) context).getPresentationSessionId());
    }
    return intent;
  }

  static void emitPaymentSuccess(Context context, String order, boolean willClose) {
    Intent intent = baseIntent(context, CardConstants.BROADCAST_CHECKOUT_PAYMENT_SUCCESS);
    if (order != null && !order.isEmpty()) {
      intent.putExtra(CardConstants.BROADCAST_EXTRA_PAYMENT_ORDER, order);
    }
    intent.putExtra(CardConstants.BROADCAST_EXTRA_WILL_CLOSE, willClose);
    context.getApplicationContext().sendBroadcast(intent);
  }

  static void emitPaymentFailure(Context context, boolean willClose) {
    Intent intent = baseIntent(context, CardConstants.BROADCAST_CHECKOUT_PAYMENT_FAILURE);
    intent.putExtra(CardConstants.BROADCAST_EXTRA_WILL_CLOSE, willClose);
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

  static void emitQrCodeScanned(Context context, String content) {
    Intent intent = baseIntent(context, CardConstants.BROADCAST_SCANNER_SCANNED);
    intent.putExtra(CardConstants.BROADCAST_EXTRA_SCANNER_CONTENT, content);
    context.getApplicationContext().sendBroadcast(intent);
  }

  static void emitScannerError(Context context, StashNative.ScannerError error) {
    Intent intent = baseIntent(context, CardConstants.BROADCAST_SCANNER_ERROR);
    intent.putExtra(CardConstants.BROADCAST_EXTRA_SCANNER_ERROR, error.name());
    context.getApplicationContext().sendBroadcast(intent);
  }
}
