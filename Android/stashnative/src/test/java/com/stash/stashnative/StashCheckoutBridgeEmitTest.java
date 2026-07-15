package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import android.content.Context;
import android.content.Intent;
import java.util.List;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Shadows;

/** Covers the five emit paths without an existing test (payloads + action names). */
@RunWith(RobolectricTestRunner.class)
public class StashCheckoutBridgeEmitTest {

  private Intent lastBroadcast(Context context) {
    List<Intent> sent =
        Shadows.shadowOf((android.app.Application) context).getBroadcastIntents();
    return sent.get(sent.size() - 1);
  }

  @Test
  public void paymentSuccessCarriesOrder() {
    Context context = RuntimeEnvironment.getApplication();
    StashCheckoutBridge.emitPaymentSuccess(context, "order-1", true);
    Intent i = lastBroadcast(context);
    assertEquals(CardConstants.BROADCAST_CHECKOUT_PAYMENT_SUCCESS, i.getAction());
    assertEquals("order-1", i.getStringExtra(CardConstants.BROADCAST_EXTRA_PAYMENT_ORDER));
    assertEquals(context.getPackageName(), i.getPackage());
  }

  @Test
  public void paymentSuccessOmitsEmptyOrder() {
    Context context = RuntimeEnvironment.getApplication();
    StashCheckoutBridge.emitPaymentSuccess(context, "", true);
    assertNull(lastBroadcast(context).getStringExtra(CardConstants.BROADCAST_EXTRA_PAYMENT_ORDER));
  }

  @Test
  public void plainEmits() {
    Context context = RuntimeEnvironment.getApplication();
    StashCheckoutBridge.emitPaymentFailure(context, true);
    assertEquals(CardConstants.BROADCAST_CHECKOUT_PAYMENT_FAILURE, lastBroadcast(context).getAction());
    StashCheckoutBridge.emitNetworkError(context);
    assertEquals(CardConstants.BROADCAST_CHECKOUT_NETWORK_ERROR, lastBroadcast(context).getAction());
    StashCheckoutBridge.emitDialogDismissed(context);
    assertEquals(CardConstants.BROADCAST_CHECKOUT_DIALOG_DISMISSED, lastBroadcast(context).getAction());
  }

  @Test
  public void optInCarriesTypeAndNullBecomesEmpty() {
    Context context = RuntimeEnvironment.getApplication();
    StashCheckoutBridge.emitOptIn(context, null);
    Intent i = lastBroadcast(context);
    assertEquals(CardConstants.BROADCAST_CHECKOUT_OPT_IN, i.getAction());
    assertEquals("", i.getStringExtra(CardConstants.BROADCAST_EXTRA_OPTIN_TYPE));
  }
}
