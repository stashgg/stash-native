package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.content.Intent;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.LooperMode;
import org.robolectric.shadows.ShadowLooper;

/** dismiss() must cancel a card whose activity is still queued, and only that one. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
@LooperMode(LooperMode.Mode.PAUSED)
public class PendingLaunchDismissTest {
  private final StashNative sdk = StashNative.getInstance();
  private final List<String> events = new ArrayList<>();
  private Activity host;

  @Before public void prepare() {
    sdk.resetPresentationState();
    host = Robolectric.buildActivity(Activity.class).setup().get();
    Shadows.shadowOf(host.getApplication()).grantPermissions(
        host.getPackageName() + ".permission.STASH_NATIVE_INTERNAL");
    sdk.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onCardDismissed() { events.add("card-dismissed"); }
      @Override public void onPaymentSuccess(String order) { events.add("success"); }
    });
  }

  @After public void cleanup() {
    sdk.resetPresentationState();
    sdk.setListener(null);
    ShadowLooper.idleMainLooper();
  }

  @Test public void dismissBeforeTheActivityRegistersCancelsItAndReportsOnce() {
    sdk.openCard(host, "https://example.invalid/checkout", null);
    Intent intent = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(intent);
    sdk.dismiss();
    // Busy until the dismissal arrives, as during an animated dismissal.
    assertTrue(sdk.isCurrentlyPresented());
    sdk.openCard(host, "https://example.invalid/other", null);
    assertNull(Shadows.shadowOf(host).getNextStartedActivity());
    ShadowLooper.idleMainLooper();
    assertEquals(Collections.singletonList("card-dismissed"), events);
    assertFalse(sdk.isCurrentlyPresented());
    ActivityController<StashCardActivity> late =
        Robolectric.buildActivity(StashCardActivity.class, intent).create();
    assertTrue(late.get().isFinishing());
    late.destroy();
    sdk.dismiss();
    ShadowLooper.idleMainLooper();
    assertEquals(Collections.singletonList("card-dismissed"), events);
  }

  @Test public void resetAfterAPendingDismissStaysSilent() {
    sdk.openCard(host, "https://example.invalid/checkout", null);
    sdk.dismiss();
    sdk.resetPresentationState();
    ShadowLooper.idleMainLooper();
    assertTrue(events.isEmpty());
    assertFalse(sdk.isCurrentlyPresented());
  }

  @Test public void dismissAfterTheActivityEndedLeavesItsPendingResultAlone() {
    sdk.openCard(host, "https://example.invalid/checkout", null);
    ActivityController<StashCardActivity> card = Robolectric.buildActivity(
        StashCardActivity.class, Shadows.shadowOf(host).getNextStartedActivity())
        .create().start().resume();
    StashCheckoutBridge.emitPaymentSuccess(card.get(), "order", true);
    card.get().callbackSent = true;
    card.pause().stop().destroy();
    sdk.dismiss();
    ShadowLooper.idleMainLooper();
    assertEquals(Arrays.asList("success"), events);
    assertFalse(sdk.isCurrentlyPresented());
  }
}
