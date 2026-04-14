package com.stash.stashnative;

import static org.junit.Assert.*;
import org.junit.Test;

/**
 * Tests for StashWebViewUtils.normalizeExternalPaymentUrl().
 * Tests that depend on android.net.Uri.parse() returning real values
 * require instrumentation tests (androidTest) since Uri is stubbed in local JVM.
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

  // NOTE: Tests for valid http/https URLs require android.net.Uri.parse() which
  // returns null in local JVM tests. Those belong in androidTest/ (instrumented).
}
