package com.stash.stashnative;

import android.os.Build;
import android.util.Log;
import android.view.View;
import android.view.Window;
import androidx.annotation.Nullable;
import androidx.core.graphics.Insets;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;
import java.lang.reflect.Method;

/**
 * Avoids hard links to {@code WindowCompat} APIs that require newer AndroidX Core (e.g. Unity and
 * other hosts that still resolve {@code androidx.core:core:1.2.x}). Uses platform APIs on API 30+ and
 * reflection where possible, with no-op or null fallbacks.
 */
final class StashWindowCompat {

  private static final String TAG = "StashWindowCompat";

  private StashWindowCompat() {}

  /**
   * Mirrors {@code WindowCompat.setDecorFitsSystemWindows}. On API 30+ uses {@link
   * Window#setDecorFitsSystemWindows(boolean)}; below that tries reflection on {@code
   * WindowCompat}; otherwise no-op.
   */
  static void setDecorFitsSystemWindows(@Nullable Window window, boolean decorFitsSystemWindows) {
    if (window == null) {
      return;
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        window.setDecorFitsSystemWindows(decorFitsSystemWindows);
        return;
      }
      Method m = androidx.core.view.WindowCompat.class.getMethod(
          "setDecorFitsSystemWindows", Window.class, boolean.class);
      m.invoke(null, window, decorFitsSystemWindows);
    } catch (Throwable t) {
      Log.w(TAG, "setDecorFitsSystemWindows fallback (old androidx.core?): " + t.getMessage());
    }
  }

  /**
   * Mirrors {@code WindowCompat.getInsetsController} via reflection so missing methods on old Core
   * do not cause {@link NoSuchMethodError} at load time.
   */
  @Nullable
  static WindowInsetsControllerCompat getInsetsController(
      @Nullable Window window, @Nullable View decorView) {
    if (window == null || decorView == null) {
      return null;
    }
    try {
      Method m = androidx.core.view.WindowCompat.class.getMethod(
          "getInsetsController", Window.class, View.class);
      Object r = m.invoke(null, window, decorView);
      if (r instanceof WindowInsetsControllerCompat) {
        return (WindowInsetsControllerCompat) r;
      }
    } catch (Throwable t) {
      Log.w(TAG, "getInsetsController unavailable: " + t.getMessage());
    }
    return null;
  }

  /**
   * Returns the status-bar (top) system inset in pixels for the given window; 0 if unavailable.
   * Used to cap card heights so they never extend behind the notch / status bar.
   */
  static int getSystemTopInsetPx(Window window) {
    if (window == null) return 0;
    try {
      View decorView = window.getDecorView();
      android.view.WindowInsets rawInsets = decorView.getRootWindowInsets();
      if (rawInsets == null) return 0;
      WindowInsetsCompat insets = WindowInsetsCompat.toWindowInsetsCompat(rawInsets, decorView);
      int top = insets.getInsets(WindowInsetsCompat.Type.statusBars()).top;
      if (top > 0) return top;
      // Older AndroidX fallback
      return rawInsets.getSystemWindowInsetTop();
    } catch (Exception ignored) {}
    return 0;
  }

  /**
   * Applies system bar insets as padding and returns insets with system bars cleared for children.
   * Works with older {@code androidx.core} where {@link WindowInsetsCompat.Type#systemBars()} is
   * absent (falls back to {@link WindowInsetsCompat#getSystemWindowInsetLeft()} etc.).
   */
  static WindowInsetsCompat onApplySystemBarInsetsPadding(
      View target, WindowInsetsCompat windowInsets) {
    int left;
    int top;
    int right;
    int bottom;
    try {
      Insets bars = windowInsets.getInsets(WindowInsetsCompat.Type.systemBars());
      left = bars.left;
      top = bars.top;
      right = bars.right;
      bottom = bars.bottom;
    } catch (Throwable ignored) {
      left = windowInsets.getSystemWindowInsetLeft();
      top = windowInsets.getSystemWindowInsetTop();
      right = windowInsets.getSystemWindowInsetRight();
      bottom = windowInsets.getSystemWindowInsetBottom();
    }
    target.setPadding(left, top, right, bottom);
    try {
      return new WindowInsetsCompat.Builder(windowInsets)
          .setInsets(WindowInsetsCompat.Type.systemBars(), Insets.NONE)
          .build();
    } catch (Throwable ignored) {
      return windowInsets.replaceSystemWindowInsets(0, 0, 0, 0);
    }
  }
}
