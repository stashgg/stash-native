package com.stash.stashnative;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;

/** Robolectric runs Android color operations used by the automatic theme. */
@RunWith(RobolectricTestRunner.class)
public class StashBackgroundColorUtilsTest {

  @Test
  public void luminanceThreshold() {
    assertTrue(StashBackgroundColorUtils.isDarkBackground(0xFF000000));
    assertTrue(StashBackgroundColorUtils.isDarkBackground(0xFF1E1E1E));
    assertFalse(StashBackgroundColorUtils.isDarkBackground(0xFFFFFFFF));
    assertFalse(StashBackgroundColorUtils.isDarkBackground(0xFFF7F9F4));
  }
}
