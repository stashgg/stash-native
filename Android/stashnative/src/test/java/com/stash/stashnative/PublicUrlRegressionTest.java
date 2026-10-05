package com.stash.stashnative;

import static org.junit.Assert.*;

import android.app.Activity;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.Uri;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowLooper;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public class PublicUrlRegressionTest {
  private StashNativeCardPlugin plugin;
  private Activity host;

  @Before public void prepare() {
    plugin = StashNativeCardPlugin.getInstance();
    plugin.resetPresentationState();
    host = Robolectric.buildActivity(Activity.class).setup().get();
    Shadows.shadowOf(host.getApplication()).grantPermissions(
        host.getPackageName() + ".permission.STASH_NATIVE_INTERNAL");
    StashNativeCard.getInstance().setActivity(host);
  }

  @After public void finish() {
    plugin.setListener(null);
    plugin.resetPresentationState();
    host.finish();
    ShadowLooper.idleMainLooper();
  }

  private Uri browserDestination(String input) {
    StashNativeCard.getInstance().openBrowser(input);
    ShadowLooper.idleMainLooper();
    Intent intent = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull("Expected browser intent", intent);
    String proxy = intent.getStringExtra(StashNativeBrowserProxyActivity.EXTRA_URL);
    return Uri.parse(proxy == null ? intent.getDataString() : proxy);
  }

  @Test public void browserPreservesMixedCaseHttpsHost() {
    Uri destination = browserDestination(" HTTPS://example.invalid/checkout ");
    assertEquals("example.invalid", destination.getHost());
    IntentFilter browser = new IntentFilter(Intent.ACTION_VIEW);
    browser.addDataScheme("https");
    assertTrue("HTTPS input must match a browser's scheme filter",
        browser.matchData(null, destination.getScheme(), destination) >= 0);
  }

  @Test public void browserPreservesQueryFragmentAndHostPort() {
    Uri uri = browserDestination("example.invalid:8443/pay?token=a%2Bb%26c#checkout");
    assertEquals("https", uri.getScheme());
    assertEquals("example.invalid", uri.getHost());
    assertEquals(8443, uri.getPort());
    assertEquals("a+b&c", uri.getQueryParameter("token"));
    assertEquals("checkout", uri.getFragment());
    assertEquals(1, uri.getQueryParameters("theme").size());
  }

  @Test public void ordinaryBrowserDestinationStillWorks() {
    assertEquals("example.invalid", browserDestination("https://example.invalid/checkout").getHost());
  }

  @Test public void browserRejectsUnsupportedSchemes() {
    for (String url : new String[] {"mailto:fixture@example.invalid", "javascript:alert(1)",
        "data:text/html,fixture", "file:///fixture", "https://", " "}) {
      StashNativeCard.getInstance().openBrowser(url);
      ShadowLooper.idleMainLooper();
      assertNull(Shadows.shadowOf(host).getNextStartedActivity());
    }
  }

  @Test public void cardPreservesMixedCaseHttpsHost() {
    StashNativeCard.getInstance().openCard("HTTPS://example.invalid/checkout", null);
    Intent intent = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(intent);
    assertEquals("example.invalid", Uri.parse(intent.getStringExtra(CardConstants.INTENT_EXTRA_URL)).getHost());
  }

  @Test public void modalNormalizesBareHostAndPreservesQuery() {
    StashNativeCard.getInstance().openModal("example.invalid:8443/pay?token=a%2Bb#checkout", null);
    Intent intent = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(intent);
    Uri uri = Uri.parse(intent.getStringExtra(CardConstants.INTENT_EXTRA_URL));
    assertEquals("example.invalid", uri.getHost());
    assertEquals(8443, uri.getPort());
    assertEquals("a+b", uri.getQueryParameter("token"));
    assertEquals("checkout", uri.getFragment());
  }

  @Test public void popupPreservesMixedCaseHttpsHost() {
    StashNativeCard.getInstance().openPopup("HTTPS://example.invalid/checkout");
    assertNotNull(plugin.webView);
    assertEquals("example.invalid", Uri.parse(Shadows.shadowOf(plugin.webView).getLastLoadedUrl()).getHost());
  }

  @Test public void invalidCheckoutUrlsDoNotOccupyPresentationState() {
    StashNativeCard sdk = StashNativeCard.getInstance();
    sdk.openCard("mailto:fixture@example.invalid", null);
    assertFalse(sdk.isCurrentlyPresented());
    sdk.openModal("data:text/html,fixture", null);
    assertFalse(sdk.isCurrentlyPresented());
    sdk.openPopup("javascript:alert(1)");
    assertFalse(sdk.isCurrentlyPresented());
    assertNull(plugin.currentDialog);
    assertNull(Shadows.shadowOf(host).getNextStartedActivity());
    sdk.openCard("https://example.invalid", null);
    assertNotNull(Shadows.shadowOf(host).getNextStartedActivity());
  }
}
