package com.stash.stashnative;

import static org.junit.Assert.*;

import android.Manifest;
import android.app.Activity;
import android.app.Application;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.graphics.Rect;
import android.graphics.RectF;
import android.view.View;
import android.widget.FrameLayout;
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
import org.robolectric.annotation.Config;
import org.robolectric.annotation.LooperMode;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = {21, 28})
@LooperMode(LooperMode.Mode.PAUSED)
public class CodeLinkTest {
  private StashNativeCardPlugin plugin;
  private RecordingCheckout activity;

  @Before public void prepare() {
    plugin = StashNativeCardPlugin.getInstance();
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
    assertEquals(StashNativeCard.CardConfig.ORIENTATION_FOLLOW_HOST,
        StashPresentationOptions.read(intent).orientation);
    assertTrue(plugin.isCurrentlyPresented());
    plugin.codeLink(host);
    plugin.openCard(host, "https://example.com", null);
    assertNull(Shadows.shadowOf(host).getNextStartedActivity());
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
    StashCodeLinkView view = new StashCodeLinkView(host, () -> {}, () -> {});
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
    StashCodeLinkView view = new StashCodeLinkView(host, () -> {}, () -> {});
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
    plugin.setListener(new StashNativeCard.StashNativeCardListenerAdapter() {
      @Override public void onCodeLinkError(StashNativeCard.CodeLinkError error) {
        assertTrue(plugin.isCurrentlyPresented());
        events.add(error.name());
      }
      @Override public void onQrCodeScanned(String content) {
        assertFalse(plugin.isCurrentlyPresented());
        events.add(content);
      }
      @Override public void onDialogDismissed() {
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
    activity.codeLinkSupport = new StashCodeLinkSupport(activity);
    activity.cardContainer.addView(activity.codeLinkSupport.view);
    Shadows.shadowOf((Application) activity.getApplicationContext())
        .denyPermissions(Manifest.permission.CAMERA);
    activity.codeLinkSupport.resume();
    activity.presentation.environmentChanged();
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
    Method method = StashNativeCardPlugin.class.getDeclaredMethod(
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
}
