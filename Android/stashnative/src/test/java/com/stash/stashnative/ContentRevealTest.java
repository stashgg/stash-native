package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.content.Context;
import android.os.Looper;
import android.webkit.ValueCallback;
import android.webkit.WebView;
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

/** Covers paint-gated reveal, stale paint callbacks, and foreground timeout accounting. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
@LooperMode(LooperMode.Mode.PAUSED)
public class ContentRevealTest {
  private StashCardActivity activity;
  private RecordingWebView web;
  private StashContentRevealSupport support;

  /** Creates an uncommitted navigation with controlled WebView callbacks. */
  @Before
  public void prepare() {
    activity = Robolectric.buildActivity(StashCardActivity.class).get();
    web = new RecordingWebView(activity);
    activity.webView = web;
    web.setAlpha(0);
    support = new StashContentRevealSupport(activity);
    support.navigationStarted();
  }

  @After
  public void cleanup() {
    support.dispose();
    web.destroy();
  }

  private void finishDocument() {
    activity.mainFrameNavigationCommitted = true;
    support.documentFinished();
  }

  private void advance(long millis) {
    Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis));
  }

  @Test
  public void paintIsAwaitedBeforeRevealing() {
    finishDocument();
    assertNotNull(web.paint);
    advance(100);
    assertFalse(activity.webViewLoadingRevealComplete);
    assertEquals(0, web.getAlpha(), 0);
    web.paint.onComplete(0);
    assertTrue(activity.webViewLoadingRevealComplete);
    assertEquals(1, web.getAlpha(), 0);
    assertEquals(0, web.scripts);
  }

  @Test
  public void revealRequiresBothDocumentFinishAndCommit() {
    support.documentFinished();
    assertNull(web.paint);
    activity.mainFrameNavigationCommitted = true;
    support.check();
    assertNotNull(web.paint);
  }

  @Test
  public void navigationInvalidatesPendingPaintFromPreviousDocument() {
    finishDocument();
    final WebView.VisualStateCallback stalePaint = web.takePaint();
    support.navigationStarted();
    stalePaint.onComplete(0);
    assertFalse(activity.webViewLoadingRevealComplete);
    assertNull(web.paint);
    finishDocument();
    assertFalse(activity.webViewLoadingRevealComplete);
    web.takePaint().onComplete(0);
    assertTrue(activity.webViewLoadingRevealComplete);
  }

  @Test
  public void pauseInvalidatesPaintAndDoesNotConsumeForegroundBudget() {
    finishDocument();
    final WebView.VisualStateCallback stalePaint = web.takePaint();
    advance(1000);
    activity.isActivityPaused = true;
    support.pause();
    advance(60000);
    stalePaint.onComplete(0);
    assertFalse(activity.webViewLoadingRevealComplete);
    activity.isActivityPaused = false;
    support.check();
    assertNotNull(web.paint);
    advance(13900);
    assertFalse(activity.webViewLoadingRevealComplete);
    advance(100);
    assertTrue(activity.webViewLoadingRevealComplete);
  }

  @Test
  public void missingProviderCallbackCannotKeepCommittedCheckoutCoveredForever() {
    finishDocument();
    advance(14900);
    assertFalse(activity.webViewLoadingRevealComplete);
    advance(100);
    assertTrue(activity.webViewLoadingRevealComplete);
  }

  @Test
  public void timeoutCannotRevealAnUncommittedNavigation() {
    advance(16000);
    assertFalse(activity.webViewLoadingRevealComplete);
    assertEquals(0, web.getAlpha(), 0);
  }

  @Test
  public void dismissalAndDisposalInvalidatePendingPaint() {
    finishDocument();
    activity.isDismissing = true;
    web.paint.onComplete(0);
    assertFalse(activity.webViewLoadingRevealComplete);
    activity.isDismissing = false;
    support.dispose();
    advance(20000);
    assertFalse(activity.webViewLoadingRevealComplete);
  }

  @Test
  public void laterNavigationLeavesRevealedContentVisible() {
    finishDocument();
    web.takePaint().onComplete(0);
    support.navigationStarted();
    support.documentFinished();
    assertNull(web.paint);
    assertEquals(1, web.getAlpha(), 0);
  }

  @Test
  @Config(sdk = 21)
  public void minimumApiRevealsShortlyAfterLoadWithoutVisualStateCallback() {
    finishDocument();
    assertNull(web.paint);
    assertFalse(activity.webViewLoadingRevealComplete);
    advance(50);
    assertTrue(activity.webViewLoadingRevealComplete);
  }

  private static final class RecordingWebView extends WebView {
    int scripts;
    VisualStateCallback paint;

    RecordingWebView(Context context) {
      super(context);
    }

    @Override
    public void evaluateJavascript(String script, ValueCallback<String> callback) {
      scripts++;
    }

    @Override
    public void postVisualStateCallback(long requestId, VisualStateCallback callback) {
      paint = callback;
    }

    VisualStateCallback takePaint() {
      VisualStateCallback callback = paint;
      paint = null;
      assertNotNull(callback);
      return callback;
    }
  }
}
