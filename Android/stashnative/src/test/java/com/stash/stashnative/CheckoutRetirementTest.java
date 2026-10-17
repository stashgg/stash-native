package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.content.Intent;
import java.util.ArrayList;
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

/** Retiring the old Activity must preserve a callback-created replacement and its teardown. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
@LooperMode(LooperMode.Mode.PAUSED)
public class CheckoutRetirementTest {
  private final StashNative sdk = StashNative.getInstance();
  private final List<ActivityController<StashCheckoutActivity>> checkouts = new ArrayList<>();
  private Activity host;
  private StashCheckoutActivity replacement;
  private int dismissed;

  @Before public void prepare() {
    sdk.resetPresentationState();
    host = Robolectric.buildActivity(Activity.class).setup().get();
    Shadows.shadowOf(host.getApplication()).grantPermissions(
        host.getPackageName() + ".permission.STASH_NATIVE_INTERNAL");
  }

  @After public void cleanup() {
    sdk.resetPresentationState();
    sdk.setListener(null);
    for (ActivityController<StashCheckoutActivity> controller : checkouts) {
      if (!controller.get().isDestroyed()) {
        controller.pause().stop().destroy();
      }
    }
    host.finish();
    ShadowLooper.idleMainLooper();
  }

  private StashCheckoutActivity open() {
    sdk.openCard(host, "https://example.invalid/checkout", null);
    Intent intent = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(intent);
    ActivityController<StashCheckoutActivity> controller =
        Robolectric.buildActivity(StashCheckoutActivity.class, intent).create().start().resume();
    checkouts.add(controller);
    return controller.get();
  }

  @Test public void externalPaymentReplacementRetiresOldActivityWithoutDismissalCallback() {
    StashCheckoutActivity original = open();
    sdk.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onExternalPayment(String url) { replacement = open(); }
      @Override public void onCardDismissed() { dismissed++; }
    });
    new StashCheckoutJsInterface(original).openExternalBrowser(
        original.issueBridgeDocumentToken(), "https://example.invalid/payment");
    assertNull(Shadows.shadowOf(original).getNextStartedActivity());
    assertReplacementSurvivesOriginalDestruction(original);
  }

  @Test public void browserCloseReplacementRetiresOldActivityWithoutDismissalCallback() {
    StashCheckoutActivity original = open();
    sdk.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onBrowserDismissed() { replacement = open(); }
      @Override public void onCardDismissed() { dismissed++; }
    });
    new StashCheckoutJsInterface(original).openExternalBrowser(
        original.issueBridgeDocumentToken(), "https://example.invalid/payment");
    Intent proxy = Shadows.shadowOf(original).getNextStartedActivity();
    assertNotNull(proxy);
    StashNativePlugin.getInstance().notifyBrowserClosedFromProxyInternal(
        proxy.getLongExtra(StashNativeBrowserProxyActivity.EXTRA_SESSION_ID, 0L));
    assertReplacementSurvivesOriginalDestruction(original);
  }

  private void assertReplacementSurvivesOriginalDestruction(StashCheckoutActivity original) {
    assertNotNull(replacement);
    assertTrue(original.isFinishing());
    checkouts.get(0).pause().stop().destroy();
    ShadowLooper.idleMainLooper();
    assertTrue(original.isDestroyed());
    assertFalse(replacement.isFinishing());
    assertTrue(sdk.isCurrentlyPresented());
    assertEquals(0, dismissed);
    sdk.resetPresentationState();
    assertTrue(replacement.isFinishing());
    assertFalse(sdk.isCurrentlyPresented());
  }
}
