package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.content.Intent;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.LooperMode;
import org.robolectric.shadows.ShadowLooper;

/** The main-frame bridge token gates every StashAndroid call that has no token of its own. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
@LooperMode(LooperMode.Mode.PAUSED)
public class BridgeTokenTest {
  private static final String[] TOKENED_WRAPPERS = {
      "triggerHaptic", "onPaymentSuccess", "onPaymentFailure", "onPurchaseProcessing",
      "onProcessingCompleted", "expand", "collapse", "openExternalBrowser", "openLink",
      "requestCloseFromPage"
  };

  private StashCardActivity activity;
  private StashCheckoutJsInterface bridge;

  @Before public void prepare() {
    StashNativePlugin plugin = StashNativePlugin.getInstance();
    plugin.resetPresentationState();
    plugin.isCurrentlyPresented = true;
    Intent intent = new Intent().putExtra(StashCheckoutBridge.EXTRA_SESSION_ID,
        plugin.presentationSessionId);
    activity = Robolectric.buildActivity(StashCardActivity.class, intent).get();
    activity.options = StashPresentationOptions.card(null);
    bridge = new StashCheckoutJsInterface(activity);
  }

  @After public void cleanup() {
    StashCheckoutLoadingSupport.cancelLoadTimers(activity);
    StashCheckoutLoadingSupport.cancelLoadingRevealAnimation(activity);
    if (activity.contentRevealSupport != null) {
      activity.contentRevealSupport.dispose();
    }
    if (activity.webView != null) {
      activity.webView.destroy();
    }
    StashNativePlugin.getInstance().resetPresentationState();
  }

  private int broadcasts() {
    return Shadows.shadowOf(activity.getApplication()).getBroadcastIntents().size();
  }

  @Test public void wrongOrMissingTokenIsIgnoredAndCurrentTokenDispatches() {
    String token = activity.issueBridgeDocumentToken();
    bridge.onPurchaseProcessing("forged");
    bridge.onPurchaseProcessing(null);
    bridge.onPurchaseProcessing("");
    assertFalse(activity.isPurchaseProcessing);
    bridge.onPurchaseProcessing(token);
    assertTrue(activity.isPurchaseProcessing);
    bridge.onProcessingCompleted("forged");
    assertTrue(activity.isPurchaseProcessing);
    bridge.onProcessingCompleted(token);
    assertFalse(activity.isPurchaseProcessing);
  }

  @Test public void forgedPaymentCloseAndBrowserCallsDoNothing() {
    activity.issueBridgeDocumentToken();
    int before = broadcasts();
    bridge.onPaymentSuccess("forged", "order");
    bridge.onPaymentFailure("forged");
    bridge.requestCloseFromPage("forged");
    bridge.openExternalBrowser("forged", "https://example.invalid/pay");
    bridge.openLink("forged", "https://example.invalid/terms");
    bridge.expand("forged");
    ShadowLooper.idleMainLooper();
    assertEquals(before, broadcasts());
    assertFalse(activity.isFinishing());
    assertFalse(activity.callbackSent);
    assertNull(Shadows.shadowOf(activity).getNextStartedActivity());
  }

  @Test public void noTokenIssuedRejectsEveryCall() {
    assertNull(activity.bridgeDocumentToken);
    bridge.onPurchaseProcessing(null);
    bridge.onPurchaseProcessing("null");
    assertFalse(activity.isPurchaseProcessing);
  }

  @Test public void aNewDocumentRetiresTheEarlierToken() {
    String first = activity.issueBridgeDocumentToken();
    String second = activity.issueBridgeDocumentToken();
    assertNotEquals(first, second);
    bridge.onPurchaseProcessing(first);
    assertFalse(activity.isPurchaseProcessing);
    bridge.onPurchaseProcessing(second);
    assertTrue(activity.isPurchaseProcessing);
  }

  @Test public void injectedScriptBindsEveryWrapperToTheDocumentToken() {
    activity.url = "https://example.invalid/checkout";
    activity.cardContainer = new StashSheetLayout(activity, 24f);
    StashCheckoutWebViewSupport.addWebView(activity);
    WebView web = activity.webView;
    assertNotNull(web);
    String token = activity.bridgeDocumentToken;
    assertNotNull(token);
    StashCheckoutWebViewSupport.injectSDK(activity, web);
    assertEquals(token, activity.bridgeDocumentToken);
    String script = Shadows.shadowOf(web).getLastEvaluatedJavascript();
    assertTrue(script.contains("var token = '" + token + "';"));
    assertFalse(script.contains(StashWebViewUtils.JS_SDK_TOKEN_PLACEHOLDER));
    for (String method : TOKENED_WRAPPERS) {
      assertTrue(method, script.contains(StashWebViewUtils.JS_INTERFACE_NAME + "." + method + "(token"));
    }
    assertFalse(script.contains("setContentHeight(token"));
    assertFalse(script.contains("getTelemetry(token"));
    // A new main-frame navigation issues a new token and injects a script bound to it.
    WebViewClient client = Shadows.shadowOf(web).getWebViewClient();
    client.onPageStarted(web, activity.url, null);
    String rotated = activity.bridgeDocumentToken;
    assertNotEquals(token, rotated);
    assertTrue(Shadows.shadowOf(web).getLastEvaluatedJavascript()
        .contains("var token = '" + rotated + "';"));
    bridge.onPurchaseProcessing(token);
    assertFalse(activity.isPurchaseProcessing);
    bridge.onPurchaseProcessing(rotated);
    assertTrue(activity.isPurchaseProcessing);
  }
}
