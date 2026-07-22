package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;

/** Robolectric: android.graphics.Color is shadowed, so the real parse paths run. */
@RunWith(RobolectricTestRunner.class)
public class StashBackgroundColorUtilsTest {

  @Test
  public void normalizeHex() {
    assertEquals("#1E1E1E", StashBackgroundColorUtils.normalizeHexOrNull("  #1E1E1E "));
    assertNull(StashBackgroundColorUtils.normalizeHexOrNull(null));
    assertNull(StashBackgroundColorUtils.normalizeHexOrNull("   "));
  }

  @Test
  public void parseSolidColors() {
    assertEquals(Integer.valueOf(0xFF112233), StashBackgroundColorUtils.parseSolidColorOrNull("#112233"));
    // #RGB expands each nibble
    assertEquals(Integer.valueOf(0xFF112233), StashBackgroundColorUtils.parseSolidColorOrNull("#123"));
    // #AARRGGBB keeps the parsed alpha (platform parity with iOS)
    assertEquals(Integer.valueOf(0x80112233), StashBackgroundColorUtils.parseSolidColorOrNull("#80112233"));
    assertNull(StashBackgroundColorUtils.parseSolidColorOrNull("112233"));
    assertNull(StashBackgroundColorUtils.parseSolidColorOrNull("#12345"));
    assertNull(StashBackgroundColorUtils.parseSolidColorOrNull("#zzzzzz"));
  }

  @Test
  public void luminanceThreshold() {
    assertTrue(StashBackgroundColorUtils.isDarkBackground(0xFF000000));
    assertTrue(StashBackgroundColorUtils.isDarkBackground(0xFF1E1E1E));
    assertFalse(StashBackgroundColorUtils.isDarkBackground(0xFFFFFFFF));
    assertFalse(StashBackgroundColorUtils.isDarkBackground(0xFFF7F9F4));
  }
}
