package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.app.Application;
import android.app.Notification;
import android.content.ComponentName;
import android.content.Intent;
import android.content.IntentFilter;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Shadows;
import org.robolectric.android.controller.ServiceController;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.LooperMode;
import org.robolectric.shadows.ShadowLooper;
import org.robolectric.shadows.ShadowPackageManager;

/** The keep-alive notification and reset must not end, or outlive, the presentation. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = {28, 34})
@LooperMode(LooperMode.Mode.PAUSED)
public class KeepAliveLifetimeTest {
  private static final int CLEARING = Intent.FLAG_ACTIVITY_CLEAR_TOP
      | Intent.FLAG_ACTIVITY_CLEAR_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT;

  private final StashNative sdk = StashNative.getInstance();
  private final StashNativePlugin plugin = StashNativePlugin.getInstance();
  private Application app;
  private Activity host;
  private ComponentName launcher;
  private int dismissed;

  @Before public void prepare() {
    sdk.resetPresentationState();
    app = RuntimeEnvironment.getApplication();
    launcher = new ComponentName(app, "com.example.GameActivity");
    ShadowPackageManager pm = Shadows.shadowOf(app.getPackageManager());
    pm.addActivityIfNotPresent(launcher);
    IntentFilter filter = new IntentFilter(Intent.ACTION_MAIN);
    filter.addCategory(Intent.CATEGORY_LAUNCHER);
    pm.addIntentFilterForActivity(launcher, filter);
    host = Robolectric.buildActivity(Activity.class).setup().get();
    sdk.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onCardDismissed() { dismissed++; }
    });
  }

  @After public void cleanup() {
    sdk.setKeepAliveEnabled(false);
    sdk.resetPresentationState();
    sdk.setListener(null);
  }

  private RecordingCard openCard() {
    sdk.openCard(host, "https://example.invalid/checkout", null);
    Intent intent = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(intent);
    RecordingCard card = Robolectric.buildActivity(RecordingCard.class, intent).get();
    card.options = StashPresentationOptions.card(null);
    plugin.setCheckoutActivity(card);
    return card;
  }

  /** What the notification starts: a plain new-task start that cannot clear the host task. */
  @Test public void notificationStartsTheReturnActivityWithoutClearingFlags() {
    ServiceController<StashKeepAliveService> service = Robolectric.buildService(
        StashKeepAliveService.class, new Intent(app, StashKeepAliveService.class))
        .create().startCommand(0, 1);
    try {
      Notification notification =
          Shadows.shadowOf(service.get()).getLastForegroundNotification();
      Intent tap = Shadows.shadowOf(notification.contentIntent).getSavedIntent();
      assertEquals(StashKeepAliveReturnActivity.class.getName(),
          tap.getComponent().getClassName());
      assertTrue((tap.getFlags() & Intent.FLAG_ACTIVITY_NEW_TASK) != 0);
      assertEquals(0, tap.getFlags() & CLEARING);
    } finally {
      service.destroy();
    }
  }

  @Test public void tapWithACardOpenReturnsToThatCardWithoutDismissingIt() {
    RecordingCard card = openCard();
    StashKeepAliveReturnActivity tap =
        Robolectric.buildActivity(StashKeepAliveReturnActivity.class).create().get();
    ShadowLooper.idleMainLooper();
    assertTrue(tap.isFinishing());
    // Started from the card, so it resolves in the card's task; only what lies above it clears.
    Intent back = card.started;
    assertNotNull(back);
    assertEquals(back, Shadows.shadowOf(tap).getNextStartedActivity());
    assertNull(Shadows.shadowOf(tap).getNextStartedActivity());
    assertEquals(StashCardActivity.class.getName(), back.getComponent().getClassName());
    int expected = Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP;
    assertEquals(expected, back.getFlags() & expected);
    assertEquals(0, back.getFlags() & Intent.FLAG_ACTIVITY_NEW_TASK);
    assertFalse(card.isFinishing());
    assertTrue(sdk.isCurrentlyPresented());
    assertEquals(0, dismissed);
  }

  @Test public void tapWithoutACardRelaunchesTheApp() {
    StashKeepAliveReturnActivity tap =
        Robolectric.buildActivity(StashKeepAliveReturnActivity.class).create().get();
    assertTrue(tap.isFinishing());
    Intent launch = Shadows.shadowOf(tap).getNextStartedActivity();
    assertNotNull(launch);
    assertEquals(launcher, launch.getComponent());
    int expected = Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP
        | Intent.FLAG_ACTIVITY_SINGLE_TOP;
    assertEquals(expected, launch.getFlags() & expected);
  }

  @Test public void tapAfterTheCardHandedOffRelaunchesTheApp() {
    RecordingCard card = openCard();
    card.cardContainer = new StashSheetLayout(card, 24f);
    new StashCheckoutJsInterface(card)
        .externalBrowser(card.issueBridgeDocumentToken(), "https://example.invalid/pay", false);
    ShadowLooper.idleMainLooper();
    assertFalse(sdk.isCurrentlyPresented());
    while (Shadows.shadowOf(card).getNextStartedActivity() != null) {}
    card.started = null;
    StashKeepAliveReturnActivity tap =
        Robolectric.buildActivity(StashKeepAliveReturnActivity.class).create().get();
    assertNull(card.started);
    assertEquals(launcher, Shadows.shadowOf(tap).getNextStartedActivity().getComponent());
    assertNull(Shadows.shadowOf(tap).getNextStartedActivity());
  }

  @Test public void resetStopsARunningKeepAliveService() {
    sdk.setKeepAliveEnabled(true);
    sdk.openBrowser(host, "https://example.invalid/terms");
    Intent started = Shadows.shadowOf(app).getNextStartedService();
    assertNotNull(started);
    assertEquals(StashKeepAliveService.class.getName(), started.getComponent().getClassName());
    while (Shadows.shadowOf(app).getNextStoppedService() != null) {}
    sdk.resetPresentationState();
    Intent stopped = Shadows.shadowOf(app).getNextStoppedService();
    assertNotNull(stopped);
    assertEquals(StashKeepAliveService.class.getName(), stopped.getComponent().getClassName());
  }

  /** Records starts made with the card as their source. */
  public static class RecordingCard extends StashCardActivity {
    Intent started;

    @Override public void startActivity(Intent intent) {
      started = intent;
      super.startActivity(intent);
    }
  }
}
