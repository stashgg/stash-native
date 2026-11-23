package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.pm.ResolveInfo;
import android.content.pm.ServiceInfo;
import android.net.Uri;
import android.view.View;
import androidx.browser.customtabs.CustomTabsService;
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
import org.robolectric.shadows.ShadowPackageManager;

/** Browser handoffs must keep the originating checkout's lifetime across host callbacks. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
@LooperMode(LooperMode.Mode.PAUSED)
public class BrowserLifetimeTest {
  private final StashNative sdk = StashNative.getInstance();
  private final StashNativePlugin plugin = StashNativePlugin.getInstance();
  private static final String PROVIDER = "com.example.browser";
  private Activity host;
  private StashCardActivity checkout;
  private int externalPayments;
  private int browserClosed;
  private String token;

  @Before public void prepare() {
    sdk.resetPresentationState();
    StashKeepAliveService.resetStartTrackingForTests();
    host = Robolectric.buildActivity(Activity.class).setup().get();
    setProviderAvailable(true);
    checkout = openCheckout();
    sdk.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onExternalPayment(String url) { externalPayments++; }
      @Override public void onBrowserDismissed() { browserClosed++; }
    });
  }

  @After public void cleanup() {
    sdk.resetPresentationState();
    sdk.setListener(null);
  }

  /** Makes the default browser offer a Custom Tabs service, or takes it away. */
  private void setProviderAvailable(boolean available) {
    ShadowPackageManager packages = Shadows.shadowOf(host.getPackageManager());
    Intent view = new Intent(Intent.ACTION_VIEW, Uri.parse("http://"));
    Intent service =
        new Intent(CustomTabsService.ACTION_CUSTOM_TABS_CONNECTION).setPackage(PROVIDER);
    if (!available) {
      packages.removeResolveInfosForIntent(view, PROVIDER);
      packages.removeResolveInfosForIntent(service, PROVIDER);
      return;
    }
    ResolveInfo activity = new ResolveInfo();
    activity.activityInfo = new ActivityInfo();
    activity.activityInfo.packageName = PROVIDER;
    activity.activityInfo.name = "BrowserActivity";
    packages.addResolveInfoForIntent(view, activity);
    ResolveInfo tabs = new ResolveInfo();
    tabs.serviceInfo = new ServiceInfo();
    tabs.serviceInfo.packageName = PROVIDER;
    tabs.serviceInfo.name = "TabsService";
    packages.addResolveInfoForIntent(service, tabs);
  }

  private StashCardActivity openCheckout() {
    sdk.openCard(host, "https://example.invalid/checkout", null);
    Intent intent = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(intent);
    StashCardActivity result = Robolectric.buildActivity(StashCardActivity.class, intent).get();
    StashNative.CardConfig config = new StashNative.CardConfig();
    config.allowBrowserOverCard = true;
    result.options = StashPresentationOptions.card(config);
    result.cardContainer = new StashSheetLayout(result, 24f);
    plugin.setCheckoutActivity(result);
    token = result.issueBridgeDocumentToken();
    return result;
  }

  private void handoff() {
    new StashCheckoutJsInterface(checkout).openExternalBrowser(token, "https://example.invalid/payment");
  }

  @Test public void queuedSignalFromResetCheckoutCannotRetireReplacement() throws Exception {
    Thread js = new Thread(this::handoff);
    js.start();
    js.join();
    sdk.resetPresentationState();
    StashCardActivity replacement = openCheckout();
    ShadowLooper.idleMainLooper();
    assertEquals(0, externalPayments);
    assertTrue(sdk.isCurrentlyPresented());
    assertEquals(replacement.getPresentationSessionId(), plugin.presentationSessionId);
    assertNull(Shadows.shadowOf(checkout).getNextStartedActivity());
  }

  @Test public void resetInsideExternalPaymentCallbackCancelsLaunch() {
    sdk.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onExternalPayment(String url) { sdk.resetPresentationState(); }
    });
    handoff();
    ShadowLooper.idleMainLooper();
    assertNull(Shadows.shadowOf(checkout).getNextStartedActivity());
    assertEquals(View.VISIBLE, checkout.cardContainer.getVisibility());
  }

  @Test public void replacementInsideExternalPaymentCallbackRetiresOldCheckoutAndCancelsLaunch() {
    sdk.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onExternalPayment(String url) { openCheckout(); }
    });
    handoff();
    ShadowLooper.idleMainLooper();
    assertNull(Shadows.shadowOf(checkout).getNextStartedActivity());
    assertTrue(sdk.isCurrentlyPresented());
    assertTrue(checkout.isFinishing());
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

  @Test public void replacementBeforeQueuedHideRetiresOldCheckout() {
    handoff();
    openCheckout();
    ShadowLooper.idleMainLooper();
    assertTrue(checkout.isFinishing());
    assertTrue(sdk.isCurrentlyPresented());
  }

  @Test public void replacementInsideBrowserClosedCallbackRetiresOldCheckout() {
    handoff();
    sdk.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onBrowserDismissed() { openCheckout(); }
    });
    long sessionId = Shadows.shadowOf(checkout).getNextStartedActivity()
        .getLongExtra(StashNativeBrowserProxyActivity.EXTRA_SESSION_ID, 0L);
    plugin.notifyBrowserClosedFromProxyInternal(sessionId);
    ShadowLooper.idleMainLooper();
    assertTrue(checkout.isFinishing());
    assertTrue(sdk.isCurrentlyPresented());
  }

  @Test public void queuedLinkCannotLaunchAfterResetOrRetireReplacement() throws Exception {
    Thread js = new Thread(() -> new StashCheckoutJsInterface(checkout)
        .openLink(token, "https://example.invalid/terms"));
    js.start();
    js.join();
    sdk.resetPresentationState();
    assertTrue(checkout.isFinishing());
    StashCardActivity replacement = openCheckout();
    ShadowLooper.idleMainLooper();
    assertNull(Shadows.shadowOf(checkout).getNextStartedActivity());
    assertFalse(replacement.isFinishing());
    assertTrue(sdk.isCurrentlyPresented());
    assertEquals(0, externalPayments);
    assertEquals(0, browserClosed);
  }

  @Test public void keepOpenBrowserOpensOverTheCardAndEndsNothing() {
    new StashCheckoutJsInterface(checkout)
        .externalBrowser(token, "https://example.invalid/payment", true);
    ShadowLooper.idleMainLooper();
    assertEquals(1, externalPayments);
    Intent launched = Shadows.shadowOf(checkout).getNextStartedActivity();
    assertNotNull(launched);
    assertTrue(launched.getDataString().startsWith("https://example.invalid/payment"));
    assertNull(launched.getComponent());
    assertEquals(PROVIDER, launched.getPackage());
    assertEquals(0, launched.getFlags() & Intent.FLAG_ACTIVITY_NEW_TASK);
    assertTrue(checkout.externalBrowserOverCard);
    assertEquals(View.VISIBLE, checkout.cardContainer.getVisibility());
    assertFalse(checkout.isFinishing());
    assertFalse(checkout.callbackSent);
    assertTrue(sdk.isCurrentlyPresented());
    assertEquals(0, browserClosed);
  }

  private void keepOpen() {
    new StashCheckoutJsInterface(checkout)
        .externalBrowser(token, "https://example.invalid/payment", true);
  }

  @Test public void repeatedKeepOpenCallsOpenOneBrowserAndReportOnce() {
    keepOpen();
    keepOpen();
    ShadowLooper.idleMainLooper();
    assertEquals(1, externalPayments);
    assertNotNull(Shadows.shadowOf(checkout).getNextStartedActivity());
    assertNull(Shadows.shadowOf(checkout).getNextStartedActivity());
    // A call while the card sits paused beneath the browser is still a repeat.
    checkout.onPause();
    keepOpen();
    ShadowLooper.idleMainLooper();
    assertEquals(1, externalPayments);
    assertNull(Shadows.shadowOf(checkout).getNextStartedActivity());
    // Back on the card, the page may open the browser again.
    checkout.onResume();
    keepOpen();
    ShadowLooper.idleMainLooper();
    assertEquals(2, externalPayments);
    assertNotNull(Shadows.shadowOf(checkout).getNextStartedActivity());
    assertTrue(sdk.isCurrentlyPresented());
    assertEquals(0, browserClosed);
  }

  @Test public void keepOpenWhoseTabCannotStartTakesTheHandoff() {
    android.app.Application app = host.getApplication();
    Shadows.shadowOf(app).checkActivities(true);
    try {
      keepOpen();
      ShadowLooper.idleMainLooper();
      assertEquals(1, externalPayments);
      assertFalse(checkout.externalBrowserOverCard);
      Intent launched = Shadows.shadowOf(checkout).getNextStartedActivity();
      assertNotNull(launched);
      assertEquals(StashNativeBrowserProxyActivity.class.getName(),
          launched.getComponent().getClassName());
      assertFalse(sdk.isCurrentlyPresented());
      assertEquals(0, browserClosed);
      plugin.notifyBrowserClosedFromProxyInternal(
          launched.getLongExtra(StashNativeBrowserProxyActivity.EXTRA_SESSION_ID, 0L));
      ShadowLooper.idleMainLooper();
      assertEquals(1, externalPayments);
      assertEquals(1, browserClosed);
    } finally {
      Shadows.shadowOf(app).checkActivities(false);
    }
  }

  @Test public void keepOpenWithNoCustomTabsProviderTakesTheHandoff() {
    setProviderAvailable(false);
    keepOpen();
    keepOpen();
    ShadowLooper.idleMainLooper();
    assertEquals(1, externalPayments);
    assertFalse(checkout.externalBrowserOverCard);
    Intent launched = Shadows.shadowOf(checkout).getNextStartedActivity();
    assertNotNull(launched);
    assertEquals(StashNativeBrowserProxyActivity.class.getName(),
        launched.getComponent().getClassName());
    assertNull(Shadows.shadowOf(checkout).getNextStartedActivity());
    long sessionId = launched.getLongExtra(StashNativeBrowserProxyActivity.EXTRA_SESSION_ID, 0L);
    assertEquals(View.INVISIBLE, checkout.cardContainer.getVisibility());
    assertFalse(sdk.isCurrentlyPresented());
    assertEquals(0, browserClosed);
    plugin.notifyBrowserClosedFromProxyInternal(sessionId);
    ShadowLooper.idleMainLooper();
    assertEquals(1, externalPayments);
    assertEquals(1, browserClosed);
    assertTrue(checkout.isFinishing());
  }

  @Test public void keepOpenWithKeepAliveStartsItOnlyAfterATabOpens() {
    android.app.Application app = host.getApplication();
    sdk.setKeepAliveEnabled(true);
    try {
      keepOpen();
      ShadowLooper.idleMainLooper();
      assertTrue(checkout.externalBrowserOverCard);
      assertNotNull(Shadows.shadowOf(app).getNextStartedService());
      // Back on the card after that browser, the request re-arms.
      checkout.onPause();
      checkout.onResume();
      assertFalse(checkout.externalBrowserOverCard);
      keepOpen();
      ShadowLooper.idleMainLooper();
      assertEquals(2, externalPayments);
      assertTrue(sdk.isCurrentlyPresented());
    } finally {
      sdk.setKeepAliveEnabled(false);
    }
  }

  @Test public void hostActivityStartedAndCardDismissedFromTheCallbackSurvives() {
    sdk.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onExternalPayment(String url) {
        externalPayments++;
        host.startActivity(new Intent(host, Activity.class));
        sdk.dismiss();
      }
    });
    keepOpen();
    ShadowLooper.idleMainLooper();
    assertEquals(1, externalPayments);
    assertFalse(checkout.externalBrowserOverCard);
    // Only the host's own start was issued: no browser, and no clear-top start from the card.
    Intent started = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(started);
    assertNull(started.getPackage());
    assertNull(Shadows.shadowOf(host).getNextStartedActivity());
    assertTrue(checkout.isFinishing());
  }

  @Test public void publicLauncherStillReportsTheSystemBrowserWhenNothingOpens() {
    Shadows.shadowOf(host.getApplication()).checkActivities(true);
    try {
      assertEquals(StashUrlLauncher.OPEN_EXTERNAL_ACTION_VIEW,
          StashUrlLauncher.openExternalUrl(host, "https://example.invalid/pay", 0));
      assertEquals(StashUrlLauncher.OPEN_EXTERNAL_NONE,
          StashUrlLauncher.launchExternalUrl(host, "https://example.invalid/pay", 0));
      assertEquals(StashUrlLauncher.OPEN_EXTERNAL_ACTION_VIEW,
          StashUrlLauncher.openExternalUrl(host, "ftp://example.invalid/pay", 0));
      assertEquals(StashUrlLauncher.OPEN_EXTERNAL_NONE,
          StashUrlLauncher.launchExternalUrl(host, "ftp://example.invalid/pay", 0));
      // A link with no handler neither crashes nor ends the card.
      new StashCheckoutJsInterface(checkout).openLink(token, "https://example.invalid/terms");
      ShadowLooper.idleMainLooper();
      assertFalse(checkout.isFinishing());
      assertTrue(sdk.isCurrentlyPresented());
    } finally {
      Shadows.shadowOf(host.getApplication()).checkActivities(false);
    }
  }

  /** Covers the card with a keepOpen browser, ends the card, and expects the browser closed. */
  private void assertEndingTheCardClosesItsBrowser(Runnable end) {
    checkout.onResume();
    keepOpen();
    ShadowLooper.idleMainLooper();
    assertNotNull(Shadows.shadowOf(checkout).getNextStartedActivity());
    checkout.onPause();
    end.run();
    ShadowLooper.idleMainLooper();
    Intent back = Shadows.shadowOf(checkout).getNextStartedActivity();
    assertNotNull(back);
    assertEquals(StashCardActivity.class.getName(), back.getComponent().getClassName());
    int expected = Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP;
    assertEquals(expected, back.getFlags() & expected);
    assertTrue(checkout.isFinishing());
    assertFalse(checkout.externalBrowserOverCard);
  }

  @Test public void paymentResultClosesTheKeepOpenBrowserWithTheCard() {
    assertEndingTheCardClosesItsBrowser(
        () -> new StashCheckoutJsInterface(checkout).onPaymentSuccess(token, "{}"));
  }

  @Test public void pageCloseClosesTheKeepOpenBrowserWithTheCard() {
    assertEndingTheCardClosesItsBrowser(
        () -> new StashCheckoutJsInterface(checkout).requestCloseFromPage(token));
  }

  @Test public void networkErrorClosesTheKeepOpenBrowserWithTheCard() {
    assertEndingTheCardClosesItsBrowser(checkout::handleNetworkError);
  }

  @Test public void hostDismissClosesTheKeepOpenBrowserWithTheCard() {
    assertEndingTheCardClosesItsBrowser(sdk::dismiss);
  }

  @Test public void resetClosesTheKeepOpenBrowserWithTheCard() {
    assertEndingTheCardClosesItsBrowser(sdk::resetPresentationState);
  }

  @Test public void endingAnUncoveredCardStartsNothing() {
    new StashCheckoutJsInterface(checkout).requestCloseFromPage(token);
    ShadowLooper.idleMainLooper();
    assertNull(Shadows.shadowOf(checkout).getNextStartedActivity());
  }

  @Test public void closeBrowserReturnsToTheCardOnlyWhileAKeepOpenBrowserIsOverIt() {
    // Without a keepOpen browser there is nothing the SDK can close.
    sdk.closeBrowser();
    ShadowLooper.idleMainLooper();
    assertNull(Shadows.shadowOf(checkout).getNextStartedActivity());
    keepOpen();
    ShadowLooper.idleMainLooper();
    assertNotNull(Shadows.shadowOf(checkout).getNextStartedActivity());
    checkout.onPause();
    sdk.closeBrowser();
    ShadowLooper.idleMainLooper();
    Intent back = Shadows.shadowOf(checkout).getNextStartedActivity();
    assertNotNull(back);
    assertEquals(StashCardActivity.class.getName(), back.getComponent().getClassName());
    int expected = Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP;
    assertEquals(expected, back.getFlags() & expected);
    assertFalse(checkout.isFinishing());
    assertTrue(sdk.isCurrentlyPresented());
    assertEquals(0, browserClosed);
    // Back on the card, the flag clears and closeBrowser has no effect again.
    checkout.onResume();
    sdk.closeBrowser();
    ShadowLooper.idleMainLooper();
    assertNull(Shadows.shadowOf(checkout).getNextStartedActivity());
  }

  @Test public void hostBrowserFromKeepOpenCallbackReplacesTheSdkLaunch() {
    sdk.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onExternalPayment(String url) {
        externalPayments++;
        sdk.openBrowser(host, "https://example.invalid/host");
      }
    });
    keepOpen();
    keepOpen();
    ShadowLooper.idleMainLooper();
    assertEquals(1, externalPayments);
    assertNotNull(Shadows.shadowOf(host).getNextStartedActivity());
    assertNull(Shadows.shadowOf(host).getNextStartedActivity());
    assertNull(Shadows.shadowOf(checkout).getNextStartedActivity());
    assertFalse(checkout.isFinishing());
    assertTrue(sdk.isCurrentlyPresented());
  }

  @Test public void externalBrowserWithoutKeepOpenIsTheCardClosingHandoff() {
    new StashCheckoutJsInterface(checkout)
        .externalBrowser(token, "https://example.invalid/payment", false);
    ShadowLooper.idleMainLooper();
    assertEquals(1, externalPayments);
    Intent launched = Shadows.shadowOf(checkout).getNextStartedActivity();
    assertNotNull(launched);
    assertEquals(StashNativeBrowserProxyActivity.class.getName(),
        launched.getComponent().getClassName());
    assertEquals(View.INVISIBLE, checkout.cardContainer.getVisibility());
    assertFalse(sdk.isCurrentlyPresented());
  }

  @Test public void keepOpenOnADefaultCardTakesTheHandoff() {
    checkout.options = StashPresentationOptions.card(null);
    keepOpen();
    keepOpen();
    ShadowLooper.idleMainLooper();
    assertEquals(1, externalPayments);
    assertFalse(checkout.externalBrowserOverCard);
    Intent launched = Shadows.shadowOf(checkout).getNextStartedActivity();
    assertNotNull(launched);
    assertEquals(StashNativeBrowserProxyActivity.class.getName(),
        launched.getComponent().getClassName());
    long sessionId = launched.getLongExtra(StashNativeBrowserProxyActivity.EXTRA_SESSION_ID, 0L);
    assertEquals(View.INVISIBLE, checkout.cardContainer.getVisibility());
    assertFalse(sdk.isCurrentlyPresented());
    assertEquals(0, browserClosed);
    plugin.notifyBrowserClosedFromProxyInternal(sessionId);
    ShadowLooper.idleMainLooper();
    assertEquals(1, browserClosed);
    assertTrue(checkout.isFinishing());
  }

  @Test public void activeLinkLaunchesWithoutCallbacksThemeOrDismissal() {
    new StashCheckoutJsInterface(checkout).openLink(token, "https://example.invalid/terms");
    ShadowLooper.idleMainLooper();
    Intent launched = Shadows.shadowOf(checkout).getNextStartedActivity();
    assertNotNull(launched);
    assertEquals("https://example.invalid/terms", launched.getDataString());
    assertFalse(checkout.isFinishing());
    assertTrue(sdk.isCurrentlyPresented());
    assertEquals(0, externalPayments);
    assertEquals(0, browserClosed);
  }

  @Test public void queuedLinkCannotLaunchAfterBrowserHandoff() throws Exception {
    Thread js = new Thread(() -> new StashCheckoutJsInterface(checkout)
        .openLink(token, "https://example.invalid/terms"));
    js.start();
    js.join();
    handoff();
    assertNotNull(Shadows.shadowOf(checkout).getNextStartedActivity());
    ShadowLooper.idleMainLooper();
    assertNull(Shadows.shadowOf(checkout).getNextStartedActivity());
    assertFalse(sdk.isCurrentlyPresented());
    assertEquals(1, externalPayments);
    assertEquals(0, browserClosed);
  }

  @Test public void browserOpenedFromExternalPaymentCallbackRetiresPreviousCheckout() {
    sdk.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onExternalPayment(String url) {
        sdk.openBrowser(host, "https://example.invalid/next");
      }
    });
    handoff();
    ShadowLooper.idleMainLooper();
    Intent launched = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(launched);
    long browser = launched.getLongExtra(StashNativeBrowserProxyActivity.EXTRA_SESSION_ID, 0L);
    assertTrue(checkout.isFinishing());
    assertTrue(plugin.isCurrentBrowserSession(browser));
    assertNull(Shadows.shadowOf(checkout).getNextStartedActivity());
  }

  @Test public void ordinaryOpenBrowserDoesNotRetireAnActiveCard() {
    sdk.openBrowser(host, "https://example.invalid/terms");
    assertNotNull(Shadows.shadowOf(host).getNextStartedActivity());
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

  /** A tab that closes without a result is detected on the proxy's second resume, once. */
  @Test public void proxyFinishedFromOutsideReportsOneClose() {
    handoff();
    Intent intent = Shadows.shadowOf(checkout).getNextStartedActivity();
    assertNotNull(intent);
    org.robolectric.android.controller.ActivityController<StashNativeBrowserProxyActivity> proxy =
        Robolectric.buildActivity(StashNativeBrowserProxyActivity.class, intent)
            .create().start().resume();
    ShadowLooper.idleMainLooper();
    assertEquals(0, browserClosed);
    // Clear-top from the keep-alive notification finishes the proxy without a result.
    proxy.get().finish();
    proxy.pause().stop().destroy();
    ShadowLooper.idleMainLooper();
    assertEquals(1, browserClosed);
    assertTrue(checkout.isFinishing());
  }

  @Test public void proxyDestroyedAfterItsResultDoesNotReportTwice() {
    handoff();
    Intent intent = Shadows.shadowOf(checkout).getNextStartedActivity();
    org.robolectric.android.controller.ActivityController<StashNativeBrowserProxyActivity> proxy =
        Robolectric.buildActivity(StashNativeBrowserProxyActivity.class, intent)
            .create().start().resume();
    ShadowLooper.idleMainLooper();
    proxy.get().onActivityResult(
        CardConstants.REQUEST_CODE_STASH_CUSTOM_TAB, Activity.RESULT_CANCELED, null);
    proxy.pause().stop().destroy();
    ShadowLooper.idleMainLooper();
    assertEquals(1, browserClosed);
  }

  @Test public void proxyResumeFallbackReportsOneCloseForTheCurrentSession() {
    handoff();
    Intent intent = Shadows.shadowOf(checkout).getNextStartedActivity();
    assertNotNull(intent);
    org.robolectric.android.controller.ActivityController<StashNativeBrowserProxyActivity> proxy =
        Robolectric.buildActivity(StashNativeBrowserProxyActivity.class, intent)
            .create().start().resume();
    ShadowLooper.idleMainLooper();
    assertNotNull(Shadows.shadowOf(proxy.get()).getNextStartedActivityForResult());
    assertEquals(0, browserClosed);
    assertFalse(proxy.get().isFinishing());
    assertFalse(checkout.isFinishing());
    proxy.pause().resume();
    ShadowLooper.idleMainLooper();
    assertEquals(1, browserClosed);
    assertTrue(proxy.get().isFinishing());
    assertTrue(checkout.isFinishing());
    proxy.pause().resume();
    proxy.get().onActivityResult(
        CardConstants.REQUEST_CODE_STASH_CUSTOM_TAB, Activity.RESULT_CANCELED, null);
    ShadowLooper.idleMainLooper();
    assertEquals(1, browserClosed);
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
    sdk.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onBrowserDismissed() {
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
