package com.stash.stashnative;

import static org.junit.Assert.*;
import org.junit.Test;

/**
 * Tests for StashWebViewUtils.appendThemeQueryParameter().
 * Uri-dependent assertions run under Robolectric in UrlAndColorRobolectricTest (real android.net.Uri).
 */
public class ThemeParameterTest {

  @Test
  public void nullUrlReturnsNull() {
    assertNull(StashWebViewUtils.appendThemeQueryParameter(null, false));
  }

  @Test
  public void emptyUrlReturnsEmpty() {
    assertEquals("", StashWebViewUtils.appendThemeQueryParameter("", true));
  }

  @Test
  public void fallbackPathAppendsThemeWithQuestionMark() {
    // Uri.parse returns null in the JVM; this exercises the catch-block string fallback path.
    String result = StashWebViewUtils.appendThemeQueryParameter("https://pay.stash.gg", true);
    assertNotNull(result);
    assertTrue(result.contains("theme=dark"));
    assertTrue(result.contains("?theme="));
  }

  @Test
  public void fallbackPathAppendsLightTheme() {
    String result = StashWebViewUtils.appendThemeQueryParameter("https://pay.stash.gg", false);
    assertNotNull(result);
    assertTrue(result.contains("theme=light"));
  }

  @Test
  public void fallbackPathUsesAmpersandWhenQueryExists() {
    String result = StashWebViewUtils.appendThemeQueryParameter(
        "https://pay.stash.gg?token=abc", true);
    assertNotNull(result);
    assertTrue(result.contains("&theme=dark"));
    assertTrue(result.contains("token=abc"));
  }
}
