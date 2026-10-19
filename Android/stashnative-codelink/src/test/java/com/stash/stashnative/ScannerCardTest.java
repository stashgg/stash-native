package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.Manifest;
import android.app.Application;
import android.content.Intent;
import android.view.View;
import android.widget.FrameLayout;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.LooperMode;

/**
 * Card lifecycle with the real module resolved through {@link StashScannerContent#create}.
 * Lives in the core package so it can reach the card's package-private seams.
 */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = {21, 28})
@LooperMode(LooperMode.Mode.PAUSED)
public class ScannerCardTest {
  private StashNativePlugin plugin;
  private RecordingCard activity;

  @Before public void prepare() {
    plugin = StashNativePlugin.getInstance();
    plugin.resetPresentationState();
  }

  @After public void cleanup() {
    if (activity != null) {
      activity.scannerContent.dispose();
      activity.presentation.dispose();
    }
    plugin.setListener(null);
    plugin.resetPresentationState();
  }

  @Test public void moduleResolvesThroughPublicConstructor() {
    prepareScanner();
    assertEquals("com.stash.stashnative.codelink.StashScannerSupport",
        activity.scannerContent.getClass().getName());
    assertNotNull(activity.scannerContent.getView());
  }

  @Test public void connectedLocksUserDismissalAndDeliversOnlyAfterDestruction() {
    prepareScanner();
    activity.completeScan("raw payload");
    activity.completeScan("duplicate");
    activity.requestUserDismiss();
    assertTrue(activity.isInteractionLocked());
    assertFalse(activity.isDismissing);
    idle(500);
    assertFalse(activity.finished);
    assertEquals(0, scanBroadcasts().size());
    idle(800);
    assertTrue(activity.finished);
    assertEquals(0, scanBroadcasts().size());
    activity.onDestroy();
    assertEquals(1, scanBroadcasts().size());
    assertEquals("raw payload", scanBroadcasts().get(0)
        .getStringExtra(CardConstants.BROADCAST_EXTRA_SCANNER_CONTENT));
  }

  @Test public void explicitDismissCancelsConnectedCallback() {
    prepareScanner();
    activity.completeScan("cancelled");
    idle(200);
    activity.dismissWithAnimation();
    idle(1500);
    activity.onDestroy();
    assertEquals(0, scanBroadcasts().size());
    assertTrue(broadcasts().stream().anyMatch(intent ->
        CardConstants.BROADCAST_CHECKOUT_DIALOG_DISMISSED.equals(intent.getAction())));
  }

  @Test public void resetDuringConnectedIsSilent() {
    prepareScanner();
    activity.completeScan("cancelled");
    activity.finishForPluginResetWithoutCallbacks();
    idle(1500);
    activity.onDestroy();
    assertEquals(0, scanBroadcasts().size());
    assertFalse(broadcasts().stream().anyMatch(intent ->
        CardConstants.BROADCAST_CHECKOUT_DIALOG_DISMISSED.equals(intent.getAction())));
  }

  @Test public void backgroundPausesConnectedHold() {
    prepareScanner();
    activity.completeScan("payload");
    idle(200);
    activity.scannerContent.pause();
    idle(3000);
    assertFalse(activity.finished);
    activity.scannerContent.resume();
    idle(200);
    assertFalse(activity.finished);
    idle(1000);
    assertTrue(activity.finished);
  }

  private void prepareScanner() {
    activity = Robolectric.buildActivity(RecordingCard.class).get();
    activity.scanner = true;
    activity.options = StashPresentationOptions.card(null);
    activity.rootLayout = new FrameLayout(activity);
    activity.rootLayout.layout(0, 0, 400, 900);
    activity.backdropView = new View(activity);
    activity.cardContainer = new StashSheetLayout(activity, 28);
    activity.cardContainer.setLayoutParams(new FrameLayout.LayoutParams(400, 560));
    activity.presentation = new StashPresentationController(activity, activity.options);
    activity.scannerContent = StashScannerContent.create(activity);
    assertNotNull(activity.scannerContent);
    activity.cardContainer.addView(activity.scannerContent.getView());
    Shadows.shadowOf((Application) activity.getApplicationContext())
        .denyPermissions(Manifest.permission.CAMERA);
    activity.scannerContent.resume();
    activity.presentation.environmentChanged();
    activity.onEnterAnimationComplete();
    idle(400);
  }

  private List<Intent> broadcasts() {
    return Shadows.shadowOf(RuntimeEnvironment.getApplication()).getBroadcastIntents();
  }

  private List<Intent> scanBroadcasts() {
    List<Intent> matches = new ArrayList<>();
    for (Intent intent : broadcasts()) {
      if (CardConstants.BROADCAST_SCANNER_SCANNED.equals(intent.getAction())) {
        matches.add(intent);
      }
    }
    return matches;
  }

  private static void idle(int milliseconds) {
    Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(Duration.ofMillis(milliseconds));
  }

  public static class RecordingCard extends StashCardActivity {
    boolean finished;

    @Override public void finish() {
      finished = true;
    }
  }
}
