package com.stash.stashnative;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

/** Pure math for the expanded phone-sheet height clamp. */
public class CardGeometryTest {

  @Test
  public void capsRawHeightToContentBox() {
    // API 35+ edge-to-edge: heightPixels includes the bars, raw overflows the content box.
    assertEquals(2211, StashNativeCardPortraitActivity.clampExpandedHeight(2280, 2211));
  }

  @Test
  public void keepsRawHeightWhenItFits() {
    // heightPixels excludes the nav bar: 95% of it fits inside the content box untouched.
    assertEquals(2160, StashNativeCardPortraitActivity.clampExpandedHeight(2160, 2211));
  }

  @Test
  public void fallsBackUnclampedWhenContentBoxUnknown() {
    assertEquals(2160, StashNativeCardPortraitActivity.clampExpandedHeight(2160, 0));
    assertEquals(2160, StashNativeCardPortraitActivity.clampExpandedHeight(2160, -1));
  }

  @Test
  public void equalHeightsPassThrough() {
    assertEquals(2085, StashNativeCardPortraitActivity.clampExpandedHeight(2085, 2085));
  }
}
