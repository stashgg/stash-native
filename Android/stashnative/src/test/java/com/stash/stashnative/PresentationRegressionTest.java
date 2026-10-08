package com.stash.stashnative;

import static org.junit.Assert.*;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import java.lang.reflect.Method;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowLooper;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public class PresentationRegressionTest {
  private StashNativeCardPlugin plugin;
  private Activity host;

  @Before public void prepare() {
    plugin = StashNativeCardPlugin.getInstance();
    plugin.resetPresentationState();
    host = Robolectric.buildActivity(Activity.class).setup().get();
    // Local unit tests have no merged host manifest; grant its signature permission explicitly.
    Shadows.shadowOf(host.getApplication()).grantPermissions(
        host.getPackageName() + ".permission.STASH_NATIVE_INTERNAL");
    plugin.setActivity(host);
  }

  @After public void finish() {
    plugin.setListener(null);
    plugin.resetPresentationState();
    host.finish();
    ShadowLooper.idleMainLooper();
  }

  @Test @Config(sdk = {21, 32, 33})
  public void receiverRequiresPrivateDeliveryOnEverySupportedApi() {
    org.robolectric.shadows.ShadowApplication.Wrapper registration =
        Shadows.shadowOf(host.getApplication()).getRegisteredReceivers().stream()
            .filter(r -> r.intentFilter.hasAction(CardConstants.BROADCAST_CHECKOUT_PAGE_LOADED))
            .findFirst().get();
    if (android.os.Build.VERSION.SDK_INT >= 33) {
      assertEquals(Context.RECEIVER_NOT_EXPORTED, registration.flags);
    } else {
      assertEquals(host.getPackageName() + ".permission.STASH_NATIVE_INTERNAL",
          registration.broadcastPermission);
    }
  }

  @Test public void repeatedOpenDoesNotLaunchOrChangeConfiguration() {
    StashNativeCard.CardConfig config = new StashNativeCard.CardConfig();
    config.preferredContentHeight = 420f;
    plugin.openCard(host, "https://example.invalid", config);
    Intent first = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(first);
    plugin.openCard(host, "https://example.invalid/second", new StashNativeCard.CardConfig());
    assertNull(Shadows.shadowOf(host).getNextStartedActivity());
    assertEquals(420f, plugin.presentationOptions.height, 0.001f);
    assertEquals(420f, StashPresentationOptions.read(first).height, 0.001f);
  }

  @Test public void processingQueryUsesActiveActivityAndClearsOnReset() {
    plugin.openCard(host, "https://example.invalid", null);
    StashCheckoutActivity checkout = Robolectric.buildActivity(
        StashCheckoutActivity.class, Shadows.shadowOf(host).getNextStartedActivity()).get();
    plugin.setCheckoutActivity(checkout);
    checkout.isPurchaseProcessing = true;
    assertTrue(StashNativeCard.getInstance().isPurchaseProcessing());
    checkout.isPurchaseProcessing = false;
    assertFalse(StashNativeCard.getInstance().isPurchaseProcessing());
    plugin.resetPresentationState();
    assertFalse(plugin.isPurchaseProcessing());
  }

  @Test public void restoredCheckoutCancelsOnceWithoutReloading() {
    final int[] dismissed = {0};
    plugin.setListener(new StashNativeCard.StashNativeCardListenerAdapter() {
      @Override public void onDialogDismissed() { dismissed[0]++; }
    });
    plugin.openCard(host, "https://example.invalid", null);
    Intent intent = Shadows.shadowOf(host).getNextStartedActivity();
    Bundle saved = new Bundle();
    saved.putBoolean("stash.callbackSent", false);
    org.robolectric.android.controller.ActivityController<StashCheckoutActivity> controller =
        Robolectric.buildActivity(StashCheckoutActivity.class, intent).create(saved);
    assertTrue(controller.get().isFinishing());
    assertNull(controller.get().webView);
    controller.destroy();
    ShadowLooper.idleMainLooper();
    assertEquals(1, dismissed[0]);
    assertFalse(plugin.isCurrentlyPresented());
  }

  @Test public void activityLaunchedBeforeResetCannotReviveItsCheckout() {
    plugin.openCard(host, "https://example.invalid", null);
    Intent intent = Shadows.shadowOf(host).getNextStartedActivity();
    plugin.resetPresentationState();
    org.robolectric.android.controller.ActivityController<StashCheckoutActivity> controller =
        Robolectric.buildActivity(StashCheckoutActivity.class, intent).create();
    assertTrue(controller.get().isFinishing());
    assertNull(controller.get().webView);
    controller.destroy();
    assertFalse(plugin.isCurrentlyPresented());
  }

  @Test public void lateBridgeEventCannotCompleteReplacementCheckout() {
    final int[] results = {0};
    plugin.setListener(new StashNativeCard.StashNativeCardListenerAdapter() {
      @Override public void onPaymentSuccess(String order) { results[0]++; }
    });
    plugin.openCard(host, "https://example.invalid", null);
    long staleSession = plugin.presentationSessionId;
    plugin.resetPresentationState();
    plugin.setActivity(host);
    plugin.openCard(host, "https://example.invalid/next", null);
    Intent event = new Intent(CardConstants.BROADCAST_CHECKOUT_PAYMENT_SUCCESS);
    event.setPackage(host.getPackageName());
    event.putExtra(StashCheckoutBridge.EXTRA_SESSION_ID, staleSession);
    host.sendBroadcast(event);
    ShadowLooper.idleMainLooper();
    assertEquals(0, results[0]);
    assertTrue(plugin.isCurrentlyPresented());
  }

  @Test public void browserFailureLogsOmitCheckoutQuery() {
    org.robolectric.shadows.ShadowLog.clear();
    Shadows.shadowOf(host.getApplication()).checkActivities(true);
    StashUrlLauncher.openExternalUrl(host, "https://example.invalid/?secret=fixture-sensitive", 0);
    assertFalse(org.robolectric.shadows.ShadowLog.getLogs().stream()
        .anyMatch(log -> log.msg.contains("fixture-sensitive")));
  }

  @Test public void reflectionBridgeMethodsAreCallable() throws Exception {
    Method unbind = StashCustomTabsEngagement.class.getMethod("unbindIfBound", Context.class);
    unbind.invoke(null, host);
    Method launch = StashCustomTabsEngagement.class.getMethod("tryLaunchForResult",
        Activity.class, android.net.Uri.class, int.class,
        StashUrlLauncher.LaunchModeCallback.class, Runnable.class);
    assertEquals(false, launch.invoke(null, null, null, 0, null, null));
  }

  @Test @Config(sdk = {21, 23, 28})
  public void selectorIsStrippedBeforeLaunchingIntentUri() {
    StashCheckoutWebViewSupport.openDeeplinkExternally(host,
        "intent://example.invalid/#Intent;scheme=demo;SEL;component=com.example/.PrivateActivity;end");
    Intent launched = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(launched);
    assertNull(launched.getSelector());
    assertNull(launched.getComponent());
  }
}
