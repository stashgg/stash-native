package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/** Pure-string checks; no android.Uri (stubbed in local JVM). */
public class DeeplinkClassificationTest {

  @Test
  public void webSchemesStayInWebView() {
    assertTrue(StashWebViewUtils.isWebScheme("https://checkout.stash.gg/pay/1"));
    assertTrue(StashWebViewUtils.isWebScheme("http://example.com"));
    assertTrue(StashWebViewUtils.isWebScheme("about:blank"));
    assertTrue(StashWebViewUtils.isWebScheme("javascript:void(0)"));
    assertFalse(StashWebViewUtils.isWebScheme("stashdemo://stash-pay/success"));
    assertFalse(StashWebViewUtils.isWebScheme("market://details?id=x"));
    assertFalse(StashWebViewUtils.isWebScheme(null));
  }

  @Test
  public void stashPayPathsClassifyRegardlessOfScheme() {
    assertEquals(StashWebViewUtils.DEEPLINK_RESULT_SUCCESS,
        StashWebViewUtils.classifyDeeplinkResult("stashdemo://stash-pay/success"));
    assertEquals(StashWebViewUtils.DEEPLINK_RESULT_SUCCESS,
        StashWebViewUtils.classifyDeeplinkResult("myapp://x/STASH-PAY/SUCCESS?y=1"));
    assertEquals(StashWebViewUtils.DEEPLINK_RESULT_FAILURE,
        StashWebViewUtils.classifyDeeplinkResult("bank://return/stash-pay/failure"));
    assertEquals(StashWebViewUtils.DEEPLINK_RESULT_CANCEL,
        StashWebViewUtils.classifyDeeplinkResult("app://stash-pay/cancel"));
  }

  @Test
  public void otherDeeplinksAreNotResults() {
    assertEquals(StashWebViewUtils.DEEPLINK_RESULT_NONE,
        StashWebViewUtils.classifyDeeplinkResult("stashdemo://misc/passthrough"));
    assertEquals(StashWebViewUtils.DEEPLINK_RESULT_NONE,
        StashWebViewUtils.classifyDeeplinkResult("stashdemo://stash-pay/failed"));
    assertEquals(StashWebViewUtils.DEEPLINK_RESULT_NONE,
        StashWebViewUtils.classifyDeeplinkResult(null));
  }
}
