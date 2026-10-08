package com.stash.stashnative;

import android.graphics.Color;
import androidx.core.graphics.ColorUtils;

/**
 * Derives readable accents from the automatic sheet background.
 */
public final class StashBackgroundColorUtils {
  private StashBackgroundColorUtils() {}

  /** True when the background is visually dark (use white/light spinner and handle). */
  public static boolean isDarkBackground(int colorArgb) {
    double lum = ColorUtils.calculateLuminance(colorArgb);
    return lum < 0.5;
  }

  public static int spinnerLightAccent() {
    return Color.WHITE;
  }

  public static int spinnerDarkAccent() {
    return Color.DKGRAY;
  }

  public static int dragHandleOnDarkBackground() {
    return Color.parseColor(CardConstants.COLOR_DRAG_HANDLE);
  }

  public static int dragHandleOnLightBackground() {
    return Color.parseColor("#636366");
  }

  public static int dragHandleFor(int sheetArgb) {
    return isDarkBackground(sheetArgb) ? dragHandleOnDarkBackground() : dragHandleOnLightBackground();
  }

  public static int spinnerAccentFor(int sheetArgb) {
    return isDarkBackground(sheetArgb) ? spinnerLightAccent() : spinnerDarkAccent();
  }
}
