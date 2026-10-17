package com.stash.stashnative;

import static org.junit.Assert.*;

import android.Manifest;
import android.app.Activity;
import android.app.Application;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.graphics.Rect;
import android.graphics.RectF;
import android.os.Parcel;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.TextView;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.EncodeHintType;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
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
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Shadows;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.Implementation;
import org.robolectric.annotation.Implements;
import org.robolectric.annotation.LooperMode;
import org.robolectric.util.ReflectionHelpers;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = {21, 28})
@LooperMode(LooperMode.Mode.PAUSED)
public class CodeLinkTest {
  private StashNativePlugin plugin;
  private RecordingCheckout activity;

  @Before public void prepare() {
    plugin = StashNativePlugin.getInstance();
    plugin.resetPresentationState();
  }

  @After public void cleanup() {
    if (activity != null) {
      activity.codeLinkSupport.dispose();
      activity.presentation.dispose();
    }
    plugin.setListener(null);
    plugin.resetPresentationState();
  }

  @Test public void admissionFollowsHostAndRefusesOverlappingPresentations() {
    Activity host = Robolectric.buildActivity(Activity.class).setup().get();
    host.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE);
    plugin.codeLink(host);
    Intent intent = Shadows.shadowOf(host).getNextStartedActivity();
    assertTrue(intent.getBooleanExtra(CardConstants.INTENT_EXTRA_CODE_LINK, false));
    assertNull(intent.getStringExtra(CardConstants.INTENT_EXTRA_URL));
    assertEquals(StashNative.CardConfig.ORIENTATION_FOLLOW_HOST,
        StashPresentationOptions.read(intent).orientation);
    assertTrue(plugin.isCurrentlyPresented());
    plugin.codeLink(host);
    plugin.openCard(host, "https://example.com", null);
    assertNull(Shadows.shadowOf(host).getNextStartedActivity());
  }

  @Test public void unavailableScannerReportsOnceAndAllowsCheckoutFromCallback() {
    Activity host = Robolectric.buildActivity(Activity.class).setup().get();
    plugin.codeLink(host);
    RecordingCheckout unavailable = Robolectric.buildActivity(RecordingCheckout.class).get();
    unavailable.setIntent(Shadows.shadowOf(host).getNextStartedActivity());
    plugin.setCheckoutActivity(unavailable);
    unavailable.isDismissing = true;
    unavailable.finish();
    int[] errors = {0};
    plugin.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onCodeLinkError(StashNative.CodeLinkError error) {
        assertEquals(StashNative.CodeLinkError.SCANNER_UNAVAILABLE, error);
        assertFalse(plugin.isCurrentlyPresented());
        errors[0]++;
        plugin.openCard(host, "https://example.com", null);
      }
    });
    plugin.codeLinkUnavailable(unavailable);
    assertEquals(1, errors[0]);
    assertTrue(plugin.isCurrentlyPresented());
    assertNotNull(Shadows.shadowOf(host).getNextStartedActivity());
    plugin.codeLinkUnavailable(unavailable);
    assertEquals(1, errors[0]);
    assertTrue(plugin.isCurrentlyPresented());
  }

  @Test
  @Config(shadows = UnavailableScannerShadow.class)
  public void unavailableScannerStartupFinishesBeforeErrorAndPreservesReentrantCard() {
    Activity host = Robolectric.buildActivity(Activity.class).setup().get();
    Shadows.shadowOf(host.getApplication()).grantPermissions(
        host.getPackageName() + ".permission.STASH_NATIVE_INTERNAL");
    plugin.codeLink(host);
    Intent scannerIntent = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(scannerIntent);
    ActivityController<StashCheckoutActivity> scanner =
        Robolectric.buildActivity(StashCheckoutActivity.class, scannerIntent);
    List<ActivityController<StashCheckoutActivity>> replacements = new ArrayList<>();
    List<String> events = new ArrayList<>();
    plugin.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onCodeLinkError(StashNative.CodeLinkError error) {
        assertEquals(StashNative.CodeLinkError.SCANNER_UNAVAILABLE, error);
        assertTrue(scanner.get().isFinishing());
        assertTrue(scanner.get().isDismissing);
        assertFalse(plugin.isCurrentlyPresented());
        events.add(error.name());
        plugin.openCard(host, "https://example.invalid/checkout", null);
        Intent cardIntent = Shadows.shadowOf(host).getNextStartedActivity();
        assertNotNull(cardIntent);
        replacements.add(Robolectric.buildActivity(StashCheckoutActivity.class, cardIntent)
            .create().start().resume());
      }

      @Override public void onScanDismissed() {
        events.add("scan-dismissed");
      }
    });
    try {
      scanner.create();
      assertEquals(Collections.singletonList("SCANNER_UNAVAILABLE"), events);
      assertEquals(1, replacements.size());
      StashCheckoutActivity replacement = replacements.get(0).get();
      scanner.destroy();
      idle(0);
      plugin.codeLinkUnavailable(scanner.get());
      assertEquals(Collections.singletonList("SCANNER_UNAVAILABLE"), events);
      assertTrue(scanner.get().isDestroyed());
      assertTrue(plugin.isCurrentlyPresented());
      assertFalse(replacement.isFinishing());
      assertEquals(replacement.getPresentationSessionId(), plugin.presentationSessionId);
    } finally {
      plugin.resetPresentationState();
      for (ActivityController<StashCheckoutActivity> replacement : replacements) {
        replacement.pause().stop().destroy();
      }
      if (!scanner.get().isDestroyed()) {
        scanner.destroy();
      }
      host.finish();
      idle(0);
    }
  }

  @Test public void configurationIsSnapshottedBeforeMainDispatchAndSurvivesIntentTransport()
      throws Exception {
    Activity host = Robolectric.buildActivity(Activity.class).setup().get();
    StashNative.CodeLinkConfig config = new StashNative.CodeLinkConfig();
    config.headerText = "Propojte svůj účet";
    config.calloutTitle = "Naskenujte kód obchodu";
    config.calloutSubtitle = "Umístěte QR kód doprostřed.\nاستخدم رمز المتجر";
    config.cameraUnavailableText = "Kamera není dostupná";
    config.connectedText = "Připojeno";
    config.showCallout = false;
    Thread worker = new Thread(() -> plugin.codeLink(host, config));
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
      StashCodeLinkOptions restored = StashCodeLinkOptions.read(Intent.CREATOR.createFromParcel(parcel));
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

  @Test public void defaultsEmptyTextAndCustomCopyReachScannerViews() {
    Activity host = Robolectric.buildActivity(Activity.class).setup().get();
    StashNative.CodeLinkConfig config = new StashNative.CodeLinkConfig();
    assertTrue(config.showCallout);
    config.headerText = "";
    config.calloutTitle = "";
    config.calloutSubtitle = "";
    config.cameraUnavailableText = "";
    config.connectedText = "";
    StashCodeLinkView defaults = new StashCodeLinkView(host,
        StashCodeLinkOptions.from(config), () -> {}, () -> {});
    assertTrue(hasText(defaults, "Scan QR code"));
    assertTrue(hasText(defaults, "Scan the webshop code"));
    assertTrue(hasText(defaults, "Keep the QR code centered inside the frame."));
    TextView statusText = ReflectionHelpers.getField(defaults, "statusText");
    View spinner = ReflectionHelpers.getField(defaults, "spinner");
    assertEquals(View.GONE, statusText.getVisibility());
    assertEquals(View.VISIBLE, spinner.getVisibility());
    defaults.showStatus(R.string.stash_code_link_permission, false, true);
    assertEquals(View.VISIBLE, statusText.getVisibility());
    assertEquals(View.GONE, spinner.getVisibility());
    defaults.showStatus(0, true, false);
    assertEquals(View.GONE, statusText.getVisibility());
    assertEquals(View.VISIBLE, spinner.getVisibility());
    defaults.showStatus(R.string.stash_code_link_unavailable, false, false);
    assertEquals("Camera unavailable", statusText.getText().toString());
    assertEquals(View.VISIBLE, statusText.getVisibility());
    assertEquals(View.GONE, spinner.getVisibility());
    defaults.showConnected();
    assertTrue(hasText(defaults, "Connected"));
    defaults.dispose();
    config.headerText = "Propojte svůj účet";
    config.calloutTitle = "Naskenujte kód obchodu";
    config.calloutSubtitle = "Umístěte QR kód doprostřed rámečku.\nاستخدم رمز المتجر";
    config.cameraUnavailableText = "Kamera není dostupná";
    config.connectedText = "Připojeno";
    for (int[] size : new int[][] {{320, 480}, {400, 330}, {400, 560}, {660, 330}}) {
      config.showCallout = true;
      StashCodeLinkView shown = new StashCodeLinkView(host,
          StashCodeLinkOptions.from(config), () -> {}, () -> {});
      layoutScanner(shown, size);
      assertTrue(hasText(shown, config.headerText));
      assertTrue(hasText(shown, config.calloutTitle));
      assertTrue(hasText(shown, config.calloutSubtitle));
      TextView heading = ReflectionHelpers.getField(shown, "heading");
      View callout = ReflectionHelpers.getField(shown, "callout");
      assertTrue(shown.scanFrame().top > heading.getBottom());
      assertTrue(shown.scanFrame().bottom < callout.getTop());
      assertTrue(shown.scanFrame().width() > 0);
      config.showCallout = false;
      StashCodeLinkView hidden = new StashCodeLinkView(host,
          StashCodeLinkOptions.from(config), () -> {}, () -> {});
      layoutScanner(hidden, size);
      assertFalse(hasText(hidden, config.calloutTitle));
      assertFalse(hasText(hidden, config.calloutSubtitle));
      assertTrue(hidden.scanFrame().width() >= shown.scanFrame().width());
      assertTrue(hidden.scanFrame().bottom < size[1] - 24);
      shown.showStatus(R.string.stash_code_link_unavailable, false, false);
      assertTrue(hasText(shown, config.cameraUnavailableText));
      shown.showStatus(R.string.stash_code_link_permission, false, true);
      assertTrue(hasText(shown, host.getString(R.string.stash_code_link_permission)));
      assertFalse(hasText(shown, config.cameraUnavailableText));
      shown.showConnected();
      assertTrue(hasText(shown, config.connectedText));
      shown.dispose();
      hidden.dispose();
    }
  }

  private static void layoutScanner(StashCodeLinkView view, int[] size) {
    view.setBottomInset(24);
    view.measure(View.MeasureSpec.makeMeasureSpec(size[0], View.MeasureSpec.EXACTLY),
        View.MeasureSpec.makeMeasureSpec(size[1], View.MeasureSpec.EXACTLY));
    view.layout(0, 0, size[0], size[1]);
  }

  private static boolean hasText(View view, String text) {
    if (view.getVisibility() != View.VISIBLE) {
      return false;
    }
    if (view instanceof TextView && text.contentEquals(((TextView) view).getText())) {
      return true;
    }
    if (view instanceof ViewGroup) {
      ViewGroup group = (ViewGroup) view;
      for (int index = 0; index < group.getChildCount(); index++) {
        if (hasText(group.getChildAt(index), text)) {
          return true;
        }
      }
    }
    return false;
  }

  @Test public void decoderPreservesPayloadWithRotationInversionAndPaddedPlanes() throws Exception {
    String content = "https://example.com/link?token=AbC%2F123&name=Žluťoučký";
    BitMatrix matrix = new QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, 240, 240,
        Collections.singletonMap(EncodeHintType.CHARACTER_SET, "UTF-8"));
    for (int turn = 0; turn < 4; turn++) {
      for (boolean inverted : new boolean[] {false, true}) {
        int stride = 510;
        ByteBuffer buffer = ByteBuffer.allocate(stride * 240 + 8);
        buffer.position(8);
        for (int y = 0; y < 240; y++) {
          for (int x = 0; x < 240; x++) {
            int sx = x;
            int sy = y;
            for (int rotation = 0; rotation < turn; rotation++) {
              int previous = sx;
              sx = 239 - sy;
              sy = previous;
            }
            boolean dark = matrix.get(sx, sy) != inverted;
            buffer.put(8 + y * stride + x * 2, (byte) (dark ? 0 : 255));
          }
        }
        assertEquals(content, new StashCodeLinkDecoder().decode(
            buffer, 240, 240, stride, 2, new Rect(0, 0, 240, 240)));
        assertNull(new StashCodeLinkDecoder().decode(
            buffer, 240, 240, stride, 2, new Rect(0, 0, 90, 240)));
      }
    }
  }

  @Test public void qrOutsideScanFrameIsIgnored() throws Exception {
    BitMatrix matrix = new QRCodeWriter().encode("outside", BarcodeFormat.QR_CODE, 160, 160);
    ByteBuffer frame = ByteBuffer.allocate(640 * 480);
    for (int y = 0; y < 480; y++) {
      for (int x = 0; x < 640; x++) {
        frame.put((byte) (x < 160 && y < 160 && matrix.get(x, y) ? 0 : 255));
      }
    }
    frame.rewind();
    StashCodeLinkDecoder decoder = new StashCodeLinkDecoder();
    assertNull(decoder.decode(frame, 640, 480, 640, 1, new Rect(200, 80, 500, 380)));
    assertEquals("outside", decoder.decode(frame, 640, 480, 640, 1, new Rect(0, 0, 180, 180)));
  }

  @Test public void scanFrameFitsPortraitLandscapeAndTabletCards() {
    Activity host = Robolectric.buildActivity(Activity.class).setup().get();
    StashCodeLinkView view = new StashCodeLinkView(host, StashCodeLinkOptions.from(null), () -> {}, () -> {});
    for (int[] size : new int[][] {{360, 560}, {400, 320}, {400, 560}, {320, 480}}) {
      view.setBottomInset(24);
      view.measure(View.MeasureSpec.makeMeasureSpec(size[0], View.MeasureSpec.EXACTLY),
          View.MeasureSpec.makeMeasureSpec(size[1], View.MeasureSpec.EXACTLY));
      view.layout(0, 0, size[0], size[1]);
      RectF frame = view.scanFrame();
      assertTrue(frame.width() > 50);
      assertEquals(frame.width(), frame.height(), 0.01);
      assertEquals(size[0] / 2f, frame.centerX(), 0.01);
      assertTrue(frame.top >= 72);
      assertTrue(frame.bottom < size[1] - 24);
      assertEquals(size[0], view.preview.getWidth());
      assertEquals(size[1], view.preview.getHeight());
    }
    view.dispose();
  }

  @Test public void navigationInsetMovesDetectionRegionWithoutResizingCard() {
    Activity host = Robolectric.buildActivity(Activity.class).setup().get();
    StashCodeLinkView view = new StashCodeLinkView(host, StashCodeLinkOptions.from(null), () -> {}, () -> {});
    int[] geometryChanges = {0};
    view.setGeometryListener(() -> geometryChanges[0]++);
    int width = View.MeasureSpec.makeMeasureSpec(360, View.MeasureSpec.EXACTLY);
    int height = View.MeasureSpec.makeMeasureSpec(560, View.MeasureSpec.EXACTLY);
    view.measure(width, height);
    view.layout(0, 0, 360, 560);
    RectF original = view.scanFrame();
    int before = geometryChanges[0];
    view.setBottomInset(48);
    view.measure(width, height);
    view.layout(0, 0, 360, 560);
    assertTrue(view.scanFrame().centerY() < original.centerY());
    assertEquals(before + 1, geometryChanges[0]);
    view.requestLayout();
    view.measure(width, height);
    view.layout(0, 0, 360, 560);
    assertEquals(before + 1, geometryChanges[0]);
    view.dispose();
  }

  @Test public void cameraErrorKeepsCardAdmittedAndScanClearsStateBeforeCallback() throws Exception {
    List<String> events = new ArrayList<>();
    plugin.isCurrentlyPresented = true;
    plugin.setListener(new StashNative.StashNativeListenerAdapter() {
      @Override public void onCodeLinkError(StashNative.CodeLinkError error) {
        assertTrue(plugin.isCurrentlyPresented());
        events.add(error.name());
      }
      @Override public void onQrCodeScanned(String content) {
        assertFalse(plugin.isCurrentlyPresented());
        events.add(content);
      }
      @Override public void onScanDismissed() {
        fail("successful scanning must not also dismiss");
      }
    });
    dispatch(new Intent(CardConstants.BROADCAST_CODE_LINK_ERROR)
        .putExtra(CardConstants.BROADCAST_EXTRA_CODE_LINK_ERROR, "CAMERA_PERMISSION_DENIED"));
    Intent result = new Intent(CardConstants.BROADCAST_CODE_LINK_SCANNED)
        .putExtra(CardConstants.BROADCAST_EXTRA_CODE_LINK_CONTENT, "raw payload");
    dispatch(result);
    dispatch(result);
    assertEquals(java.util.Arrays.asList("CAMERA_PERMISSION_DENIED", "raw payload"), events);
  }

  @Test public void connectedLocksUserDismissalAndDeliversOnlyAfterDestruction() {
    prepareScanner();
    activity.completeCodeLink("raw payload");
    activity.completeCodeLink("duplicate");
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
        .getStringExtra(CardConstants.BROADCAST_EXTRA_CODE_LINK_CONTENT));
  }

  @Test public void explicitDismissCancelsConnectedCallback() {
    prepareScanner();
    activity.completeCodeLink("cancelled");
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
    activity.completeCodeLink("cancelled");
    activity.finishForPluginResetWithoutCallbacks();
    idle(1500);
    activity.onDestroy();
    assertEquals(0, scanBroadcasts().size());
    assertFalse(broadcasts().stream().anyMatch(intent ->
        CardConstants.BROADCAST_CHECKOUT_DIALOG_DISMISSED.equals(intent.getAction())));
  }

  @Test public void backgroundPausesConnectedHold() {
    prepareScanner();
    activity.completeCodeLink("payload");
    idle(200);
    activity.codeLinkSupport.pause();
    idle(3000);
    assertFalse(activity.finished);
    activity.codeLinkSupport.resume();
    idle(200);
    assertFalse(activity.finished);
    idle(1000);
    assertTrue(activity.finished);
  }

  private void prepareScanner() {
    activity = Robolectric.buildActivity(RecordingCheckout.class).get();
    activity.codeLink = true;
    activity.options = StashPresentationOptions.card(null);
    activity.rootLayout = new FrameLayout(activity);
    activity.rootLayout.layout(0, 0, 400, 900);
    activity.backdropView = new View(activity);
    activity.cardContainer = new StashSheetLayout(activity, 28);
    activity.cardContainer.setLayoutParams(new FrameLayout.LayoutParams(400, 560));
    activity.presentation = new StashPresentationController(activity, activity.options);
    activity.codeLinkSupport = StashCodeLinkSession.create(activity);
    assertNotNull(activity.codeLinkSupport);
    activity.cardContainer.addView(activity.codeLinkSupport.getView());
    Shadows.shadowOf((Application) activity.getApplicationContext())
        .denyPermissions(Manifest.permission.CAMERA);
    activity.codeLinkSupport.resume();
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
      if (CardConstants.BROADCAST_CODE_LINK_SCANNED.equals(intent.getAction())) {
        matches.add(intent);
      }
    }
    return matches;
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

  public static class RecordingCheckout extends StashCheckoutActivity {
    boolean finished;
    @Override public void finish() {
      finished = true;
    }
  }

  @Implements(StashCodeLinkSession.class)
  public static class UnavailableScannerShadow {
    @Implementation
    protected static StashCodeLinkSession create(StashCheckoutActivity activity) {
      return null;
    }
  }
}
