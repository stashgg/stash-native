package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.content.Intent;
import android.view.View;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.LooperMode;
import org.robolectric.shadows.ShadowLooper;

/** Browser handoffs must keep the originating checkout's lifetime across host callbacks. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
@LooperMode(LooperMode.Mode.PAUSED)
public class BrowserLifetimeTest {
  private final StashNativeCard sdk = StashNativeCard.getInstance();
  private final StashNativeCardPlugin plugin = StashNativeCardPlugin.getInstance();
  private Activity host;
  private StashCheckoutActivity checkout;
  private int externalPayments;
  private int browserClosed;

  @Before public void prepare() {
    sdk.resetPresentationState();
    host = Robolectric.buildActivity(Activity.class).setup().get();
    checkout = openCheckout();
    sdk.setListener(new StashNativeCard.StashNativeCardListenerAdapter() {
      @Override public void onExternalPayment(String url) { externalPayments++; }
      @Override public void onBrowserClosed() { browserClosed++; }
    });
  }

  @After public void cleanup() {
    sdk.resetPresentationState();
    sdk.setListener(null);
  }

  private StashCheckoutActivity openCheckout() {
    sdk.openCard(host, "https://example.invalid/checkout", null);
    Intent intent = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(intent);
    StashCheckoutActivity result = Robolectric.buildActivity(StashCheckoutActivity.class, intent).get();
    result.options = StashPresentationOptions.card(null);
    result.cardContainer = new StashSheetLayout(result, 24f);
    plugin.setCheckoutActivity(result);
    return result;
  }

  private void handoff() {
    new StashCheckoutJsInterface(checkout).openExternalBrowser("https://example.invalid/payment");
  }

  @Test public void queuedSignalFromResetCheckoutCannotRetireReplacement() throws Exception {
    Thread js = new Thread(this::handoff);
    js.start();
    js.join();
    sdk.resetPresentationState();
    StashCheckoutActivity replacement = openCheckout();
    ShadowLooper.idleMainLooper();
    assertEquals(0, externalPayments);
    assertTrue(sdk.isCurrentlyPresented());
    assertEquals(replacement.getPresentationSessionId(), plugin.presentationSessionId);
    assertNull(Shadows.shadowOf(checkout).getNextStartedActivity());
  }

  @Test public void resetInsideExternalPaymentCallbackCancelsLaunch() {
    sdk.setListener(new StashNativeCard.StashNativeCardListenerAdapter() {
      @Override public void onExternalPayment(String url) { sdk.resetPresentationState(); }
    });
    handoff();
    ShadowLooper.idleMainLooper();
    assertNull(Shadows.shadowOf(checkout).getNextStartedActivity());
    assertEquals(View.VISIBLE, checkout.cardContainer.getVisibility());
  }

  @Test public void replacementInsideExternalPaymentCallbackCancelsLaunch() {
    sdk.setListener(new StashNativeCard.StashNativeCardListenerAdapter() {
      @Override public void onExternalPayment(String url) { openCheckout(); }
    });
    handoff();
    ShadowLooper.idleMainLooper();
    assertNull(Shadows.shadowOf(checkout).getNextStartedActivity());
    assertTrue(sdk.isCurrentlyPresented());
    assertEquals(View.VISIBLE, checkout.cardContainer.getVisibility());
  }

  @Test public void repeatedHandoffLaunchesOnceAndClosesOnce() {
    handoff();
    handoff();
    ShadowLooper.idleMainLooper();
    assertEquals(1, externalPayments);
    Intent launched = Shadows.shadowOf(checkout).getNextStartedActivity();
    assertNotNull(launched);
    long sessionId = launched.getLongExtra(StashNativeBrowserProxyActivity.EXTRA_SESSION_ID, 0L);
    assertNull(Shadows.shadowOf(checkout).getNextStartedActivity());
    assertEquals(View.INVISIBLE, checkout.cardContainer.getVisibility());
    plugin.notifyBrowserClosedFromProxyInternal(sessionId);
    plugin.notifyBrowserEngagementSessionEndedFromProxyInternal(sessionId);
    ShadowLooper.idleMainLooper();
    assertEquals(1, browserClosed);
    assertTrue(checkout.isFinishing());
  }

  @Test public void replacementBeforeQueuedHideKeepsOldChromeUntouched() {
    handoff();
    openCheckout();
    ShadowLooper.idleMainLooper();
    assertEquals(View.VISIBLE, checkout.cardContainer.getVisibility());
    assertTrue(sdk.isCurrentlyPresented());
  }

  @Test public void replacementInsideBrowserClosedCallbackCannotRunOldDismissal() {
    handoff();
    sdk.setListener(new StashNativeCard.StashNativeCardListenerAdapter() {
      @Override public void onBrowserClosed() { openCheckout(); }
    });
    long sessionId = Shadows.shadowOf(checkout).getNextStartedActivity()
        .getLongExtra(StashNativeBrowserProxyActivity.EXTRA_SESSION_ID, 0L);
    plugin.notifyBrowserClosedFromProxyInternal(sessionId);
    ShadowLooper.idleMainLooper();
    assertFalse(checkout.isFinishing());
    assertTrue(sdk.isCurrentlyPresented());
  }
  @Test public void retiredProxyCannotCloseAReplacementBrowser() {
    handoff();
    Intent oldIntent = Shadows.shadowOf(checkout).getNextStartedActivity();
    StashNativeBrowserProxyActivity retired = Robolectric.buildActivity(
        StashNativeBrowserProxyActivity.class, oldIntent).get();
    sdk.resetPresentationState();
    checkout = openCheckout();
    handoff();
    retired.onActivityResult(CardConstants.REQUEST_CODE_STASH_CUSTOM_TAB, Activity.RESULT_CANCELED, null);
    ShadowLooper.idleMainLooper();
    assertEquals(0, browserClosed);
    assertFalse(checkout.isFinishing());
  }

  @Test public void resetBeforeProxyCreationCannotLaunchBrowser() {
    handoff();
    Intent intent = Shadows.shadowOf(checkout).getNextStartedActivity();
    sdk.resetPresentationState();
    // Robolectric records ordinary launches in its activity-result queue too.
    while (Shadows.shadowOf(checkout).getNextStartedActivityForResult() != null) {}
    StashNativeBrowserProxyActivity proxy = Robolectric.buildActivity(
        StashNativeBrowserProxyActivity.class, intent).create().get();
    ShadowLooper.idleMainLooper();
    assertTrue(proxy.isFinishing());
    assertNull(Shadows.shadowOf(proxy).getNextStartedActivityForResult());
    assertEquals(0, browserClosed);
  }

  @Test public void browserOpenedFromCloseCallbackSurvivesPreviousCheckoutTeardown() {
    handoff();
    long oldSession = Shadows.shadowOf(checkout).getNextStartedActivity()
        .getLongExtra(StashNativeBrowserProxyActivity.EXTRA_SESSION_ID, 0L);
    sdk.setListener(new StashNativeCard.StashNativeCardListenerAdapter() {
      @Override public void onBrowserClosed() {
        sdk.openBrowser(host, "https://example.invalid/next");
      }
    });
    plugin.notifyBrowserClosedFromProxyInternal(oldSession);
    long newSession = Shadows.shadowOf(host).getNextStartedActivity()
        .getLongExtra(StashNativeBrowserProxyActivity.EXTRA_SESSION_ID, 0L);
    ShadowLooper.idleMainLooper();
    assertTrue(checkout.isFinishing());
    assertTrue(plugin.isCurrentBrowserSession(newSession));
  }
}
