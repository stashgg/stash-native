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
}
