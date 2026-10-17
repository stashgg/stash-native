package com.stash.stashnative;

import static org.junit.Assert.*;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.shadows.ShadowLooper;

@RunWith(RobolectricTestRunner.class)
public class StashCheckoutBridgeTest {

  @Test
  public void emitPageLoaded_setsActionAndExtra() {
    Context app = RuntimeEnvironment.getApplication();
    final Intent[] captured = new Intent[1];
    BroadcastReceiver receiver =
        new BroadcastReceiver() {
          @Override
          public void onReceive(Context context, Intent intent) {
            captured[0] = intent;
          }
        };
    app.registerReceiver(
        receiver, new IntentFilter(CardConstants.BROADCAST_CHECKOUT_PAGE_LOADED));

    try {
      StashCheckoutBridge.emitPageLoaded(app, 1234L);
      ShadowLooper.idleMainLooper();

      assertNotNull(captured[0]);
      assertEquals(CardConstants.BROADCAST_CHECKOUT_PAGE_LOADED, captured[0].getAction());
      assertEquals(1234L, captured[0].getLongExtra(CardConstants.BROADCAST_EXTRA_PAGE_LOAD_MS, -1L));
    } finally {
      app.unregisterReceiver(receiver);
    }
  }

  @Test
  public void oversizedOrderIsTruncatedBeforeBroadcast() {
    int max = StashCheckoutBridge.MAX_PAYMENT_ORDER_CHARS;
    StringBuilder big = new StringBuilder(max + 16);
    while (big.length() < max + 16) {
      big.append('x');
    }
    assertEquals(max, StashCheckoutBridge.capPaymentOrder(big.toString()).length());
    String exact = big.substring(0, max);
    assertSame(exact, StashCheckoutBridge.capPaymentOrder(exact));
    assertSame("order", StashCheckoutBridge.capPaymentOrder("order"));
    assertNull(StashCheckoutBridge.capPaymentOrder(null));
  }
}
