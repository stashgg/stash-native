package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.net.Uri;
import android.webkit.WebResourceRequest;
import android.webkit.WebView;
import android.webkit.WebViewClient;
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

/** Real checkout error handling, including the legacy main-resource callback. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = {21, 22, 28})
@LooperMode(LooperMode.Mode.PAUSED)
@SuppressWarnings("deprecation")
public class WebViewFailureTest {
  private StashCheckoutActivity activity;
  private WebView web;
  private WebViewClient client;

  @Before public void prepare() {
    activity = Robolectric.buildActivity(StashCheckoutActivity.class).get();
    activity.url = "https://unavailable.invalid/checkout";
    activity.cardContainer = new StashSheetLayout(activity, 24f);
    StashCheckoutWebViewSupport.addWebView(activity);
    web = activity.webView;
    client = Shadows.shadowOf(web).getWebViewClient();
    client.onPageStarted(web, activity.url, null);
  }

  @After public void cleanup() {
    StashCheckoutWebViewSupport.cancelLoadTimers(activity);
    StashCheckoutWebViewSupport.cancelLoadingRevealAnimation(activity);
    activity.contentRevealSupport.dispose();
    web.destroy();
  }

  private long networkErrors() {
    return Shadows.shadowOf(activity.getApplication()).getBroadcastIntents().stream()
        .filter(intent -> CardConstants.BROADCAST_CHECKOUT_NETWORK_ERROR.equals(intent.getAction()))
        .count();
  }

  private void finishErrorDocument() {
    Shadows.shadowOf(web).getWebChromeClient().onProgressChanged(web, 100);
    client.onPageFinished(web, activity.url);
    assertTrue(activity.isFinishing());
    assertEquals(1, networkErrors());
    assertFalse(activity.initialPageLoadComplete);
    assertFalse(activity.mainFrameNavigationCommitted);
    assertFalse(activity.pageLoadedCallbackSent);
  }

  @Test public void legacyMainResourceFailureCannotRevealChromiumErrorPage() {
    client.onReceivedError(web, WebViewClient.ERROR_HOST_LOOKUP, "Host lookup failed", activity.url);
    client.onReceivedError(web, WebViewClient.ERROR_HOST_LOOKUP, "Duplicate failure", activity.url);
    finishErrorDocument();
  }

  @Test @Config(sdk = 28)
  public void modernAndLegacyDeliveryReportOneNetworkFailure() {
    client.onReceivedError(web, request(true), null);
    client.onReceivedError(web, WebViewClient.ERROR_CONNECT, "Duplicate failure", activity.url);
    finishErrorDocument();
  }

  @Test @Config(sdk = 28)
  public void failedSubresourceDoesNotCloseTheCheckout() {
    client.onReceivedError(web, request(false), null);
    assertEquals(0, networkErrors());
    assertFalse(activity.mainFrameErrorReceived);
    assertFalse(activity.isFinishing());
  }

  @Test public void failedNavigationAfterLoadClosesWithoutInitialLoadErrorCallback() {
    activity.initialPageLoadComplete = true;
    client.onReceivedError(web, WebViewClient.ERROR_TIMEOUT, "Timed out", activity.url);
    assertTrue(activity.isFinishing());
    assertEquals(0, networkErrors());
  }

  @Test public void cancelledNavigationAfterLoadKeepsCheckoutOpen() {
    activity.initialPageLoadComplete = true;
    client.onReceivedError(web, WebViewClient.ERROR_UNKNOWN, "net::ERR_ABORTED", activity.url);
    assertFalse(activity.isFinishing());
    assertFalse(activity.mainFrameErrorReceived);
    assertEquals(0, networkErrors());
  }

  @Test public void retiredWebViewErrorCannotCloseItsReplacement() {
    WebView retired = new WebView(activity);
    client.onReceivedError(retired, WebViewClient.ERROR_CONNECT, "Connection lost", activity.url);
    assertFalse(activity.isFinishing());
    assertEquals(0, networkErrors());
    retired.destroy();
  }

  private WebResourceRequest request(boolean mainFrame) {
    return new WebResourceRequest() {
      @Override public Uri getUrl() { return Uri.parse(activity.url); }
      @Override public boolean isForMainFrame() { return mainFrame; }
      @Override public boolean isRedirect() { return false; }
      @Override public boolean hasGesture() { return false; }
      @Override public String getMethod() { return "GET"; }
      @Override public Map<String, String> getRequestHeaders() { return Collections.emptyMap(); }
    };
  }

}
