package com.stash.stashnative;

import static org.junit.Assert.*;
import org.junit.Test;

/**
 * Tests for StashWebViewUtils.appendThemeQueryParameter().
 * Uri-dependent assertions require instrumented tests (androidTest).
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
    // Uri.parse returns null in JVM, so the catch block runs the string fallback path.
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
