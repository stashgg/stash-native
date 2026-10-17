package com.stash.stashnative;

import static org.junit.Assert.*;
import org.junit.Test;

/** Exercises the real Android URI parser under Robolectric. */
@org.junit.runner.RunWith(org.robolectric.RobolectricTestRunner.class)
@org.robolectric.annotation.Config(sdk = 28)
public class UrlNormalizationTest {

  @Test
  public void nullReturnsNull() {
    assertNull(StashWebViewUtils.normalizeExternalPaymentUrl(null));
  }

  @Test
  public void emptyReturnsNull() {
    assertNull(StashWebViewUtils.normalizeExternalPaymentUrl(""));
    assertNull(StashWebViewUtils.normalizeExternalPaymentUrl("   "));
  }

  @Test
  public void javascriptSchemeBlocked() {
    assertNull(StashWebViewUtils.normalizeExternalPaymentUrl("javascript:alert(1)"));
    assertNull(StashWebViewUtils.normalizeExternalPaymentUrl("JAVASCRIPT:void(0)"));
  }

  @Test
  public void dataSchemeBlocked() {
    assertNull(StashWebViewUtils.normalizeExternalPaymentUrl("data:text/html,<h1>x</h1>"));
  }

  @Test
  public void fileSchemeBlocked() {
    assertNull(StashWebViewUtils.normalizeExternalPaymentUrl("file:///etc/passwd"));
  }

  @Test
  public void httpUrlsAndBareHostsNormalizeWithoutAcceptingOtherSchemes() {
    assertEquals("https://example.invalid/path", StashWebViewUtils.normalizeExternalPaymentUrl(" example.invalid/path "));
    assertEquals("https://example.invalid/path", StashWebViewUtils.normalizeExternalPaymentUrl("HTTPS://example.invalid/path"));
    assertEquals("https://localhost:8080/a", StashWebViewUtils.normalizeExternalPaymentUrl("localhost:8080/a"));
    assertNull(StashWebViewUtils.normalizeExternalPaymentUrl("mailto:a@example.invalid"));
    assertNull(StashWebViewUtils.normalizeExternalPaymentUrl("ftp://example.invalid"));
    assertNull(StashWebViewUtils.normalizeExternalPaymentUrl("https://"));
  }

  @Test
  public void sharedAcceptanceRuleCanonicalizesSchemeAndRejectsOtherInput() {
    assertEquals("https://Example.invalid/pay?x=1#f",
        StashWebViewUtils.parseAcceptedHttpUri(" HTTPS://Example.invalid/pay?x=1#f ").toString());
    assertEquals("http", StashWebViewUtils.parseAcceptedHttpUri("HTTP://example.invalid").getScheme());
    assertNull(StashWebViewUtils.parseAcceptedHttpUri(null));
    assertNull(StashWebViewUtils.parseAcceptedHttpUri("  "));
    assertNull(StashWebViewUtils.parseAcceptedHttpUri("https://"));
    assertNull(StashWebViewUtils.parseAcceptedHttpUri("example.invalid/path"));
    assertNull(StashWebViewUtils.parseAcceptedHttpUri("ftp://example.invalid"));
    assertNull(StashWebViewUtils.parseAcceptedHttpUri("javascript:alert(1)"));
    assertNull(StashWebViewUtils.parseAcceptedHttpUri("file:///etc/passwd"));
  }

  @Test
  public void launcherOpensUppercaseSchemeAsCanonicalHttps() {
    android.app.Activity host = org.robolectric.Robolectric.buildActivity(
        android.app.Activity.class).setup().get();
    try {
      StashUrlLauncher.openExternalUrl(host, "HTTPS://example.invalid/pay", 0);
      android.content.Intent launched =
          org.robolectric.Shadows.shadowOf(host).getNextStartedActivity();
      assertNotNull(launched);
      assertEquals("https", launched.getData().getScheme());
      assertEquals("https://example.invalid/pay", launched.getDataString());
      assertEquals(StashUrlLauncher.OPEN_EXTERNAL_ACTION_VIEW,
          StashUrlLauncher.openExternalUrl(host, "FTP://example.invalid/pay", 0));
      assertNull(org.robolectric.Shadows.shadowOf(host).getNextStartedActivity());
    } finally {
      host.finish();
    }
  }
}
