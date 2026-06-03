package com.stash.stashnative;

import static org.junit.Assert.*;
import org.junit.Test;

/**
 * Tests for StashWebViewUtils.normalizeExternalPaymentUrl().
 * Cases here cover inputs that do not call android.net.Uri.parse().
 */
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

  // Valid http/https URL cases live in UrlAndColorRobolectricTest (Robolectric, real Uri).
}
