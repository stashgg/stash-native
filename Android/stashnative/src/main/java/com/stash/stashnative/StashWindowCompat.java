package com.stash.stashnative;

import android.content.Context;
import android.content.res.Resources;
import android.os.Build;
import android.util.Log;
import android.view.View;
import android.view.Window;
import androidx.annotation.Nullable;
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
   * Reads a framework {@code dimen} such as {@code status_bar_height} / {@code navigation_bar_height}.
   * Used when {@link View#getRootWindowInsets()} is unavailable (API {@literal <} 23) or returns null.
   */
  private static int systemBarDimensionPx(@Nullable Context context, String dimenName) {
    if (context == null) {
      return 0;
    }
    try {
      Resources res = context.getResources();
      int id = res.getIdentifier(dimenName, "dimen", "android");
      if (id <= 0) {
        return 0;
      }
      return res.getDimensionPixelSize(id);
    } catch (Exception ignored) {
      return 0;
    }
  }

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
   *
   * <p>Uses only platform {@link android.view.WindowInsets} — never {@link
   * WindowInsetsCompat#toWindowInsetsCompat(android.view.WindowInsets, View)}, so hosts (e.g.
   * Unity) that ship an old {@code androidx.core} on the classpath do not crash with {@link
   * NoSuchMethodError}.
   */
  static int getSystemTopInsetPx(Window window) {
    if (window == null) {
      return 0;
    }
    try {
      View decorView = window.getDecorView();
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        android.view.WindowInsets wi = decorView.getRootWindowInsets();
        if (wi != null) {
          int top = wi.getSystemWindowInsetTop();
          if (top > 0) {
            return top;
          }
        }
      }
      return systemBarDimensionPx(window.getContext(), "status_bar_height");
    } catch (Throwable ignored) {
      return 0;
    }
  }

  /**
   * Returns the navigation-bar (bottom) system inset in pixels; 0 if unavailable.
   * Used with {@link #getSystemTopInsetPx} to cap sheet height so the card does not draw into
   * gesture or 3-button navigation areas.
   *
   * <p>Same host-compat constraints as {@link #getSystemTopInsetPx}.
   */
  static int getSystemBottomInsetPx(Window window) {
    if (window == null) {
      return 0;
    }
    try {
      View decorView = window.getDecorView();
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        android.view.WindowInsets wi = decorView.getRootWindowInsets();
        if (wi != null) {
          int bottom = wi.getSystemWindowInsetBottom();
          if (bottom > 0) {
            return bottom;
          }
        }
      }
      return systemBarDimensionPx(window.getContext(), "navigation_bar_height");
    } catch (Throwable ignored) {
      return 0;
    }
  }

  /**
   * Applies system bar insets as padding and returns insets with system bars cleared for children.
   *
   * <p>Uses only legacy {@link WindowInsetsCompat#getSystemWindowInsetLeft()} (etc.) and {@link
   * WindowInsetsCompat#replaceSystemWindowInsets(int, int, int, int)} — no {@link
   * WindowInsetsCompat.Type} or {@link WindowInsetsCompat.Builder}, so Unity and other hosts that
   * ship an older {@code androidx.core} do not hit {@link NoSuchMethodError} / missing {@code Type}.
   */
  static WindowInsetsCompat onApplySystemBarInsetsPadding(
      View target, WindowInsetsCompat windowInsets) {
    int left = windowInsets.getSystemWindowInsetLeft();
    int top = windowInsets.getSystemWindowInsetTop();
    int right = windowInsets.getSystemWindowInsetRight();
    int bottom = windowInsets.getSystemWindowInsetBottom();
    target.setPadding(left, top, right, bottom);
    return windowInsets.replaceSystemWindowInsets(0, 0, 0, 0);
  }
}
