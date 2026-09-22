package com.stash.stashnative;

import static org.junit.Assert.*;
import org.junit.Test;

/** Exercises the real Android URI parser under Robolectric. */
@org.junit.runner.RunWith(org.robolectric.RobolectricTestRunner.class)
@org.robolectric.annotation.Config(sdk = 28)
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
  public void httpUrlAppendsThemeWithQuestionMark() {
    String result = StashWebViewUtils.appendThemeQueryParameter("https://pay.stash.gg", true);
    assertNotNull(result);
    assertTrue(result.contains("theme=dark"));
    assertTrue(result.contains("?theme="));
  }

  @Test
  public void httpUrlAppendsLightTheme() {
    String result = StashWebViewUtils.appendThemeQueryParameter("https://pay.stash.gg", false);
    assertNotNull(result);
    assertTrue(result.contains("theme=light"));
  }

  @Test
  public void queryUsesAmpersand() {
    String result = StashWebViewUtils.appendThemeQueryParameter(
        "https://pay.stash.gg?token=abc", true);
    assertNotNull(result);
    assertTrue(result.contains("&theme=dark"));
    assertTrue(result.contains("token=abc"));
  }

  @Test
  public void dedupExistingThemeYieldsSingleParam() {
    String result = StashWebViewUtils.appendThemeQueryParameter(
        "https://pay.stash.gg?theme=light&token=abc", true);
    assertNotNull(result);
    // exactly one theme= occurrence, and it is the new value
    int first = result.indexOf("theme=");
    assertTrue(first >= 0);
    assertEquals(-1, result.indexOf("theme=", first + 1));
    assertTrue(result.contains("theme=dark"));
    assertFalse(result.contains("theme=light"));
    assertTrue(result.contains("token=abc"));
  }

  @Test
  public void themePrefixParamSurvives() {
    String result = StashWebViewUtils.appendThemeQueryParameter(
        "https://pay.stash.gg?themeX=1", true);
    assertNotNull(result);
    assertTrue(result.contains("themeX=1"));
    assertTrue(result.contains("theme=dark"));
  }

  @Test
  public void fragmentPreservedAndThemedBeforeHash() {
    String result = StashWebViewUtils.appendThemeQueryParameter(
        "https://pay.stash.gg?token=abc#section", true);
    assertNotNull(result);
    assertTrue(result.endsWith("#section"));
    assertTrue(result.indexOf("theme=dark") < result.indexOf("#section"));
  }
  @Test
  public void signedQueryEncodingAndFragmentSurviveRetheming() {
    String url = "https://example.invalid/?token=a%2Bb%26c&theme=light&theme=light#section";
    assertEquals("https://example.invalid/?token=a%2Bb%26c&theme=dark#section",
        StashWebViewUtils.appendThemeQueryParameter(url, true));
  }
}
