package com.stash.stashnative;

import static org.junit.Assert.assertArrayEquals;

import android.content.Context;
import android.util.DisplayMetrics;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

/**
 * Pins StashSheetGeometry size outputs. Runs at mdpi (density 1.0), where dpToPx(context, dp) == dp
 * and the dp minimum floors equal their dp values. Unused ratio arguments are set to the 0.99f
 * sentinel.
 */
@RunWith(RobolectricTestRunner.class)
@Config(manifest = Config.NONE, qualifiers = "mdpi")
public class StashSheetGeometryTest {

  private static Context context() {
    return RuntimeEnvironment.getApplication();
  }

  private static DisplayMetrics metrics(int widthPx, int heightPx) {
    DisplayMetrics m = new DisplayMetrics();
    m.widthPixels = widthPx;
    m.heightPixels = heightPx;
    m.density = 1f;
    return m;
  }

  // --- tabletCardSize ---

  @Test
  public void tabletPortraitAppliesPortraitRatios() {
    int[] out = StashSheetGeometry.tabletCardSize(
        context(), metrics(1000, 1500), 0.5f, 0.6f, 0.99f, 0.99f);
    assertArrayEquals(new int[] {500, 900}, out);
  }

  @Test
  public void tabletLandscapeAppliesLandscapeRatios() {
    int[] out = StashSheetGeometry.tabletCardSize(
        context(), metrics(1500, 1000), 0.99f, 0.99f, 0.3f, 0.7f);
    assertArrayEquals(new int[] {450, 700}, out);
  }

  @Test
  public void tabletDegenerateRatiosFallBackToFixedSize() {
    int[] out = StashSheetGeometry.tabletCardSize(
        context(), metrics(1000, 1500), 0f, 0f, 0.99f, 0.99f);
    assertArrayEquals(
        new int[] {
            CardConstants.FALLBACK_TABLET_CARD_WIDTH, CardConstants.FALLBACK_TABLET_CARD_HEIGHT},
        out);
  }

  @Test
  public void tabletEnforcesMinimumFloors() {
    // 0.1 ratios give 100x150, both below the 400x500 dp floors.
    int[] out = StashSheetGeometry.tabletCardSize(
        context(), metrics(1000, 1500), 0.1f, 0.1f, 0.99f, 0.99f);
    assertArrayEquals(new int[] {400, 500}, out);
  }

  // --- modalCardSize ---

  @Test
  public void modalPhonePortraitAppliesPhonePortraitRatios() {
    int[] out = StashSheetGeometry.modalCardSize(
        context(), metrics(1000, 2000), false,
        0.99f, 0.99f, 0.99f, 0.99f, // tablet ratios (unused)
        0.8f, 0.5f, 0.99f, 0.99f);  // phone portrait used
    assertArrayEquals(new int[] {800, 1000}, out);
  }

  @Test
  public void modalTabletLandscapeAppliesTabletLandscapeRatiosAndHeightFloor() {
    // 1500x1000 landscape, tablet 0.3x0.4 -> 450x400; tablet floors 400x500 raise height to 500.
    int[] out = StashSheetGeometry.modalCardSize(
        context(), metrics(1500, 1000), true,
        0.99f, 0.99f, 0.3f, 0.4f,   // tablet landscape used
        0.99f, 0.99f, 0.99f, 0.99f);
    assertArrayEquals(new int[] {450, 500}, out);
  }

  @Test
  public void modalPhoneEnforcesMinimumFloorsUsingWidthDpForBoth() {
    // Phone min uses MIN_PHONE_CARD_WIDTH_DP (300) for both width and height.
    int[] out = StashSheetGeometry.modalCardSize(
        context(), metrics(1000, 2000), false,
        0.99f, 0.99f, 0.99f, 0.99f,
        0.1f, 0.1f, 0.99f, 0.99f);
    assertArrayEquals(new int[] {300, 300}, out);
  }
}
