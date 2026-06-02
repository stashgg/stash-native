package com.stash.stashnative;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

/** Pins the [0.1,1.0] ratio clamp and the popup-multiplier degenerate-input guard. */
public class ClampTest {

  @Test
  public void clampRatioKeepsInRange() {
    assertEquals(0.5f, StashNativeCardPlugin.clampRatio(0.5f), 0.0001f);
    assertEquals(0.1f, StashNativeCardPlugin.clampRatio(0.1f), 0.0001f);
    assertEquals(1.0f, StashNativeCardPlugin.clampRatio(1.0f), 0.0001f);
  }

  @Test
  public void clampRatioClampsOutOfRange() {
    assertEquals(1.0f, StashNativeCardPlugin.clampRatio(5.0f), 0.0001f);
    assertEquals(0.1f, StashNativeCardPlugin.clampRatio(0.0f), 0.0001f);
    assertEquals(0.1f, StashNativeCardPlugin.clampRatio(-1.0f), 0.0001f);
  }

  @Test
  public void popupMultiplierKeepsValidValuesIncludingAboveOne() {
    assertEquals(1.485f, StashNativeCardPlugin.sanitizePopupMultiplier(1.485f, 2.0f), 0.0001f);
    assertEquals(0.05f, StashNativeCardPlugin.sanitizePopupMultiplier(0.05f, 2.0f), 0.0001f);
  }

  @Test
  public void popupMultiplierFallsBackOnDegenerateInput() {
    assertEquals(2.0f, StashNativeCardPlugin.sanitizePopupMultiplier(0.0f, 2.0f), 0.0001f);
    assertEquals(2.0f, StashNativeCardPlugin.sanitizePopupMultiplier(-1.0f, 2.0f), 0.0001f);
    assertEquals(2.0f, StashNativeCardPlugin.sanitizePopupMultiplier(Float.NaN, 2.0f), 0.0001f);
  }
}
