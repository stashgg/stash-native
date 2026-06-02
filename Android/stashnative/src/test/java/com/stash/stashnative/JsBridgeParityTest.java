package com.stash.stashnative;

import static org.junit.Assert.assertTrue;

import org.junit.Test;

/**
 * Guards the window.stash_sdk surface in the injected bridge script. The same surface must be
 * mirrored on iOS (stashSDKScript in StashNativeCard.m) and in docs/stash-sdk-js.md.
 */
public class JsBridgeParityTest {

  private static final String[] EXPECTED_MEMBERS = {
    "window.stash_sdk.onPaymentSuccess",
    "window.stash_sdk.onPaymentFailure",
    "window.stash_sdk.onPurchaseProcessing",
    "window.stash_sdk.setPaymentChannel",
    "window.stash_sdk.expand",
    "window.stash_sdk.collapse",
    "window.stash_sdk.openExternalBrowser",
    "window.close",
  };

  @Test
  public void scriptExposesEveryBridgeMember() {
    String script = StashWebViewUtils.JS_SDK_SCRIPT;
    for (String member : EXPECTED_MEMBERS) {
      assertTrue("JS_SDK_SCRIPT must define " + member, script.contains(member));
    }
  }

  @Test
  public void scriptCallsThroughTheNamedInterface() {
    assertTrue(StashWebViewUtils.JS_SDK_SCRIPT.contains(StashWebViewUtils.JS_INTERFACE_NAME));
    assertTrue("StashAndroid".equals(StashWebViewUtils.JS_INTERFACE_NAME));
  }
}
