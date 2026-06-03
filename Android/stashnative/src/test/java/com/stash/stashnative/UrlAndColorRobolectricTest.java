package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

/**
 * Exercises the real android.net.Uri and android.graphics.Color code paths under Robolectric.
 */
@RunWith(RobolectricTestRunner.class)
@Config(manifest = Config.NONE)
public class UrlAndColorRobolectricTest {

  // --- normalizeExternalPaymentUrl (real Uri) ---

  @Test
  public void httpsUrlPassesThrough() {
    assertEquals("https://pay.example.com/checkout",
        StashWebViewUtils.normalizeExternalPaymentUrl("https://pay.example.com/checkout"));
  }

  @Test
  public void schemelessUrlGetsHttpsPrepended() {
    assertEquals("https://pay.example.com",
        StashWebViewUtils.normalizeExternalPaymentUrl("pay.example.com"));
  }

  @Test
  public void httpIsUpgradedToHttps() {
    String out = StashWebViewUtils.normalizeExternalPaymentUrl("http://pay.example.com/x");
    assertNotNull(out);
    assertTrue("expected https upgrade, got " + out, out.startsWith("https://"));
  }

  @Test
  public void uppercaseHttpSchemeIsHandled() {
    String out = StashWebViewUtils.normalizeExternalPaymentUrl("HTTP://pay.example.com");
    assertNotNull(out);
    assertTrue("expected https upgrade, got " + out, out.toLowerCase().startsWith("https://"));
  }

  @Test
  public void disallowedSchemesRejected() {
    assertNull(StashWebViewUtils.normalizeExternalPaymentUrl("javascript:alert(1)"));
    assertNull(StashWebViewUtils.normalizeExternalPaymentUrl("file:///etc/passwd"));
    assertNull(StashWebViewUtils.normalizeExternalPaymentUrl("data:text/html,<x>"));
  }

  @Test
  public void blankRejected() {
    assertNull(StashWebViewUtils.normalizeExternalPaymentUrl("   "));
    assertNull(StashWebViewUtils.normalizeExternalPaymentUrl(null));
  }

  // --- appendThemeQueryParameter (real Uri) ---

  @Test
  public void themeAppendedExactlyOnce() {
    String dark = StashWebViewUtils.appendThemeQueryParameter("https://x.example.com/p", true);
    assertTrue(dark.contains("theme=dark"));
    assertEquals(1, countOccurrences(dark, "theme="));

    String light = StashWebViewUtils.appendThemeQueryParameter("https://x.example.com/p?a=b", false);
    assertTrue(light.contains("theme=light"));
    assertEquals(1, countOccurrences(light, "theme="));
  }

  // --- StashBackgroundColorUtils.parseSolidColorOrNull (real Color) ---

  @Test
  public void parsesValidHexShapes() {
    assertNotNull(StashBackgroundColorUtils.parseSolidColorOrNull("#abc"));
    assertNotNull(StashBackgroundColorUtils.parseSolidColorOrNull("#1e1e1e"));
    assertNotNull(StashBackgroundColorUtils.parseSolidColorOrNull("#ff1e1e1e"));
  }

  @Test
  public void rejectsInvalidHex() {
    assertNull(StashBackgroundColorUtils.parseSolidColorOrNull("1e1e1e")); // missing '#'
    assertNull(StashBackgroundColorUtils.parseSolidColorOrNull("#ff"));    // wrong length
    assertNull(StashBackgroundColorUtils.parseSolidColorOrNull("#ggg"));   // non-hex
    assertNull(StashBackgroundColorUtils.parseSolidColorOrNull(null));
  }

  @Test
  public void rrggbbForcesOpaqueAlpha() {
    Integer c = StashBackgroundColorUtils.parseSolidColorOrNull("#1e1e1e");
    assertNotNull(c);
    assertEquals(0xFF, (c >> 24) & 0xFF);
  }

  private static int countOccurrences(String haystack, String needle) {
    int count = 0;
    int idx = 0;
    while ((idx = haystack.indexOf(needle, idx)) != -1) {
      count++;
      idx += needle.length();
    }
    return count;
  }
}
