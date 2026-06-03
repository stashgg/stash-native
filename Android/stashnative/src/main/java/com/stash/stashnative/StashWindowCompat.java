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
 * Window and inset helpers that use platform APIs on API 30+ and reflection elsewhere, with no-op or
 * null fallbacks. Does not hard-link {@code WindowCompat} APIs that require newer AndroidX Core.
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
   * Mirrors {@code WindowCompat.getInsetsController} via reflection. Returns null on failure.
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
   *
   * <p>Uses only platform {@link android.view.WindowInsets}, never {@link
   * WindowInsetsCompat#toWindowInsetsCompat(android.view.WindowInsets, View)}.
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
   *
   * <p>Uses only platform {@link android.view.WindowInsets}, never {@link
   * WindowInsetsCompat#toWindowInsetsCompat(android.view.WindowInsets, View)}.
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
   * WindowInsetsCompat#replaceSystemWindowInsets(int, int, int, int)}; no {@link
   * WindowInsetsCompat.Type} or {@link WindowInsetsCompat.Builder}.
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

  /**
   * Applies system-bar padding using only the status and navigation bars, excluding the IME.
   *
   * <p>Platform API 30+ only ({@code WindowInsets.Type.systemBars()}). Returns {@code true} when
   * padding was applied, {@code false} when unavailable. Uses framework types only (no {@code
   * WindowInsetsCompat.Type}).
   */
  static boolean applySystemBarsPaddingExcludingIme(View target, WindowInsetsCompat windowInsets) {
    if (target == null || windowInsets == null) {
      return false;
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        android.view.WindowInsets platform = windowInsets.toWindowInsets();
        if (platform != null) {
          android.graphics.Insets bars =
              platform.getInsets(android.view.WindowInsets.Type.systemBars());
          target.setPadding(bars.left, bars.top, bars.right, bars.bottom);
          return true;
        }
      }
    } catch (Throwable ignored) {
    }
    return false;
  }

  /**
   * Height in px by which a visible soft keyboard overlaps the content sitting above the navigation
   * bar (IME bottom minus system-bars bottom); 0 if hidden/unavailable. Platform API 30+ only; 0
   * otherwise.
   */
  static int getImeOverlapPx(WindowInsetsCompat windowInsets) {
    if (windowInsets == null) {
      return 0;
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        android.view.WindowInsets platform = windowInsets.toWindowInsets();
        if (platform != null) {
          int ime = platform.getInsets(android.view.WindowInsets.Type.ime()).bottom;
          int bars = platform.getInsets(android.view.WindowInsets.Type.systemBars()).bottom;
          return Math.max(0, ime - bars);
        }
      }
    } catch (Throwable ignored) {
    }
    return 0;
  }

  /**
   * Navigation-bar (bottom) reference height in px that excludes the IME: the stable bottom inset if
   * available, otherwise the framework {@code navigation_bar_height}.
   */
  static int getStableOrNavBottomPx(View view) {
    if (view == null) {
      return 0;
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        android.view.WindowInsets wi = view.getRootWindowInsets();
        if (wi != null) {
          int stable = wi.getStableInsetBottom();
          if (stable > 0) {
            return stable;
          }
        }
      }
    } catch (Throwable ignored) {
    }
    return systemBarDimensionPx(view.getContext(), "navigation_bar_height");
  }
}
