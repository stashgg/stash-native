package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.app.Application;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Looper;
import java.lang.reflect.Method;
import java.time.Duration;
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
import org.robolectric.util.ReflectionHelpers;

/** Live listener delivery routes named callbacks through the existing session guards. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
@LooperMode(LooperMode.Mode.PAUSED)
public class CallbackContractTest {
  private final StashNative sdk = StashNative.getInstance();
  private final StashNativePlugin plugin = StashNativePlugin.getInstance();
  private final List<String> events = new ArrayList<>();
  private Activity host;

  /** Creates a host with a live recording listener. */
  @Before public void prepare() {
    sdk.resetPresentationState();
    sdk.setListener(null);
    host = Robolectric.buildActivity(Activity.class).setup().get();
    sdk.setListener(recordingListener("first"));
  }

  /** Releases presentations and the listener between tests. */
  @After public void cleanup() {
    sdk.resetPresentationState();
    sdk.setListener(null);
    host.finish();
  }

  private StashNative.StashNativeListener recordingListener(String name) {
    return new StashNative.StashNativeListenerAdapter() {
      @Override public void onCardDismissed() {
        events.add(name + ":card-dismissed");
      }

      @Override public void onScannerDismissed() {
        events.add(name + ":scan-dismissed");
      }

      @Override public void onBrowserDismissed() {
        events.add(name + ":browser-dismissed");
      }

      @Override public void onPaymentSuccess(String order) {
        events.add(name + ":payment:" + order);
      }

      @Override public void onScannerError(StashNative.ScannerError error) {
        events.add(name + ":error:" + error);
      }

      @Override public void onQrCodeScanned(String content) {
        events.add(name + ":qr:" + content);
      }
    };
  }

  private StashCardActivity open(boolean scanner) {
    if (scanner) {
      sdk.openScanner(host);
    } else {
      sdk.openCard(host, "https://example.invalid/checkout", null);
    }
    Intent intent = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(intent);
    StashCardActivity checkout =
        Robolectric.buildActivity(StashCardActivity.class, intent).get();
    checkout.options = StashPresentationOptions.card(null);
    checkout.scanner = scanner;
    checkout.cardContainer = new StashSheetLayout(checkout, 24f);
    plugin.setCheckoutActivity(checkout);
    return checkout;
  }

  private void dispatch(StashCardActivity checkout, Intent intent) throws Exception {
    Method method = StashNativePlugin.class.getDeclaredMethod(
        "dispatchCheckoutBridgeIntent", String.class, Intent.class);
    method.setAccessible(true);
    intent.putExtra(StashCheckoutBridge.EXTRA_SESSION_ID, checkout.getPresentationSessionId());
    method.invoke(plugin, intent.getAction(), intent);
  }

  private long launchedBrowser(Activity activity) {
    Intent intent = Shadows.shadowOf(activity).getNextStartedActivity();
    assertNotNull(intent);
    return intent.getLongExtra(StashNativeBrowserProxyActivity.EXTRA_SESSION_ID, 0L);
  }

  @Test public void listenerUsesOneLiveSlotWithoutRegisteringSessionObservers() {
    StashNative.StashNativeListener listener = recordingListener("replacement");
    sdk.setListener(listener);
    assertSame(listener, plugin.getListener());
    plugin.setListener(null);
    assertNull(sdk.getListener());
    assertFalse(ReflectionHelpers.getField(plugin, "checkoutBridgeReceiverRegistered"));
  }

  @Test public void standaloneBrowserAndScannerDeliverDistinctDismissals() throws Exception {
    final StashCardActivity scanner = open(true);
    sdk.openBrowser(host, "https://example.invalid/help");
    final long browser = launchedBrowser(host);
    plugin.notifyBrowserClosedFromProxyInternal(browser);
    assertTrue(sdk.isCurrentlyPresented());
    assertFalse(scanner.isFinishing());
    dispatch(scanner, new Intent(CardConstants.BROADCAST_CHECKOUT_DIALOG_DISMISSED));
    assertEquals(Arrays.asList("first:browser-dismissed", "first:scan-dismissed"), events);
  }

  @Test public void cardDismissalDoesNotChangeCoexistingBrowserCallback() throws Exception {
    StashCardActivity card = open(false);
    sdk.openBrowser(host, "https://example.invalid/help");
    final long browser = launchedBrowser(host);
    dispatch(card, new Intent(CardConstants.BROADCAST_CHECKOUT_DIALOG_DISMISSED));
    open(true);
    plugin.notifyBrowserClosedFromProxyInternal(browser);
    assertEquals(Arrays.asList("first:card-dismissed", "first:browser-dismissed"), events);
    assertTrue(sdk.isCurrentlyPresented());
  }

  @Test public void handoffKeepsItsCallbackAfterScannerAndListenerReplacement() {
    StashCardActivity card = open(false);
    new StashCheckoutJsInterface(card).openExternalBrowser(card.issueBridgeDocumentToken(), "https://example.invalid/pay");
    long browser = launchedBrowser(card);
    final StashCardActivity scanner = open(true);
    sdk.setListener(recordingListener("replacement"));
    plugin.notifyBrowserClosedFromProxyInternal(browser);
    plugin.notifyBrowserEngagementSessionEndedFromProxyInternal(browser);
    Shadows.shadowOf(Looper.getMainLooper()).idle();
    assertEquals(Arrays.asList("replacement:browser-dismissed"), events);
    assertTrue(sdk.isCurrentlyPresented());
    assertFalse(scanner.isFinishing());
  }

  @Test public void reentrantBrowserOpeningDeliversDismissalToEachLiveListener() {
    StashCardActivity card = open(false);
    new StashCheckoutJsInterface(card).openExternalBrowser(card.issueBridgeDocumentToken(), "https://example.invalid/pay");
    long firstBrowser = launchedBrowser(card);
    sdk.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onBrowserDismissed() {
        events.add("original:browser-dismissed");
        sdk.setListener(recordingListener("replacement"));
        sdk.openBrowser(host, "https://example.invalid/next");
      }
    });
    plugin.notifyBrowserClosedFromProxyInternal(firstBrowser);
    long replacement = launchedBrowser(host);
    plugin.notifyBrowserClosedFromProxyInternal(firstBrowser);
    Shadows.shadowOf(Looper.getMainLooper()).idle();
    assertTrue(plugin.isCurrentBrowserSession(replacement));
    plugin.notifyBrowserClosedFromProxyInternal(replacement);
    assertEquals(Arrays.asList(
        "original:browser-dismissed", "replacement:browser-dismissed"), events);
  }

  @Test public void replacementDuringPaymentTakesEffectForNextRepeatableEvent() throws Exception {
    StashCardActivity card = open(false);
    sdk.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onPaymentSuccess(String order) {
        events.add("original:" + order);
        sdk.setListener(recordingListener("replacement"));
      }
    });
    Intent payment = new Intent(CardConstants.BROADCAST_CHECKOUT_PAYMENT_SUCCESS)
        .putExtra(CardConstants.BROADCAST_EXTRA_WILL_CLOSE, false)
        .putExtra(CardConstants.BROADCAST_EXTRA_PAYMENT_ORDER, "order");
    dispatch(card, payment);
    dispatch(card, payment);
    assertEquals(Arrays.asList("original:order", "replacement:payment:order"), events);
    assertTrue(sdk.isCurrentlyPresented());
  }

  @Test public void clearingDropsEventsWithoutReplayAndResetRetainsListener() throws Exception {
    StashCardActivity card = open(false);
    sdk.setListener(null);
    dispatch(card, new Intent(CardConstants.BROADCAST_CHECKOUT_DIALOG_DISMISSED));
    StashNative.StashNativeListener replacement = recordingListener("replacement");
    sdk.setListener(replacement);
    assertTrue(events.isEmpty());
    final StashCardActivity scanner = open(true);
    sdk.openBrowser(host, "https://example.invalid/help");
    final long browser = launchedBrowser(host);
    sdk.resetPresentationState();
    assertSame(replacement, sdk.getListener());
    dispatch(scanner, new Intent(CardConstants.BROADCAST_SCANNER_SCANNED)
        .putExtra(CardConstants.BROADCAST_EXTRA_SCANNER_CONTENT, "stale"));
    plugin.notifyBrowserClosedFromProxyInternal(browser);
    assertTrue(events.isEmpty());
    StashCardActivity next = open(true);
    dispatch(next, new Intent(CardConstants.BROADCAST_CHECKOUT_DIALOG_DISMISSED));
    assertEquals(Arrays.asList("replacement:scan-dismissed"), events);
  }

  @Test public void scannerCameraConfigurationErrorIsNonterminal() throws Exception {
    final StashCardActivity scanner = open(true);
    dispatch(scanner, new Intent(CardConstants.BROADCAST_SCANNER_ERROR)
        .putExtra(CardConstants.BROADCAST_EXTRA_SCANNER_ERROR, "CAMERA_CONFIGURATION_FAILED"));
    assertTrue(sdk.isCurrentlyPresented());
    dispatch(scanner, new Intent(CardConstants.BROADCAST_SCANNER_SCANNED)
        .putExtra(CardConstants.BROADCAST_EXTRA_SCANNER_CONTENT, "payload"));
    dispatch(scanner, new Intent(CardConstants.BROADCAST_CHECKOUT_DIALOG_DISMISSED));
    assertEquals(Arrays.asList(
        "first:error:CAMERA_CONFIGURATION_FAILED", "first:qr:payload"), events);
    assertFalse(sdk.isCurrentlyPresented());
  }

  @Test public void reentrantScannerDismissalCanOpenCardWithoutStaleDismissal() throws Exception {
    final StashCardActivity scanner = open(true);
    sdk.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onScannerDismissed() {
        events.add("original:scan-dismissed");
        sdk.setListener(recordingListener("replacement"));
        open(false);
      }
    });
    dispatch(scanner, new Intent(CardConstants.BROADCAST_CHECKOUT_DIALOG_DISMISSED));
    dispatch(scanner, new Intent(CardConstants.BROADCAST_CHECKOUT_DIALOG_DISMISSED));
    assertEquals(Arrays.asList("original:scan-dismissed"), events);
    assertTrue(sdk.isCurrentlyPresented());
  }

  @Test public void delayedFallbackCloseCannotCloseReplacement() throws Exception {
    open(true);
    Method begin = StashNativePlugin.class.getDeclaredMethod(
        "beginBrowserCloseTrackingAfterExternalUrlLaunched");
    Method schedule = StashNativePlugin.class.getDeclaredMethod("scheduleBrowserClosedDebounce");
    begin.setAccessible(true);
    schedule.setAccessible(true);
    begin.invoke(plugin);
    Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(400));
    schedule.invoke(plugin);
    Runnable stale = ReflectionHelpers.getField(plugin, "browserClosedDebounceRunnable");
    begin.invoke(plugin);
    stale.run();
    assertTrue(events.isEmpty());
    Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(400));
    schedule.invoke(plugin);
    Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(500));
    assertEquals(Arrays.asList("first:browser-dismissed"), events);
    assertTrue(sdk.isCurrentlyPresented());
  }

  @Test
  @Config(shadows = ActionViewLauncher.class)
  public void fallbackHandoffDismissesOnceToReplacementListener() {
    StashCardActivity card = open(false);
    new StashCheckoutJsInterface(card).openExternalBrowser(card.issueBridgeDocumentToken(), "https://example.invalid/pay");
    Intent launched = Shadows.shadowOf(card).getNextStartedActivity();
    assertNotNull(launched);
    assertEquals(Intent.ACTION_VIEW, launched.getAction());
    Application.ActivityLifecycleCallbacks lifecycle =
        ReflectionHelpers.getField(plugin, "checkoutHostLifecycleCallbacks");
    lifecycle.onActivityPaused(host);
    sdk.setListener(recordingListener("replacement"));
    lifecycle.onActivityResumed(host);
    Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(499));
    assertTrue(events.isEmpty());
    Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(1));
    lifecycle.onActivityResumed(host);
    Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(500));
    assertEquals(Arrays.asList("replacement:browser-dismissed"), events);
    assertTrue(card.isFinishing());
    assertFalse(sdk.isCurrentlyPresented());
  }

  /**
   * Framework order for a translucent checkout over the host when an opaque browser comes and
   * goes: the host was paused at open; the browser pauses the card and stops the host; closing
   * it starts the host (still paused under the card) and resumes only the card.
   */
  @Test
  @Config(shadows = ActionViewLauncher.class)
  public void fallbackHandoffCompletesWhenOnlyTheCheckoutResumes() {
    StashCardActivity card = open(false);
    new StashCheckoutJsInterface(card).openExternalBrowser(
        card.issueBridgeDocumentToken(), "https://example.invalid/pay");
    Shadows.shadowOf(Looper.getMainLooper()).idle();
    Intent launched = Shadows.shadowOf(card).getNextStartedActivity();
    assertNotNull(launched);
    assertEquals(Intent.ACTION_VIEW, launched.getAction());
    Application.ActivityLifecycleCallbacks lifecycle =
        ReflectionHelpers.getField(plugin, "checkoutHostLifecycleCallbacks");
    lifecycle.onActivityPaused(card);
    lifecycle.onActivityStopped(host);
    Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(1000));
    assertTrue(events.isEmpty());
    lifecycle.onActivityStarted(host);
    lifecycle.onActivityResumed(card);
    Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(499));
    assertTrue(events.isEmpty());
    Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(501));
    assertEquals(Arrays.asList("first:browser-dismissed"), events);
    assertTrue(card.isFinishing());
    assertFalse(sdk.isCurrentlyPresented());
  }

  /** Without a pending handoff the checkout's own lifecycle never stands in for the host. */
  @Test
  @Config(shadows = ActionViewLauncher.class)
  public void checkoutLifecycleIsIgnoredWithoutAPendingHandoff() {
    StashCardActivity card = open(false);
    sdk.openBrowser(host, "https://example.invalid/help");
    Shadows.shadowOf(Looper.getMainLooper()).idle();
    Intent launched = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(launched);
    assertEquals(Intent.ACTION_VIEW, launched.getAction());
    Application.ActivityLifecycleCallbacks lifecycle =
        ReflectionHelpers.getField(plugin, "checkoutHostLifecycleCallbacks");
    lifecycle.onActivityPaused(card);
    lifecycle.onActivityResumed(card);
    Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(1000));
    assertTrue(events.isEmpty());
    assertFalse(card.isFinishing());
    lifecycle.onActivityPaused(host);
    lifecycle.onActivityResumed(host);
    Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(500));
    assertEquals(Arrays.asList("first:browser-dismissed"), events);
    assertFalse(card.isFinishing());
    assertTrue(sdk.isCurrentlyPresented());
  }

  /** Selects the browser fallback without requiring a second test dependency graph. */
  @Implements(value = StashUrlLauncher.class, isInAndroidSdk = false)
  public static class ActionViewLauncher {
    @Implementation public static boolean isCustomTabsClassAvailable() {
      return false;
    }

    @Implementation public static int openExternalUrl(Context context, String url) {
      context.startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
      return StashUrlLauncher.OPEN_EXTERNAL_ACTION_VIEW;
    }
  }
}
