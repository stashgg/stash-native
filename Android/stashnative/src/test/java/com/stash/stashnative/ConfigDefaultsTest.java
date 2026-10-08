package com.stash.stashnative;

import static org.junit.Assert.*;
import org.junit.Test;

public class ConfigDefaultsTest {
  @Test public void cardDefaultsAndSnapshotAreIndependentFromCaller() {
    StashNativeCard.CardConfig config = new StashNativeCard.CardConfig();
    StashPresentationOptions snapshot = StashPresentationOptions.card(config);
    config.preferredContentHeight = 123;
    assertEquals(400f, snapshot.width, 0);
    assertEquals(560f, snapshot.height, 0);
    assertEquals(720f, snapshot.maximumHeight, 0);
    assertEquals(16f, snapshot.margin, 0);
    assertEquals(0, snapshot.orientation);
    assertTrue(snapshot.allowDismiss);
    assertTrue(snapshot.autoClose);
  }

  @Test public void invalidConstraintsNormalizeBeforeDispatch() {
    StashNativeCard.CardConfig config = new StashNativeCard.CardConfig();
    config.preferredContentWidth = Float.NaN;
    config.preferredContentHeight = Float.POSITIVE_INFINITY;
    config.maximumContentHeight = -4;
    config.edgeMargin = Float.NaN;
    config.orientationPreference = 999;
    StashPresentationOptions snapshot = StashPresentationOptions.card(config);
    assertEquals(400f, snapshot.width, 0);
    assertEquals(560f, snapshot.height, 0);
    assertEquals(720f, snapshot.maximumHeight, 0);
    assertEquals(16f, snapshot.margin, 0);
    assertEquals(0, snapshot.orientation);
    assertTrue(Float.isNaN(config.preferredContentWidth));
  }

  @Test public void zeroMarginAndHeightCeilingRemainUnbounded() {
    StashNativeCard.CardConfig config = new StashNativeCard.CardConfig();
    config.edgeMargin = 0;
    config.maximumContentHeight = 0;
    assertEquals(0f, StashPresentationOptions.card(config).maximumHeight, 0);
    assertEquals(0f, StashPresentationOptions.card(config).margin, 0);
  }

  @Test public void reportsVersionThree() { assertEquals("3.0.0", StashNativeCard.getVersion()); }
}
