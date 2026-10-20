package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertTrue;

import android.net.Uri;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import java.time.Duration;
import java.util.Collections;
import java.util.Map;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.LooperMode;

/** The stall retry replaces the first attempt; that attempt's cancellation is not the retry's. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = {21, 28})
@LooperMode(LooperMode.Mode.PAUSED)
@SuppressWarnings("deprecation")
public class InitialLoadRetryTest {
  private StashCardActivity activity;
  private WebView web;
  private WebViewClient client;
  private String first;
  private String retry;

  @Before public void prepare() {
    activity = Robolectric.buildActivity(StashCardActivity.class).get();
    activity.url = "https://stalled.invalid";
    activity.cardContainer = new StashSheetLayout(activity, 24f);
    StashCheckoutWebViewSupport.addWebView(activity);
    web = activity.webView;
    client = Shadows.shadowOf(web).getWebViewClient();
    first = activity.webViewCommittedReloadUrl;
    // The first attempt gets no response, so the stall retry replaces it.
    StashCheckoutLoadingSupport.scheduleInitialLoadTimers(activity);
    Shadows.shadowOf(android.os.Looper.getMainLooper())
        .idleFor(Duration.ofMillis(CardConstants.WEBVIEW_RETRY_TIMEOUT_MS));
    retry = Shadows.shadowOf(web).getLastLoadedUrl();
    assertTrue(retry.startsWith(first + "&_stash_nc="));
  }

  @After public void cleanup() {
    StashCheckoutLoadingSupport.cancelLoadTimers(activity);
    StashCheckoutLoadingSupport.cancelLoadingRevealAnimation(activity);
    activity.contentRevealSupport.dispose();
    web.destroy();
  }

  private long networkErrors() {
    return Shadows.shadowOf(activity.getApplication()).getBroadcastIntents().stream()
        .filter(intent -> CardConstants.BROADCAST_CHECKOUT_NETWORK_ERROR.equals(intent.getAction()))
        .count();
  }

  /** WebView reports the root path of the first attempt's URL as "/". */
  private String reported(String url) {
    return url.replace("https://stalled.invalid?", "https://stalled.invalid/?");
  }

  @Test public void cancelledFirstAttemptCannotFailTheRetry() {
    client.onReceivedError(web, WebViewClient.ERROR_UNKNOWN, "net::ERR_ABORTED", first);
    client.onReceivedError(web, WebViewClient.ERROR_UNKNOWN, "net::ERR_ABORTED", reported(first));
    assertFalse(activity.mainFrameErrorReceived);
    assertFalse(activity.isFinishing());
    assertEquals(0, networkErrors());
    client.onReceivedError(web, WebViewClient.ERROR_CONNECT, "Connection failed", retry);
    assertTrue(activity.isFinishing());
    assertEquals(1, networkErrors());
  }

  @Test @Config(sdk = 28)
  public void cancelledFirstAttemptCannotFailTheRetryThroughModernCallbacks() {
    client.onReceivedError(web, request(reported(first)), null);
    client.onReceivedHttpError(web, request(first), new WebResourceResponse(
        "text/html", "utf-8", 502, "Bad Gateway", null, null));
    assertEquals(0, networkErrors());
    client.onReceivedError(web, request(retry), null);
    assertEquals(1, networkErrors());
  }

  @Test @Config(sdk = 28)
  public void cancelledFirstAttemptCannotCompleteTheInitialLoad() {
    client.onPageFinished(web, reported(first));
    assertFalse(activity.initialPageLoadComplete);
    // The retry's own server failure must still end checkout as a network error.
    client.onReceivedHttpError(web, request(retry), new WebResourceResponse(
        "text/html", "utf-8", 500, "Server Error", null, null));
    assertTrue(activity.isFinishing());
    assertEquals(1, networkErrors());
  }

  @Test public void retryEventsCountIncludingARedirectBackToTheFirstUrl() {
    client.onPageStarted(web, reported(first), null);
    client.onPageFinished(web, reported(first));
    assertTrue(activity.initialPageLoadComplete);
    assertEquals(0, networkErrors());
  }

  @Test public void retryFinishCompletesTheInitialLoad() {
    client.onPageStarted(web, retry, null);
    client.onPageFinished(web, retry);
    assertTrue(activity.initialPageLoadComplete);
    assertNotEquals(first, retry);
  }

  private static WebResourceRequest request(String url) {
    return new WebResourceRequest() {
      @Override public Uri getUrl() { return Uri.parse(url); }
      @Override public boolean isForMainFrame() { return true; }
      @Override public boolean isRedirect() { return false; }
      @Override public boolean hasGesture() { return false; }
      @Override public String getMethod() { return "GET"; }
      @Override public Map<String, String> getRequestHeaders() { return Collections.emptyMap(); }
    };
  }
}
