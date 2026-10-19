package com.stash.stashnative.codelink;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.graphics.Rect;
import android.graphics.RectF;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.EncodeHintType;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;
import com.stash.stashnative.StashNative;
import com.stash.stashnative.StashScannerOptions;
import java.nio.ByteBuffer;
import java.util.Collections;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.LooperMode;
import org.robolectric.util.ReflectionHelpers;

/** Scanner chrome layout, copy, and QR decoding inside the module. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = {21, 28})
@LooperMode(LooperMode.Mode.PAUSED)
public class ScannerViewTest {

  @Test public void defaultsEmptyTextAndCustomCopyReachScannerViews() {
    Activity host = Robolectric.buildActivity(Activity.class).setup().get();
    StashNative.ScannerConfig config = new StashNative.ScannerConfig();
    assertTrue(config.showCallout);
    config.headerText = "";
    config.calloutTitle = "";
    config.calloutSubtitle = "";
    config.cameraUnavailableText = "";
    config.connectedText = "";
    StashScannerView defaults = new StashScannerView(host,
        StashScannerOptions.from(config), () -> {}, () -> {});
    assertTrue(hasText(defaults, "Scan QR code"));
    assertTrue(hasText(defaults, "Scan the webshop code"));
    assertTrue(hasText(defaults, "Keep the QR code centered inside the frame."));
    TextView statusText = ReflectionHelpers.getField(defaults, "statusText");
    View spinner = ReflectionHelpers.getField(defaults, "spinner");
    assertEquals(View.GONE, statusText.getVisibility());
    assertEquals(View.VISIBLE, spinner.getVisibility());
    defaults.showStatus(R.string.stash_scanner_permission, false, true);
    assertEquals(View.VISIBLE, statusText.getVisibility());
    assertEquals(View.GONE, spinner.getVisibility());
    defaults.showStatus(0, true, false);
    assertEquals(View.GONE, statusText.getVisibility());
    assertEquals(View.VISIBLE, spinner.getVisibility());
    defaults.showStatus(R.string.stash_scanner_unavailable, false, false);
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
      StashScannerView shown = new StashScannerView(host,
          StashScannerOptions.from(config), () -> {}, () -> {});
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
      StashScannerView hidden = new StashScannerView(host,
          StashScannerOptions.from(config), () -> {}, () -> {});
      layoutScanner(hidden, size);
      assertFalse(hasText(hidden, config.calloutTitle));
      assertFalse(hasText(hidden, config.calloutSubtitle));
      assertTrue(hidden.scanFrame().width() >= shown.scanFrame().width());
      assertTrue(hidden.scanFrame().bottom < size[1] - 24);
      shown.showStatus(R.string.stash_scanner_unavailable, false, false);
      assertTrue(hasText(shown, config.cameraUnavailableText));
      shown.showStatus(R.string.stash_scanner_permission, false, true);
      assertTrue(hasText(shown, host.getString(R.string.stash_scanner_permission)));
      assertFalse(hasText(shown, config.cameraUnavailableText));
      shown.showConnected();
      assertTrue(hasText(shown, config.connectedText));
      shown.dispose();
      hidden.dispose();
    }
  }

  private static void layoutScanner(StashScannerView view, int[] size) {
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

  @Test public void decoderPreservesPayloadWithRotationInversionAndPaddedPlanes()
      throws Exception {
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
        assertEquals(content, new StashScannerDecoder().decode(
            buffer, 240, 240, stride, 2, new Rect(0, 0, 240, 240)));
        assertNull(new StashScannerDecoder().decode(
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
    StashScannerDecoder decoder = new StashScannerDecoder();
    assertNull(decoder.decode(frame, 640, 480, 640, 1, new Rect(200, 80, 500, 380)));
    assertEquals("outside", decoder.decode(frame, 640, 480, 640, 1, new Rect(0, 0, 180, 180)));
  }

  @Test public void scanFrameFitsPortraitLandscapeAndTabletCards() {
    Activity host = Robolectric.buildActivity(Activity.class).setup().get();
    StashScannerView view = new StashScannerView(host, StashScannerOptions.from(null),
        () -> {}, () -> {});
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
    StashScannerView view = new StashScannerView(host, StashScannerOptions.from(null),
        () -> {}, () -> {});
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
}
