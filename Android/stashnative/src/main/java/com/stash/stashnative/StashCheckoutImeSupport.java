package com.stash.stashnative;

import android.os.Build;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;

/**
 * System-bar and soft-keyboard inset handling for {@link StashNativeCardPortraitActivity}:
 * edge-to-edge padding, keyboard-driven expand/collapse, WebView bottom inset (API 30+) and
 * WebView height shrink (pre-30). State lives on the activity.
 */
final class StashCheckoutImeSupport {
  private static final String TAG = "StashNativeCard";

  private StashCheckoutImeSupport() {}

  /**
   * Applies system-bar padding (excluding the IME) and tracks the soft-keyboard overlap. The window
   * is edge-to-edge, so the IME arrives as an inset rather than a window pan; the legacy
   * system-window inset includes the keyboard height, which without this would inflate the bottom
   * padding and push the bottom-pinned card off the top of the screen.
   */
  static WindowInsetsCompat onWindowInsets(
      StashNativeCardPortraitActivity activity, View v, WindowInsetsCompat insets) {
    try {
      if (StashWindowCompat.applySystemBarsPaddingExcludingIme(v, insets)) {
        applyImeOverlap(activity, StashWindowCompat.getImeOverlapPx(insets));
        return insets.replaceSystemWindowInsets(0, 0, 0, 0);
      }
    } catch (Throwable t) {
      Log.w(TAG, "IME-aware inset handling unavailable: " + t.getMessage());
    }
    // Pre-API-30 (Type.ime() is 30+): keep the card exactly sized and positioned and let the
    // keyboard simply slide over it. The legacy system-window bottom inset includes the keyboard
    // height, so we clamp it back to the keyboard-free (navigation-bar) value; otherwise the inflated
    // padding would lift the bottom-pinned card and make it jump. No resize/cap here.
    return applyPreApi30StaticPadding(activity, v, insets);
  }

  static WindowInsetsCompat applyPreApi30StaticPadding(
      StashNativeCardPortraitActivity activity, View v, WindowInsetsCompat insets) {
    try {
      int left = insets.getSystemWindowInsetLeft();
      int top = insets.getSystemWindowInsetTop();
      int right = insets.getSystemWindowInsetRight();
      int sysBottom = insets.getSystemWindowInsetBottom();
      int navRef = StashWindowCompat.getStableOrNavBottomPx(activity.rootLayout);
      boolean imeInflated =
          navRef > 0 && sysBottom > navRef + (int) StashWebViewUtils.dpToPx(activity, 80);
      if (!imeInflated) {
        // Remember the exact keyboard-free bottom inset so the card does not shift when the keyboard
        // later appears (reusing this value avoids a few-pixel jump from dimension rounding).
        activity.navBottomInsetPx = sysBottom;
      }
      int bottom = imeInflated ? activity.navBottomInsetPx : sysBottom;
      v.setPadding(left, top, right, bottom);
      return insets.replaceSystemWindowInsets(0, 0, 0, 0);
    } catch (Throwable t) {
      return StashWindowCompat.onApplySystemBarInsetsPadding(v, insets);
    }
  }

  /**
   * Pre-API-30 keyboard detection. {@code WindowInsets.Type.ime()} is API 30+, so on older devices
   * the keyboard height is derived from the visible display frame and fed into the same
   * {@link #applyImeOverlap} card expand used on API 30+. No-op on API 30+, where the inset listener
   * drives it.
   */
  static void registerImeGlobalLayoutListenerIfNeeded(StashNativeCardPortraitActivity activity) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R || activity.rootLayout == null) {
      return;
    }
    if (activity.imeGlobalLayoutListener != null) {
      return;
    }
    activity.imeGlobalLayoutListener = () -> updateKeyboardOverlapPreApi30(activity);
    activity.rootLayout.getViewTreeObserver().addOnGlobalLayoutListener(activity.imeGlobalLayoutListener);
  }

  static void updateKeyboardOverlapPreApi30(StashNativeCardPortraitActivity activity) {
    if (activity.cardContainer == null || activity.rootLayout == null || activity.usePopup) {
      return;
    }
    try {
      android.graphics.Rect r = new android.graphics.Rect();
      activity.rootLayout.getWindowVisibleDisplayFrame(r);
      int fullHeight = activity.rootLayout.getRootView().getHeight();
      if (fullHeight <= 0) {
        return;
      }
      int nav = StashWindowCompat.getStableOrNavBottomPx(activity.rootLayout);
      boolean keyboardShown = (fullHeight - r.bottom) > (int) StashWebViewUtils.dpToPx(activity, 80);
      // Keyboard height above the navigation bar (r.bottom is the keyboard top in screen coords).
      int overlap = keyboardShown ? Math.max(0, (fullHeight - nav) - r.bottom) : 0;
      applyImeOverlap(activity, overlap);
      // Pre-30 WebView does not scroll the focused input for content padding, so shrink the WebView's
      // HEIGHT so its bottom sits at the keyboard top -- Chromium then scrolls the input into view.
      // Recomputed every layout pass, so it tracks the card's expand animation. -1 restores full.
      applyPreApi30WebViewHeight(activity, keyboardShown ? r.bottom : -1);
    } catch (Throwable t) {
      Log.w(TAG, "IME<30 overlap failed: " + t.getMessage());
    }
  }

  /**
   * Pre-API-30: sizes the WebView so its bottom sits at {@code keyboardTopScreenY}, leaving the card
   * geometry untouched. {@code keyboardTopScreenY} {@literal <} 0 restores MATCH_PARENT.
   */
  static void applyPreApi30WebViewHeight(StashNativeCardPortraitActivity activity, int keyboardTopScreenY) {
    if (activity.webView == null) {
      return;
    }
    ViewGroup.LayoutParams lp = activity.webView.getLayoutParams();
    if (lp == null) {
      return;
    }
    if (keyboardTopScreenY < 0) {
      if (lp.height != ViewGroup.LayoutParams.MATCH_PARENT) {
        lp.height = ViewGroup.LayoutParams.MATCH_PARENT;
        activity.webView.setLayoutParams(lp);
      }
      return;
    }
    int[] loc = new int[2];
    activity.webView.getLocationOnScreen(loc);
    int target = Math.max(1, keyboardTopScreenY - loc[1]);
    // Tolerance avoids a relayout loop once it settles (setLayoutParams re-triggers global layout).
    if (Math.abs(lp.height - target) > 2) {
      lp.height = target;
      activity.webView.setLayoutParams(lp);
    }
  }

  /** Content height available to gravity-positioned children (root height minus inset padding). */
  static int rootContentHeightPx(StashNativeCardPortraitActivity activity) {
    if (activity.rootLayout == null) {
      return 0;
    }
    return Math.max(0,
        activity.rootLayout.getHeight() - activity.rootLayout.getPaddingTop() - activity.rootLayout.getPaddingBottom());
  }

  /**
   * Matches the iOS behaviour: when the keyboard opens the card expands to the STANDARD expanded size
   * (the same {@link StashNativeCardPortraitActivity#animateExpand} used by drag / the {@code expand()} bridge), and collapses again
   * on hide. The focused input is kept visible by insetting the WebView content from the bottom by
   * the keyboard height (so the card geometry is untouched -- only the web viewport shrinks, and the
   * page scrolls the input into it). Centered card / modal slide up instead. {@code overlapPx} is the
   * keyboard height above the navigation bar (0 = hidden).
   */
  static void applyImeOverlap(StashNativeCardPortraitActivity activity, int overlapPx) {
    if (activity.cardContainer == null || activity.usePopup) {
      return;
    }
    if (activity.isPurchaseProcessing && overlapPx > 0) {
      return;
    }
    if (overlapPx == activity.currentImeOverlapPx) {
      return;
    }
    FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) activity.cardContainer.getLayoutParams();
    if (params == null) {
      return;
    }

    if (activity.cachedIsTablet || activity.useModal) {
      // Centered card: slide up by the amount the keyboard intrudes past the gap below the card;
      // clamp the shift to that same gap so the top never crosses the status bar.
      int cardHeight = params.height > 0 ? params.height : activity.cardContainer.getHeight();
      int gapBelow = Math.max(0, (rootContentHeightPx(activity) - cardHeight) / 2);
      int shift = Math.min(gapBelow, Math.max(0, overlapPx - gapBelow));
      activity.cardContainer.setTranslationY(-shift);
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        applyWebViewBottomInset(activity, overlapPx);
      }
      activity.currentImeOverlapPx = overlapPx;
      return;
    }

    boolean showing = activity.currentImeOverlapPx == 0 && overlapPx > 0;
    boolean hiding = overlapPx == 0;

    if (showing) {
      activity.keyboardActive = true;
      // Expand to the standard expanded size (same as drag / expand()); skip if already expanded.
      if (!activity.isExpanded && !activity.isLandscapeMode()) {
        activity.animateExpand();
        activity.keyboardExpandedCard = true;
      }
    }

    // Keep the focused input visible above the keyboard. API 30+: inset the WebView content (padding)
    // -- modern WebView scrolls the focused element into the reduced viewport. Pre-30 WebView ignores
    // content padding for scroll-into-view, so there the WebView HEIGHT is shrunk instead (handled by
    // the global-layout listener, which has the keyboard top).
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      applyWebViewBottomInset(activity, overlapPx);
    }
    activity.currentImeOverlapPx = overlapPx;

    if (hiding) {
      activity.keyboardActive = false;
      if (activity.keyboardExpandedCard) {
        activity.animateCollapse();
        activity.keyboardExpandedCard = false;
      }
    }
  }

  /**
   * Insets the WebView content from the bottom by {@code bottomPx} so the page lays out / scrolls the
   * focused input above the keyboard, without changing the card size. 0 clears it.
   */
  static void applyWebViewBottomInset(StashNativeCardPortraitActivity activity, int bottomPx) {
    if (activity.webView == null) {
      return;
    }
    int target = Math.max(0, bottomPx);
    if (activity.webView.getPaddingBottom() != target) {
      activity.webView.setPadding(
          activity.webView.getPaddingLeft(), activity.webView.getPaddingTop(), activity.webView.getPaddingRight(), target);
    }
  }

  /** Clears IME state before a rotation re-layout; the next inset pass re-applies it. */
  static void resetImeOverlap(StashNativeCardPortraitActivity activity) {
    if (activity.cardContainer != null) {
      try {
        activity.cardContainer.setTranslationY(0f);
      } catch (Throwable ignored) {
      }
    }
    applyWebViewBottomInset(activity, 0);
    applyPreApi30WebViewHeight(activity, -1);
    if (activity.keyboardExpandedCard) {
      // The rotation resize recomputes the card height from the collapsed base.
      activity.isExpanded = false;
      activity.keyboardExpandedCard = false;
    }
    activity.keyboardActive = false;
    activity.currentImeOverlapPx = 0;
  }

  /** Recomputes the keyboard overlap against the new orientation once the rotation layout settles. */
  static void reapplyImeOverlapAfterRotation(StashNativeCardPortraitActivity activity) {
    if (activity.rootLayout == null) {
      return;
    }
    activity.rootLayout.post(() -> {
      try {
        WindowInsetsCompat insets = ViewCompat.getRootWindowInsets(activity.rootLayout);
        if (insets != null) {
          applyImeOverlap(activity, StashWindowCompat.getImeOverlapPx(insets));
        }
      } catch (Throwable ignored) {
      }
    });
  }
}
