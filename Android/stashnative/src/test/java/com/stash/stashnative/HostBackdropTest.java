package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.Matrix;
import android.graphics.RectF;
import android.graphics.drawable.BitmapDrawable;
import android.widget.FrameLayout;
import android.widget.ImageView;
import java.io.ByteArrayOutputStream;
import java.time.Duration;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.LooperMode;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
@LooperMode(LooperMode.Mode.PAUSED)
public class HostBackdropTest {
  private Activity host;
  private StashNativeCardPlugin plugin;
  private StashNativeCard.CardConfig config;
  private StashHostBackdropSupport ownedBackdrop;

  @Before public void prepare() {
    plugin = StashNativeCardPlugin.getInstance();
    plugin.resetPresentationState();
    host = Robolectric.buildActivity(Activity.class).setup().get();
    Shadows.shadowOf(host.getApplication()).grantPermissions(
        host.getPackageName() + ".permission.STASH_NATIVE_INTERNAL");
    config = new StashNativeCard.CardConfig();
    config.orientationPreference = StashNativeCard.CardConfig.ORIENTATION_PORTRAIT;
  }

  @After public void cleanup() {
    if (ownedBackdrop != null) {
      ownedBackdrop.dispose();
    }
    plugin.resetPresentationState();
    host.finish();
  }

  @Test @Config(sdk = {21, 28, 33})
  public void replacementAndExplicitClearReleasePendingImages() {
    Bitmap first = bitmap();
    Bitmap second = bitmap();
    StashNativeCard.setBackdropBitmap(first);
    StashNativeCard.setBackdropBitmap(first);
    assertFalse(first.isRecycled());
    StashNativeCard.setBackdropBitmap(second);
    assertTrue(first.isRecycled());
    assertFalse(second.isRecycled());
    StashNativeCard.setBackdropBitmap(null);
    assertTrue(second.isRecycled());
  }

  @Test public void invalidBytesClearPendingImage() {
    Bitmap bitmap = bitmap();
    StashNativeCard.setBackdropBitmap(bitmap);
    StashNativeCard.setBackdropBytes(new byte[] {1, 2, 3});
    assertTrue(bitmap.isRecycled());
    assertNull(StashHostBackdropSupport.decode(null));
    assertNull(StashHostBackdropSupport.decode(new byte[0]));
  }

  @Test public void bytesDecodeAndLargeImagesStayWithinTextureBudget() {
    Bitmap original = Bitmap.createBitmap(5000, 100, Bitmap.Config.ARGB_8888);
    ByteArrayOutputStream bytes = new ByteArrayOutputStream();
    assertTrue(original.compress(Bitmap.CompressFormat.PNG, 100, bytes));
    Bitmap decoded = StashHostBackdropSupport.decode(bytes.toByteArray());
    assertNotNull(decoded);
    assertTrue(decoded.getWidth() <= 2400);
    decoded.recycle();
    ownedBackdrop = StashHostBackdropSupport.create(host, original);
    FrameLayout root = new FrameLayout(host);
    ownedBackdrop.attach(host, root);
    assertTrue(original.isRecycled());
    Bitmap shown = ((BitmapDrawable) ((ImageView) root.getChildAt(0)).getDrawable()).getBitmap();
    assertEquals(2400, shown.getWidth());
    ownedBackdrop.dispose();
    assertEquals(0, root.getChildCount());
    assertTrue(shown.isRecycled());
  }

  @Test public void rejectedOpenDoesNotConsumeAndAcceptedOpenConsumesOnce() {
    Bitmap bitmap = bitmap();
    StashNativeCard.setBackdropBitmap(bitmap);
    plugin.openCard(host, "", config);
    assertFalse(bitmap.isRecycled());
    plugin.openCard(host, "https://example.invalid", config);
    ownedBackdrop = plugin.takeBackdrop(plugin.presentationSessionId);
    assertNotNull(ownedBackdrop);
    assertNull(plugin.takeBackdrop(plugin.presentationSessionId));
    FrameLayout root = new FrameLayout(host);
    ownedBackdrop.attach(host, root);
    assertSame(bitmap,
        ((BitmapDrawable) ((ImageView) root.getChildAt(0)).getDrawable()).getBitmap());
  }

  @Test public void resetBeforeActivityCreationCannotLeakBackdropIntoNextSession() {
    Bitmap bitmap = bitmap();
    StashNativeCard.setBackdropBitmap(bitmap);
    plugin.openCard(host, "https://example.invalid", config);
    long oldSession = plugin.presentationSessionId;
    plugin.resetPresentationState();
    assertTrue(bitmap.isRecycled());
    StashNativeCard.setBackdropBitmap(bitmap());
    plugin.openCard(host, "https://example.invalid", config);
    assertNull(plugin.takeBackdrop(oldSession));
    ownedBackdrop = plugin.takeBackdrop(plugin.presentationSessionId);
    assertNotNull(ownedBackdrop);
  }

  @Test public void scannerDoesNotUseOrConsumePendingCardBackdrop() {
    Bitmap bitmap = bitmap();
    StashNativeCard.setBackdropBitmap(bitmap);
    plugin.codeLink(host);
    assertNull(plugin.takeBackdrop(plugin.presentationSessionId));
    assertFalse(bitmap.isRecycled());
    plugin.cleanupAllViews();
    plugin.openCard(host, "https://example.invalid", config);
    ownedBackdrop = plugin.takeBackdrop(plugin.presentationSessionId);
    assertNotNull(ownedBackdrop);
  }

  @Test public void followHostCardDiscardsItsUnusedBackdrop() {
    Bitmap bitmap = bitmap();
    StashNativeCard.setBackdropBitmap(bitmap);
    plugin.openCard(host, "https://example.invalid", null);
    assertTrue(bitmap.isRecycled());
    assertNull(plugin.takeBackdrop(plugin.presentationSessionId));
  }

  @Test public void launchFailureReleasesAdmittedBackdrop() {
    Activity failingHost = Robolectric.buildActivity(FailingHost.class).setup().get();
    Bitmap bitmap = bitmap();
    StashNativeCard.setBackdropBitmap(bitmap);
    plugin.openCard(failingHost, "https://example.invalid", config);
    assertTrue(bitmap.isRecycled());
    assertFalse(plugin.isCurrentlyPresented());
    assertNull(plugin.takeBackdrop(plugin.presentationSessionId));
    failingHost.finish();
  }

  @Test @Config(qualifiers = "sw600dp-land")
  public void tabletIgnoresPortraitBackdrop() {
    Bitmap bitmap = bitmap();
    StashNativeCard.setBackdropBitmap(bitmap);
    plugin.openCard(host, "https://example.invalid", config);
    Intent intent = Shadows.shadowOf(host).getNextStartedActivity();
    org.robolectric.android.controller.ActivityController<StashCheckoutActivity> controller =
        Robolectric.buildActivity(StashCheckoutActivity.class, intent).create();
    assertTrue(bitmap.isRecycled());
    assertEquals(ActivityInfo.SCREEN_ORIENTATION_BEHIND,
        controller.get().getRequestedOrientation());
    assertFalse(controller.get().rootLayout.getChildAt(0) instanceof ImageView);
    controller.destroy();
  }

  @Test public void allRotationMappingsCoverResizedWindowWithoutMirroring() {
    for (int source = 0; source < 4; source++) {
      for (int current = 0; current < 4; current++) {
        for (int[] size : new int[][] {{400, 800}, {900, 400}, {500, 500}}) {
          Matrix matrix = StashHostBackdropSupport.matrix(1000, 600,
              size[0], size[1], source, current);
          RectF bounds = new RectF(0, 0, 1000, 600);
          matrix.mapRect(bounds);
          assertTrue(bounds.left <= 0.01f && bounds.top <= 0.01f);
          assertTrue(bounds.right >= size[0] - 0.01f && bounds.bottom >= size[1] - 0.01f);
          float[] center = {500, 300};
          matrix.mapPoints(center);
          assertEquals(size[0] / 2f, center[0], 0.01f);
          assertEquals(size[1] / 2f, center[1], 0.01f);
          float[] axes = {1, 0, 0, 1};
          matrix.mapVectors(axes);
          assertTrue(axes[0] * axes[3] - axes[1] * axes[2] > 0);
        }
      }
    }
  }

  @Test public void oppositeLandscapeDirectionsRotateInOppositeDirections() {
    float[] left = {0, 0};
    float[] right = {0, 0};
    StashHostBackdropSupport.matrix(800, 400, 400, 800, 1, 0).mapPoints(left);
    StashHostBackdropSupport.matrix(800, 400, 400, 800, 3, 0).mapPoints(right);
    assertEquals(400, left[0], 0.01f);
    assertEquals(0, left[1], 0.01f);
    assertEquals(0, right[0], 0.01f);
    assertEquals(800, right[1], 0.01f);
  }

  @Test public void returnWaitsForLandscapeAndCompletesOnlyOnce() {
    FrameLayout root = landscapeBackdrop();
    int[] completed = {0};
    assertTrue(ownedBackdrop.finishAfterRotation(() -> completed[0]++));
    assertEquals(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE, host.getRequestedOrientation());
    Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(Duration.ofMillis(100));
    assertEquals(0, completed[0]);
    host.getResources().getConfiguration().orientation = Configuration.ORIENTATION_LANDSCAPE;
    root.getChildAt(0).layout(0, 0, 800, 400);
    Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(Duration.ofMillis(100));
    assertEquals(1, completed[0]);
    Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(Duration.ofSeconds(1));
    assertEquals(1, completed[0]);
  }

  @Test public void ignoredRotationTimesOutAndDisposalCancelsPendingReturn() {
    landscapeBackdrop();
    int[] completed = {0};
    ownedBackdrop.finishAfterRotation(() -> completed[0]++);
    Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(Duration.ofSeconds(1));
    assertEquals(1, completed[0]);
    ownedBackdrop.dispose();
    landscapeBackdrop();
    ownedBackdrop.finishAfterRotation(() -> completed[0]++);
    ownedBackdrop.dispose();
    Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(Duration.ofSeconds(1));
    assertEquals(1, completed[0]);
  }

  @Test public void reverseLandscapeHostKeepsItsRequestedDirection() {
    host.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE);
    landscapeBackdrop();
    host.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT);
    ownedBackdrop.finishAfterRotation(() -> {});
    assertEquals(ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
        host.getRequestedOrientation());
  }

  private FrameLayout landscapeBackdrop() {
    host.getResources().getConfiguration().orientation = Configuration.ORIENTATION_LANDSCAPE;
    ownedBackdrop = StashHostBackdropSupport.create(host, bitmap());
    FrameLayout root = new FrameLayout(host);
    host.setContentView(root);
    ownedBackdrop.attach(host, root);
    host.getResources().getConfiguration().orientation = Configuration.ORIENTATION_PORTRAIT;
    root.getChildAt(0).layout(0, 0, 400, 800);
    return root;
  }

  private Bitmap bitmap() {
    return Bitmap.createBitmap(800, 400, Bitmap.Config.RGB_565);
  }

  public static class FailingHost extends Activity {
    @Override public void startActivity(Intent intent) {
      throw new IllegalStateException("Launch unavailable");
    }
  }
}
