package com.stash.stashnative;

import android.os.Build;
import android.util.Log;
import android.view.View;
import android.view.Window;
import androidx.annotation.Nullable;
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

}
