package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.content.Intent;
import android.os.Looper;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.Implementation;
import org.robolectric.annotation.Implements;
import org.robolectric.annotation.LooperMode;
import org.robolectric.shadows.ShadowContextImpl;

/** A payment broadcast the system rejects must still release the presentation exactly once. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28, shadows = PaymentBroadcastFailureTest.ThrowingPaymentBroadcast.class)
@LooperMode(LooperMode.Mode.PAUSED)
public class PaymentBroadcastFailureTest {
  private final StashNative sdk = StashNative.getInstance();
  private final StashNativePlugin plugin = StashNativePlugin.getInstance();
  private final List<String> events = new ArrayList<>();
  private Activity host;

  @Before public void prepare() {
    sdk.resetPresentationState();
    sdk.setListener(null);
    host = Robolectric.buildActivity(Activity.class).setup().get();
    Shadows.shadowOf(host.getApplication()).grantPermissions(
        host.getPackageName() + ".permission.STASH_NATIVE_INTERNAL");
    sdk.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onPaymentSuccess(String order) {
        events.add("payment:" + order);
      }

      @Override public void onNetworkError() {
        events.add("network-error");
      }

      @Override public void onCardDismissed() {
        events.add("card-dismissed");
      }
    });
  }

  @After public void cleanup() {
    sdk.resetPresentationState();
    sdk.setListener(null);
    host.finish();
  }

  private StashCardActivity open() {
    sdk.openCard(host, "https://example.invalid/checkout", null);
    Intent intent = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(intent);
    StashCardActivity card =
        Robolectric.buildActivity(StashCardActivity.class, intent).get();
    card.options = StashPresentationOptions.card(null);
    card.cardContainer = new StashSheetLayout(card, 24f);
    plugin.setCheckoutActivity(card);
    return card;
  }

  @Test public void failedPaymentBroadcastEndsCheckoutAsNetworkErrorAndReleasesPresentation() {
    StashCardActivity card = open();
    card.isPurchaseProcessing = true;
    assertTrue(sdk.isCurrentlyPresented());
    card.notifyPaymentResult(true, "order");
    Shadows.shadowOf(Looper.getMainLooper()).idle();
    assertTrue(card.isFinishing());
    assertTrue(card.callbackSent);
    assertTrue(card.networkErrorHandled);
    assertFalse(card.isPurchaseProcessing);
    assertEquals(Arrays.asList("network-error"), events);
    assertFalse(sdk.isCurrentlyPresented());
    card.notifyPaymentResult(true, "order");
    Shadows.shadowOf(Looper.getMainLooper()).idle();
    assertEquals(Arrays.asList("network-error"), events);
  }

  @Test public void paymentFailureBroadcastStillDeliversWhenOnlySuccessIsRejected() {
    StashCardActivity card = open();
    card.notifyPaymentResult(false, null);
    Shadows.shadowOf(Looper.getMainLooper()).idle();
    assertTrue(card.callbackSent);
    assertFalse(card.networkErrorHandled);
    assertFalse(sdk.isCurrentlyPresented());
    assertTrue(events.isEmpty());
  }

  /** Rejects the success broadcast the way Binder rejects an oversized transaction. */
  @Implements(className = "android.app.ContextImpl")
  public static class ThrowingPaymentBroadcast extends ShadowContextImpl {
    @Implementation
    @Override
    protected void sendBroadcast(Intent intent) {
      if (CardConstants.BROADCAST_CHECKOUT_PAYMENT_SUCCESS.equals(intent.getAction())) {
        throw new RuntimeException("Failure from system: transaction too large");
      }
      super.sendBroadcast(intent);
    }
  }
}
