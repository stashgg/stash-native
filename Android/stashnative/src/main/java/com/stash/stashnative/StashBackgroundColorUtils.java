package com.stash.stashnative;

import android.graphics.Color;
import android.util.Log;
import androidx.core.graphics.ColorUtils;

/**
 * Parses optional HTML hex colors for custom sheet backgrounds and derives luminance-based accents.
 */
public final class StashBackgroundColorUtils {
  private static final String TAG = "StashNativeCard";

  private StashBackgroundColorUtils() {}

  /** Trims and returns null if empty or invalid. */
  public static String normalizeHexOrNull(String raw) {
    if (raw == null) {
      return null;
    }
    String s = raw.trim();
    return s.isEmpty() ? null : s;
  }

  /**
   * Parses #RGB, #RRGGBB, or #AARRGGBB into opaque ARGB (alpha forced to 0xFF). Returns null if
   * invalid.
   */
  public static Integer parseSolidColorOrNull(String hex) {
    String s = normalizeHexOrNull(hex);
    if (s == null) {
      return null;
    }
    if (!s.startsWith("#")) {
      Log.w(TAG, "Invalid backgroundColor (expected #hex): " + s);
      return null;
    }
    String h = s.substring(1);
    try {
      if (h.length() == 3) {
        int r = Integer.parseInt(h.substring(0, 1) + h.substring(0, 1), 16);
        int g = Integer.parseInt(h.substring(1, 2) + h.substring(1, 2), 16);
        int b = Integer.parseInt(h.substring(2, 3) + h.substring(2, 3), 16);
        return Color.rgb(r, g, b);
      }
      if (h.length() == 6) {
        return Color.parseColor(s) | 0xFF000000;
      }
      if (h.length() == 8) {
        return Color.parseColor(s);
      }
    } catch (Exception e) {
      Log.w(TAG, "Invalid backgroundColor: " + s, e);
      return null;
    }
    Log.w(TAG, "Invalid backgroundColor length: " + s);
    return null;
  }

  /** True when the background luminance is below 0.5. */
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
