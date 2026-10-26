package com.stash.stashnative;

import static org.junit.Assert.*;
import org.junit.Test;

public class CardGeometryTest {
  private StashCheckoutSizing.Layout card(int width, int height, float density, boolean expanded) {
    return StashCheckoutSizing.resolve(new StashCheckoutSizing.Box(0, 0, width, height), density,
        StashPresentationOptions.card(null), expanded);
  }

  @Test public void phoneContentFillsSheetWithoutReservedChrome() {
    StashCheckoutSizing.Layout layout = card(390, 760, 1, false);
    assertTrue(layout.bottomAttached);
    assertEquals(390, layout.frame.width());
    assertEquals(560, layout.frame.height());
    assertEquals(760, layout.frame.bottom);
  }

  @Test public void densityChangesPixelsWithoutChangingLogicalSize() {
    StashCheckoutSizing.Layout first = card(390, 760, 1, false);
    StashCheckoutSizing.Layout scaled = card(1170, 2280, 3, false);
    assertEquals(first.frame.height() * 3, scaled.frame.height());
    assertEquals(first.frame.top * 3, scaled.frame.top);
  }

  @Test public void wideCardCentersAndCapsWidth() {
    StashCheckoutSizing.Layout layout = card(1100, 900, 1, false);
    assertFalse(layout.bottomAttached);
    assertEquals(400, layout.frame.width());
    assertEquals(350, layout.frame.left);
    assertEquals(170, layout.frame.top);
  }

  @Test public void landscapePhoneKeepsBottomCardAtConfiguredWidth() {
    for (boolean expanded : new boolean[] {false, true}) {
      StashCheckoutSizing.Layout layout = StashCheckoutSizing.resolve(
          new StashCheckoutSizing.Box(0, 0, 915, 411), 1, StashPresentationOptions.card(null),
          expanded, true);
      assertTrue(layout.bottomAttached);
      assertEquals(400, layout.frame.width());
      assertEquals(257, layout.frame.left);
      assertEquals(411, layout.frame.bottom);
      assertEquals(395, layout.frame.height());
    }
  }

  @Test public void compactHeightCardStaysWithinTheWidthAndMargins() {
    StashNative.CardConfig config = new StashNative.CardConfig();
    config.preferredContentWidth = 2000;
    StashCheckoutSizing.Layout layout = StashCheckoutSizing.resolve(
        new StashCheckoutSizing.Box(0, 0, 700, 380), 1, StashPresentationOptions.card(config),
        false, true);
    assertTrue(layout.bottomAttached);
    assertEquals(668, layout.frame.width());
    assertEquals(16, layout.frame.left);
  }

  @Test public void tallWideWindowStillFloats() {
    StashCheckoutSizing.Layout layout = StashCheckoutSizing.resolve(
        new StashCheckoutSizing.Box(0, 0, 1100, 900), 1, StashPresentationOptions.card(null),
        false, false);
    assertFalse(layout.bottomAttached);
  }

  @Test public void restingUsesPreferredHeightAndExpandedUsesCeiling() {
    assertEquals(560, card(390, 760, 1, false).frame.height());
    assertEquals(720, card(390, 760, 1, true).frame.height());
  }

  @Test public void shortWindowOverridesPreferredAndMaximumSizes() {
    for (boolean expanded : new boolean[]{true, false}) {
      StashCheckoutSizing.Layout layout = card(900, 240, 1, expanded);
      assertTrue(layout.frame.top >= 16);
      assertTrue(layout.frame.bottom <= 224);
      assertTrue(layout.frame.height() > 0);
    }
  }

  @Test public void configuredCeilingAppliesToBothDetents() {
    StashNative.CardConfig config = new StashNative.CardConfig();
    config.maximumContentHeight = 300;
    StashCheckoutSizing.Layout layout = StashCheckoutSizing.resolve(new StashCheckoutSizing.Box(0, 30, 390, 800),
        1, StashPresentationOptions.card(config), true);
    assertEquals(300, layout.frame.height());
    assertEquals(300, layout.restingHeight);
    assertEquals(800, layout.frame.bottom);
  }

  @Test public void separatingHingeChoosesLargestOrTrailingLowerPane() {
    StashCheckoutSizing.Box bounds = new StashCheckoutSizing.Box(0, 0, 1000, 800);
    StashCheckoutSizing.Box vertical = new StashCheckoutSizing.Box(490, 0, 510, 800);
    assertEquals(510, StashCheckoutSizing.choosePane(bounds, vertical, true, false).left);
    assertEquals(490, StashCheckoutSizing.choosePane(bounds, vertical, true, true).right);
    StashCheckoutSizing.Box horizontal = new StashCheckoutSizing.Box(0, 390, 1000, 410);
    assertEquals(410, StashCheckoutSizing.choosePane(bounds, horizontal, false, false).top);
    StashCheckoutSizing.Box uneven = new StashCheckoutSizing.Box(700, 0, 720, 800);
    assertEquals(700, StashCheckoutSizing.choosePane(bounds, uneven, true, false).right);
  }

  @Test public void draggingWideCardStaysCenteredWithinItsPane() {
    StashCheckoutSizing.Layout layout = card(1100, 900, 1, false);
    StashCheckoutSizing.Box expanded = StashCheckoutSizing.frameAtHeight(layout, 10000);
    assertEquals(90, expanded.top);
    assertEquals(810, expanded.bottom);
    assertEquals(900, expanded.top + expanded.bottom);
    StashCheckoutSizing.Layout compact = card(390, 760, 1, false);
    assertEquals(760, StashCheckoutSizing.frameAtHeight(compact, 10000).bottom);
  }

  @Test public void zeroMarginUsesAvailableBounds() {
    StashNative.CardConfig config = new StashNative.CardConfig();
    config.edgeMargin = 0;
    StashCheckoutSizing.Layout layout = StashCheckoutSizing.resolve(new StashCheckoutSizing.Box(0, 0, 300, 200),
        1, StashPresentationOptions.card(config), false);
    assertEquals(300, layout.frame.width());
    assertEquals(200, layout.frame.height());
  }
}
