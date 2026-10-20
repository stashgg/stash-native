package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.os.Parcel;
import android.view.View;
import java.lang.reflect.Method;
import java.time.Duration;
import java.util.ArrayList;
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
import org.robolectric.annotation.Implementation;
import org.robolectric.annotation.Implements;
import org.robolectric.annotation.LooperMode;

/**
 * Scanner admission, configuration transport, and callback routing in the core. The core test
 * classpath has no stashnative-codelink module; camera and view behavior is tested there.
 */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = {21, 28})
@LooperMode(LooperMode.Mode.PAUSED)
public class ScannerTest {
  private StashNativePlugin plugin;

  @Before public void prepare() {
    plugin = StashNativePlugin.getInstance();
    plugin.resetPresentationState();
  }

  @After public void cleanup() {
    plugin.setListener(null);
    plugin.resetPresentationState();
  }

  @Test
  @Config(shadows = ResolvedScannerModuleShadow.class)
  public void admissionFollowsHostAndRefusesOverlappingPresentations() {
    Activity host = Robolectric.buildActivity(Activity.class).setup().get();
    host.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE);
    plugin.openScanner(host);
    Intent intent = Shadows.shadowOf(host).getNextStartedActivity();
    assertTrue(intent.getBooleanExtra(CardConstants.INTENT_EXTRA_SCANNER, false));
    assertNull(intent.getStringExtra(CardConstants.INTENT_EXTRA_URL));
    assertEquals(StashNative.CardConfig.ORIENTATION_FOLLOW_HOST,
        StashPresentationOptions.read(intent).orientation);
    assertTrue(plugin.isCurrentlyPresented());
    plugin.openScanner(host);
    plugin.openCard(host, "https://example.com", null);
    assertNull(Shadows.shadowOf(host).getNextStartedActivity());
  }

  @Test public void missingModuleResolvesToNullWithoutThrowing() {
    StashCardActivity card = Robolectric.buildActivity(StashCardActivity.class).get();
    assertFalse(StashScannerContent.isAvailable());
    assertNull(StashScannerContent.create(card));
  }

  @Test public void missingModulePresentsNothingAndReportsAsynchronouslyOnce() {
    Activity host = Robolectric.buildActivity(Activity.class).setup().get();
    long session = plugin.presentationSessionId;
    List<String> events = new ArrayList<>();
    plugin.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onScannerError(StashNative.ScannerError error) {
        assertFalse(plugin.isCurrentlyPresented());
        events.add(error.name());
      }

      @Override public void onScannerDismissed() {
        events.add("scanner-dismissed");
      }
    });
    plugin.openScanner(host);
    assertNull(Shadows.shadowOf(host).getNextStartedActivity());
    assertFalse(plugin.isCurrentlyPresented());
    assertEquals(session, plugin.presentationSessionId);
    assertTrue(events.isEmpty());
    idle(0);
    assertEquals(Collections.singletonList("SCANNER_UNAVAILABLE"), events);
    idle(1000);
    assertEquals(Collections.singletonList("SCANNER_UNAVAILABLE"), events);
    assertNull(Shadows.shadowOf(host).getNextStartedActivity());
    assertFalse(plugin.isCurrentlyPresented());
  }

  @Test
  @Config(shadows = LibraryMissingAtFirstUseShadow.class)
  public void libraryMissingAtFirstUseClosesCardAsUnavailableWithoutCrashing() {
    Activity host = Robolectric.buildActivity(Activity.class).setup().get();
    Shadows.shadowOf(host.getApplication()).grantPermissions(
        host.getPackageName() + ".permission.STASH_NATIVE_INTERNAL");
    List<String> events = new ArrayList<>();
    plugin.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onScannerError(StashNative.ScannerError error) {
        events.add(error.name());
      }

      @Override public void onScannerDismissed() {
        events.add("scanner-dismissed");
      }
    });
    plugin.openScanner(host);
    Intent intent = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(intent);
    ActivityController<StashCardActivity> scanner =
        Robolectric.buildActivity(StashCardActivity.class, intent);
    try {
      scanner.create().start().resume();
      StashCardActivity card = scanner.get();
      assertTrue(card.isFinishing());
      assertNull(card.scannerContent);
      assertEquals(1, LibraryMissingAtFirstUseShadow.content.disposals);
      assertFalse(plugin.isCurrentlyPresented());
      assertEquals(Collections.singletonList("SCANNER_UNAVAILABLE"), events);
      scanner.pause().stop().destroy();
      idle(1000);
      assertEquals(Collections.singletonList("SCANNER_UNAVAILABLE"), events);
    } finally {
      if (!scanner.get().isDestroyed()) {
        scanner.destroy();
      }
      host.finish();
      idle(0);
    }
  }

  @Test
  @Config(shadows = ResolvedScannerModuleShadow.class)
  public void unavailableScannerReportsOnceAndAllowsCheckoutFromCallback() {
    Activity host = Robolectric.buildActivity(Activity.class).setup().get();
    plugin.openScanner(host);
    StashCardActivity unavailable = Robolectric.buildActivity(StashCardActivity.class).get();
    unavailable.setIntent(Shadows.shadowOf(host).getNextStartedActivity());
    plugin.setCheckoutActivity(unavailable);
    unavailable.isDismissing = true;
    unavailable.finish();
    int[] errors = {0};
    plugin.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onScannerError(StashNative.ScannerError error) {
        assertEquals(StashNative.ScannerError.SCANNER_UNAVAILABLE, error);
        assertFalse(plugin.isCurrentlyPresented());
        errors[0]++;
        plugin.openCard(host, "https://example.com", null);
      }
    });
    plugin.scannerUnavailable(unavailable);
    assertEquals(1, errors[0]);
    assertTrue(plugin.isCurrentlyPresented());
    assertNotNull(Shadows.shadowOf(host).getNextStartedActivity());
    plugin.scannerUnavailable(unavailable);
    assertEquals(1, errors[0]);
    assertTrue(plugin.isCurrentlyPresented());
  }

  @Test
  @Config(shadows = UnavailableScannerShadow.class)
  public void unavailableScannerStartupFinishesBeforeErrorAndPreservesReentrantCard() {
    Activity host = Robolectric.buildActivity(Activity.class).setup().get();
    Shadows.shadowOf(host.getApplication()).grantPermissions(
        host.getPackageName() + ".permission.STASH_NATIVE_INTERNAL");
    plugin.openScanner(host);
    Intent scannerIntent = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(scannerIntent);
    ActivityController<StashCardActivity> scanner =
        Robolectric.buildActivity(StashCardActivity.class, scannerIntent);
    List<ActivityController<StashCardActivity>> replacements = new ArrayList<>();
    List<String> events = new ArrayList<>();
    plugin.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onScannerError(StashNative.ScannerError error) {
        assertEquals(StashNative.ScannerError.SCANNER_UNAVAILABLE, error);
        assertTrue(scanner.get().isFinishing());
        assertTrue(scanner.get().isDismissing);
        assertFalse(plugin.isCurrentlyPresented());
        events.add(error.name());
        plugin.openCard(host, "https://example.invalid/checkout", null);
        Intent cardIntent = Shadows.shadowOf(host).getNextStartedActivity();
        assertNotNull(cardIntent);
        replacements.add(Robolectric.buildActivity(StashCardActivity.class, cardIntent)
            .create().start().resume());
      }

      @Override public void onScannerDismissed() {
        events.add("scanner-dismissed");
      }
    });
    try {
      scanner.create();
      assertEquals(Collections.singletonList("SCANNER_UNAVAILABLE"), events);
      assertEquals(1, replacements.size());
      StashCardActivity replacement = replacements.get(0).get();
      scanner.destroy();
      idle(0);
      plugin.scannerUnavailable(scanner.get());
      assertEquals(Collections.singletonList("SCANNER_UNAVAILABLE"), events);
      assertTrue(scanner.get().isDestroyed());
      assertTrue(plugin.isCurrentlyPresented());
      assertFalse(replacement.isFinishing());
      assertEquals(replacement.getPresentationSessionId(), plugin.presentationSessionId);
    } finally {
      plugin.resetPresentationState();
      for (ActivityController<StashCardActivity> replacement : replacements) {
        replacement.pause().stop().destroy();
      }
      if (!scanner.get().isDestroyed()) {
        scanner.destroy();
      }
      host.finish();
      idle(0);
    }
  }

  @Test
  @Config(shadows = ResolvedScannerModuleShadow.class)
  public void configurationIsSnapshottedBeforeMainDispatchAndSurvivesIntentTransport()
      throws Exception {
    Activity host = Robolectric.buildActivity(Activity.class).setup().get();
    StashNative.ScannerConfig config = new StashNative.ScannerConfig();
    config.headerText = "Propojte svůj účet";
    config.calloutTitle = "Naskenujte kód obchodu";
    config.calloutSubtitle = "Umístěte QR kód doprostřed.\nاستخدم رمز المتجر";
    config.cameraUnavailableText = "Kamera není dostupná";
    config.connectedText = "Připojeno";
    config.showCallout = false;
    Thread worker = new Thread(() -> plugin.openScanner(host, config));
    worker.start();
    worker.join();
    config.headerText = "changed";
    config.calloutTitle = null;
    config.calloutSubtitle = null;
    config.cameraUnavailableText = null;
    config.connectedText = null;
    config.showCallout = true;
    idle(0);
    Intent intent = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(intent);
    Parcel parcel = Parcel.obtain();
    try {
      intent.writeToParcel(parcel, 0);
      parcel.setDataPosition(0);
      StashScannerOptions restored =
          StashScannerOptions.read(Intent.CREATOR.createFromParcel(parcel));
      assertEquals("Propojte svůj účet", restored.headerText);
      assertEquals("Naskenujte kód obchodu", restored.calloutTitle);
      assertEquals("Umístěte QR kód doprostřed.\nاستخدم رمز المتجر", restored.calloutSubtitle);
      assertEquals("Kamera není dostupná", restored.cameraUnavailableText);
      assertEquals("Připojeno", restored.connectedText);
      assertFalse(restored.showCallout);
      assertEquals(StashNative.CardConfig.ORIENTATION_FOLLOW_HOST,
          StashPresentationOptions.read(intent).orientation);
    } finally {
      parcel.recycle();
    }
  }

  @Test public void cameraErrorKeepsCardAdmittedAndScanClearsStateBeforeCallback()
      throws Exception {
    List<String> events = new ArrayList<>();
    plugin.isCurrentlyPresented = true;
    plugin.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onScannerError(StashNative.ScannerError error) {
        assertTrue(plugin.isCurrentlyPresented());
        events.add(error.name());
      }

      @Override public void onQrCodeScanned(String content) {
        assertFalse(plugin.isCurrentlyPresented());
        events.add(content);
      }

      @Override public void onScannerDismissed() {
        fail("successful scanning must not also dismiss");
      }
    });
    dispatch(new Intent(CardConstants.BROADCAST_SCANNER_ERROR)
        .putExtra(CardConstants.BROADCAST_EXTRA_SCANNER_ERROR, "CAMERA_PERMISSION_DENIED"));
    Intent result = new Intent(CardConstants.BROADCAST_SCANNER_SCANNED)
        .putExtra(CardConstants.BROADCAST_EXTRA_SCANNER_CONTENT, "raw payload");
    dispatch(result);
    dispatch(result);
    assertEquals(java.util.Arrays.asList("CAMERA_PERMISSION_DENIED", "raw payload"), events);
  }

  private void dispatch(Intent intent) throws Exception {
    Method method = StashNativePlugin.class.getDeclaredMethod(
        "dispatchCheckoutBridgeIntent", String.class, Intent.class);
    method.setAccessible(true);
    intent.putExtra(StashCheckoutBridge.EXTRA_SESSION_ID, plugin.presentationSessionId);
    method.invoke(plugin, intent.getAction(), intent);
  }

  private static void idle(int milliseconds) {
    Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(Duration.ofMillis(milliseconds));
  }

  /** The module resolves for admission, but its constructor fails in the card. */
  @Implements(StashScannerContent.class)
  public static class UnavailableScannerShadow {
    @Implementation
    protected static boolean isAvailable() {
      return true;
    }

    @Implementation
    protected static StashScannerContent create(StashScannerHost host) {
      return null;
    }
  }

  /** A partial installation whose missing library is first touched when the camera starts. */
  @Implements(StashScannerContent.class)
  public static class LibraryMissingAtFirstUseShadow {
    static FailingContent content;

    @Implementation
    protected static boolean isAvailable() {
      return true;
    }

    @Implementation
    protected static StashScannerContent create(StashScannerHost host) {
      content = new FailingContent(host.getActivity());
      return content;
    }
  }

  static final class FailingContent extends StashScannerContent {
    private final View view;
    int disposals;

    FailingContent(Activity activity) {
      view = new View(activity);
    }

    @Override public View getView() {
      return view;
    }

    @Override public void setBottomInset(int inset) {}

    @Override public void resume() {
      throw new NoClassDefFoundError("androidx/camera/lifecycle/ProcessCameraProvider");
    }

    @Override public void pause() {}

    @Override public void dispose() {
      disposals++;
    }

    @Override public void geometryChanged() {}

    @Override public void permissionResult() {}

    @Override public void showConnected(Runnable completion) {}
  }
}
