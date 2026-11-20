package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.app.Application;
import android.content.Intent;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.android.controller.ServiceController;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.LooperMode;
import org.robolectric.shadows.ShadowLooper;

/** A keepOpen browser leaves the card presented and is cleared whenever the card ends. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
@LooperMode(LooperMode.Mode.PAUSED)
public class BrowserLifetimeTest {
  private static final String PAYMENT_URL = "https://example.invalid/payment";

  private final StashNativeCard sdk = StashNativeCard.getInstance();
  private final StashNativeCardPlugin plugin = StashNativeCardPlugin.getInstance();
  private Activity host;
  private StashNativeCardPortraitActivity checkout;
  private int externalPayments;
  private int browserClosed;
  private int paymentSuccesses;
  private int dialogDismissals;
  private String externalUrl;

  @Before
  public void prepare() {
    sdk.resetPresentationState();
    StashKeepAliveService.resetStartTrackingForTests();
    host = Robolectric.buildActivity(Activity.class).setup().get();
    sdk.setActivity(host);
    sdk.setListener(
        new StashNativeCard.StashNativeCardListenerAdapter() {
          @Override
          public void onExternalPayment(String url) {
            externalPayments++;
            externalUrl = url;
          }

          @Override
          public void onBrowserClosed() {
            browserClosed++;
          }

          @Override
          public void onPaymentSuccess(String order) {
            paymentSuccesses++;
          }

          @Override
          public void onDialogDismissed() {
            dialogDismissals++;
          }
        });
    checkout = openCheckout();
  }

  @After
  public void cleanup() {
    sdk.resetPresentationState();
    plugin.clearPortraitActivity(checkout);
    sdk.setListener(null);
    Shadows.shadowOf(host.getApplication()).checkActivities(false);
    sdk.setKeepAliveEnabled(false);
    StashKeepAliveService.resetStartTrackingForTests();
  }

  private StashNativeCardPortraitActivity openCheckout() {
    sdk.openCard("https://example.invalid/checkout", null);
    Intent intent = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(intent);
    StashNativeCardPortraitActivity result =
        Robolectric.buildActivity(StashNativeCardPortraitActivity.class, intent).get();
    plugin.setPortraitActivity(result);
    return result;
  }

  // Drives the plugin path the JS interface takes on a host with Custom Tabs.
  private void keepOpen() {
    String themed =
        StashWebViewUtils.appendThemeQueryParameter(
            StashWebViewUtils.normalizeExternalPaymentUrl(PAYMENT_URL),
            checkout.effectiveIsDarkForContent);
    plugin.openExternalBrowserOverCheckout(checkout, themed);
    ShadowLooper.idleMainLooper();
  }

  private Intent nextStarted() {
    return Shadows.shadowOf(checkout).getNextStartedActivity();
  }

  private static void assertClearsToTheCard(Intent back) {
    assertNotNull(back);
    assertEquals(
        StashNativeCardPortraitActivity.class.getName(), back.getComponent().getClassName());
    int expected = Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP;
    assertEquals(expected, back.getFlags() & expected);
  }

  @Test
  public void keepOpenOpensOverTheCardAndEndsNothing() {
    keepOpen();
    assertEquals(1, externalPayments);
    assertTrue(externalUrl.startsWith(PAYMENT_URL));
    Intent launched = nextStarted();
    assertNotNull(launched);
    assertEquals(Intent.ACTION_VIEW, launched.getAction());
    assertEquals(externalUrl, launched.getDataString());
    assertNull(launched.getComponent());
    assertNull(nextStarted());
    assertFalse(checkout.isFinishing());
    assertFalse(checkout.callbackSent);
    assertTrue(sdk.isCurrentlyPresented());
    assertTrue(checkout.externalBrowserOverCard);
    assertEquals(0, browserClosed);
  }

  @Test
  public void externalBrowserWithoutKeepOpenIsTheCardClosingHandoff() {
    new StashCheckoutJsInterface(checkout).externalBrowser(PAYMENT_URL, false);
    ShadowLooper.idleMainLooper();
    assertEquals(1, externalPayments);
    assertTrue(checkout.callbackSent);
    assertFalse(sdk.isCurrentlyPresented());
    assertFalse(checkout.externalBrowserOverCard);
  }

  @Test
  public void keepOpenWithoutCustomTabsTakesTheHandoff() {
    assertFalse(StashUrlLauncher.isCustomTabsClassAvailable());
    new StashCheckoutJsInterface(checkout).externalBrowser(PAYMENT_URL, true);
    ShadowLooper.idleMainLooper();
    assertEquals(1, externalPayments);
    assertTrue(checkout.callbackSent);
    assertFalse(sdk.isCurrentlyPresented());
    assertFalse(checkout.externalBrowserOverCard);
  }

  @Test
  public void openExternalBrowserIsTheSameHandoff() {
    new StashCheckoutJsInterface(checkout).openExternalBrowser(PAYMENT_URL);
    ShadowLooper.idleMainLooper();
    assertEquals(1, externalPayments);
    assertTrue(checkout.callbackSent);
    assertFalse(sdk.isCurrentlyPresented());
    assertFalse(checkout.externalBrowserOverCard);
  }

  @Test
  public void repeatedAndPausedKeepOpenCallsAreIgnored() {
    keepOpen();
    keepOpen();
    assertEquals(1, externalPayments);
    assertNotNull(nextStarted());
    assertNull(nextStarted());
    // A call while the card sits paused beneath the browser is still a repeat.
    checkout.onPause();
    keepOpen();
    assertEquals(1, externalPayments);
    assertNull(nextStarted());
    // Back on the card, the page may open the browser again.
    checkout.onResume();
    assertFalse(checkout.externalBrowserOverCard);
    keepOpen();
    assertEquals(2, externalPayments);
    assertNotNull(nextStarted());
    assertTrue(sdk.isCurrentlyPresented());
    assertEquals(0, browserClosed);
  }

  @Test
  public void keepOpenWithNoBrowserReleasesTheRequestAndKeepAlive() {
    Application app = host.getApplication();
    sdk.setKeepAliveEnabled(true);
    Shadows.shadowOf(app).checkActivities(true);
    keepOpen();
    assertEquals(1, externalPayments);
    assertNull(nextStarted());
    assertFalse(checkout.externalBrowserOverCard);
    assertNull(Shadows.shadowOf(app).getNextStartedService());
    // Nothing covered the card, so the page's next request is not taken for a repeat.
    Shadows.shadowOf(app).checkActivities(false);
    keepOpen();
    assertEquals(2, externalPayments);
    assertNotNull(nextStarted());
    assertTrue(checkout.externalBrowserOverCard);
    assertFalse(checkout.isFinishing());
    assertTrue(sdk.isCurrentlyPresented());
  }

  @Test
  public void keepOpenStartsKeepAliveAfterTheBrowserLaunches() {
    Application app = host.getApplication();
    sdk.setKeepAliveEnabled(true);
    keepOpen();
    assertNotNull(nextStarted());
    assertNotNull(Shadows.shadowOf(app).getNextStartedService());
  }

  /** Covers the card with a keepOpen browser, ends the card, and expects the browser cleared. */
  private void assertEndingTheCardClosesItsBrowser(Runnable end) {
    checkout.onResume();
    keepOpen();
    assertNotNull(nextStarted());
    checkout.onPause();
    end.run();
    ShadowLooper.idleMainLooper();
    assertClearsToTheCard(nextStarted());
    assertTrue(checkout.isFinishing());
    assertFalse(checkout.externalBrowserOverCard);
  }

  @Test
  public void paymentSuccessClosesTheKeepOpenBrowserWithTheCard() {
    assertEndingTheCardClosesItsBrowser(
        () -> new StashCheckoutJsInterface(checkout).onPaymentSuccess("{}"));
    assertEquals(1, paymentSuccesses);
    assertEquals(0, browserClosed);
  }

  @Test
  public void paymentFailureClosesTheKeepOpenBrowserWithTheCard() {
    assertEndingTheCardClosesItsBrowser(
        () -> new StashCheckoutJsInterface(checkout).onPaymentFailure());
  }

  @Test
  public void pageCloseClosesTheKeepOpenBrowserWithTheCard() {
    assertEndingTheCardClosesItsBrowser(
        () -> new StashCheckoutJsInterface(checkout).requestCloseFromPage());
  }

  @Test
  public void hostDismissClosesTheKeepOpenBrowserWithTheCard() {
    assertEndingTheCardClosesItsBrowser(sdk::dismiss);
  }

  @Test
  public void resetClosesTheKeepOpenBrowserWithTheCard() {
    assertEndingTheCardClosesItsBrowser(sdk::resetPresentationState);
  }

  @Test
  public void networkErrorClosesTheKeepOpenBrowserWithTheCard() {
    assertEndingTheCardClosesItsBrowser(checkout::handleNetworkError);
  }

  @Test
  public void endingAnUncoveredCardStartsNothing() {
    new StashCheckoutJsInterface(checkout).requestCloseFromPage();
    ShadowLooper.idleMainLooper();
    assertNull(nextStarted());
    assertTrue(checkout.isFinishing());
  }

  @Test
  public void dismissInsideTheExternalPaymentCallbackLaunchesNoBrowser() {
    sdk.setListener(
        new StashNativeCard.StashNativeCardListenerAdapter() {
          @Override
          public void onExternalPayment(String url) {
            externalPayments++;
            sdk.dismiss();
          }

          @Override
          public void onDialogDismissed() {
            dialogDismissals++;
          }
        });
    keepOpen();
    assertEquals(1, externalPayments);
    Intent started;
    while ((started = nextStarted()) != null) {
      assertFalse(Intent.ACTION_VIEW.equals(started.getAction()));
    }
    assertTrue(checkout.isFinishing());
    assertFalse(checkout.externalBrowserOverCard);
    checkout.onDestroy();
    ShadowLooper.idleMainLooper();
    assertEquals(1, dialogDismissals);
  }

  @Test
  public void listenerDismissBeforeLaunchDoesNotClearTheHostTask() {
    sdk.setListener(
        new StashNativeCard.StashNativeCardListenerAdapter() {
          @Override
          public void onExternalPayment(String url) {
            externalPayments++;
            host.startActivity(new Intent(host, Activity.class));
            sdk.dismiss();
          }
        });
    checkout.onResume();
    keepOpen();
    assertEquals(1, externalPayments);
    assertFalse(checkout.externalBrowserOverCard);
    Intent started;
    while ((started = nextStarted()) != null) {
      assertFalse(Intent.ACTION_VIEW.equals(started.getAction()));
      boolean clearsTop = (started.getFlags() & Intent.FLAG_ACTIVITY_CLEAR_TOP) != 0;
      boolean targetsCard =
          started.getComponent() != null
              && StashNativeCardPortraitActivity.class
                  .getName()
                  .equals(started.getComponent().getClassName());
      assertFalse(clearsTop && targetsCard);
    }
  }

  @Test
  public void resetStopsKeepAliveUnderAKeepOpenBrowser() {
    Application app = host.getApplication();
    sdk.setKeepAliveEnabled(true);
    checkout.onResume();
    keepOpen();
    Intent launched = Shadows.shadowOf(app).getNextStartedService();
    assertNotNull(launched);
    // The service enters the foreground first; a stop before that is deferred to the service.
    ServiceController<StashKeepAliveService> service =
        Robolectric.buildService(StashKeepAliveService.class, launched).create().startCommand(0, 1);
    try {
      checkout.onPause();
      sdk.resetPresentationState();
      ShadowLooper.idleMainLooper();
      Intent stopped = Shadows.shadowOf(app).getNextStoppedService();
      assertNotNull(stopped);
      assertEquals(StashKeepAliveService.class.getName(), stopped.getComponent().getClassName());
    } finally {
      service.destroy();
    }
  }

  @Test
  public void returnToKeepOpenCardNeedsAPresentedCardCoveredByAKeepOpenBrowser() {
    plugin.clearPortraitActivity(checkout);
    assertFalse(plugin.returnToKeepOpenCard());
    plugin.setPortraitActivity(checkout);
    assertFalse(plugin.returnToKeepOpenCard());
    assertNull(nextStarted());
    keepOpen();
    assertNotNull(nextStarted());
    assertTrue(plugin.returnToKeepOpenCard());
    assertClearsToTheCard(nextStarted());
    assertFalse(checkout.isFinishing());
    assertTrue(sdk.isCurrentlyPresented());
    // Back on the card, nothing is covering it again.
    checkout.onPause();
    checkout.onResume();
    assertFalse(plugin.returnToKeepOpenCard());
  }

  @Test
  public void popupBridgeAlwaysTakesTheHandoff() {
    new StashPopupJsInterface(plugin).externalBrowser(PAYMENT_URL, true);
    ShadowLooper.idleMainLooper();
    assertEquals(1, externalPayments);
    Intent launched = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(launched);
    assertEquals(Intent.ACTION_VIEW, launched.getAction());
    assertFalse(checkout.externalBrowserOverCard);
    assertFalse(checkout.isFinishing());
    assertNull(nextStarted());
    assertEquals(0, browserClosed);
  }
}
