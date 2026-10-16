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

/** Covers initial-paint readiness, stale callbacks, and foreground timeout accounting. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
@LooperMode(LooperMode.Mode.PAUSED)
public class ContentRevealTest {
  private StashCheckoutActivity activity;
  private RecordingWebView web;
  private StashContentRevealSupport support;

  /** Creates an uncommitted navigation with controlled WebView callbacks. */
  @Before
  public void prepare() {
    activity = Robolectric.buildActivity(StashCheckoutActivity.class).get();
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
  public void readinessIsCheckedAgainAfterPaintBeforeRevealing() {
    finishDocument();
    web.answer("false");
    assertNull(web.paint);
    assertEquals(0, web.getAlpha(), 0);
    advance(100);
    web.answer("true");
    assertNotNull(web.paint);
    assertFalse(activity.webViewLoadingRevealComplete);
    web.paint.onComplete(0);
    web.answer("false");
    assertFalse(activity.webViewLoadingRevealComplete);
    advance(100);
    web.answer("true");
    web.paint.onComplete(0);
    web.answer("true");
    assertTrue(activity.webViewLoadingRevealComplete);
    assertEquals(1, web.getAlpha(), 0);
  }

  @Test
  public void readinessRequiresBothDocumentFinishAndCommit() {
    support.documentFinished();
    assertNull(web.answer);
    activity.mainFrameNavigationCommitted = true;
    support.check();
    assertNotNull(web.answer);
  }

  @Test
  public void navigationInvalidatesPendingPaintFromPreviousDocument() {
    finishDocument();
    web.answer("true");
    final WebView.VisualStateCallback stalePaint = web.paint;
    support.navigationStarted();
    stalePaint.onComplete(0);
    assertNull(web.answer);
    assertFalse(activity.webViewLoadingRevealComplete);
    finishDocument();
    web.answer("false");
    assertFalse(activity.webViewLoadingRevealComplete);
  }

  @Test
  public void pauseInvalidatesProbeAndDoesNotConsumeForegroundBudget() {
    finishDocument();
    final ValueCallback<String> staleProbe = web.answer;
    advance(1000);
    activity.isActivityPaused = true;
    support.pause();
    advance(60000);
    staleProbe.onReceiveValue("true");
    assertNull(web.paint);
    assertFalse(activity.webViewLoadingRevealComplete);
    activity.isActivityPaused = false;
    support.check();
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
  public void dismissalAndDisposalInvalidatePendingReadiness() {
    finishDocument();
    activity.isDismissing = true;
    web.answer("true");
    assertFalse(activity.webViewLoadingRevealComplete);
    activity.isDismissing = false;
    support.dispose();
    advance(20000);
    assertFalse(activity.webViewLoadingRevealComplete);
  }

  @Test
  public void laterNavigationLeavesRevealedContentVisible() {
    finishDocument();
    web.answer("true");
    web.paint.onComplete(0);
    web.answer("true");
    support.navigationStarted();
    support.documentFinished();
    assertNull(web.answer);
    assertEquals(1, web.getAlpha(), 0);
  }

  @Test
  @Config(sdk = 21)
  public void minimumApiVerifiesReadinessWithoutVisualStateCallback() {
    finishDocument();
    web.answer("null");
    assertNull(web.paint);
    advance(50);
    web.answer("null");
    assertTrue(activity.webViewLoadingRevealComplete);
  }

  private static final class RecordingWebView extends WebView {
    ValueCallback<String> answer;
    VisualStateCallback paint;

    RecordingWebView(Context context) {
      super(context);
    }

    @Override
    public void evaluateJavascript(String script, ValueCallback<String> callback) {
      answer = callback;
    }

    @Override
    public void postVisualStateCallback(long requestId, VisualStateCallback callback) {
      paint = callback;
    }

    void answer(String value) {
      ValueCallback<String> callback = answer;
      answer = null;
      assertNotNull(callback);
      callback.onReceiveValue(value);
    }
  }
}
