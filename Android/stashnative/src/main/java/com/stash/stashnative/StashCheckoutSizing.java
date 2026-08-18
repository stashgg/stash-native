package com.stash.stashnative;

import android.content.res.Configuration;
import android.util.DisplayMetrics;
import android.widget.FrameLayout;

/**
 * Card, sheet, and modal size computation for {@link StashNativeCardPortraitActivity}.
 * Reads the activity's configured ratios and current insets; returns pixel sizes.
 */
final class StashCheckoutSizing {

  private StashCheckoutSizing() {}

  static int[] calculateTabletCardSize(StashNativeCardPortraitActivity activity, DisplayMetrics metrics) {
    // Use actual current screen dimensions
    int screenWidth = metrics.widthPixels;
    int screenHeight = metrics.heightPixels;

    // Determine orientation and use appropriate ratios
    boolean isLandscape = screenWidth > screenHeight;

    float widthRatio;
    float heightRatio;
    if (isLandscape) {
      widthRatio = activity.tabletWidthRatioLandscape;
      heightRatio = activity.tabletHeightRatioLandscape;
    } else {
      widthRatio = activity.tabletWidthRatioPortrait;
      heightRatio = activity.tabletHeightRatioPortrait;
    }

    // Apply orientation-specific tablet ratios to actual screen dimensions
    int cardWidth = (int) (screenWidth * widthRatio);
    int cardHeight = (int) (screenHeight * heightRatio);

    if (cardWidth <= 0 || cardHeight <= 0) {
      return new int[]{
          CardConstants.FALLBACK_TABLET_CARD_WIDTH, CardConstants.FALLBACK_TABLET_CARD_HEIGHT};
    }

    // Enforce minimum sizes for usability
    int minWidth = (int) CardConstants.MIN_TABLET_CARD_WIDTH_DP;
    int minHeight = (int) CardConstants.MIN_TABLET_CARD_HEIGHT_DP;
    if (cardWidth < minWidth) {
      cardWidth = minWidth;
    }
    if (cardHeight < minHeight) {
      cardHeight = minHeight;
    }

    return new int[]{cardWidth, cardHeight};
  }

  /**
   * Phone checkout in portrait (including force-portrait while configuration is still landscape):
   * height is {@code activity.cardHeightRatioPortrait} of the physical portrait screen height, capped so
   * the sheet stays below the status bar and above the navigation bar (aligned with iOS clamping).
   */
  static int computePhonePortraitSheetHeightPx(StashNativeCardPortraitActivity activity, DisplayMetrics metrics) {
    boolean isLandscape = activity.getResources().getConfiguration().orientation
        == Configuration.ORIENTATION_LANDSCAPE;
    int portraitHeight = (activity.forcePortraitOnCheckout && isLandscape)
        ? metrics.widthPixels : metrics.heightPixels;
    int maxH = phoneSheetMaxHeightPx(activity, portraitHeight);
    return Math.min((int) (portraitHeight * activity.cardHeightRatioPortrait), maxH);
  }

  /**
   * Hard ceiling for the phone sheet: top+bottom system insets subtracted from the physical
   * portrait height. This is the true "100%" bound -- {@link #expandedCardHeightCapPx} must never
   * exceed it, or {@code expand()} can grow a card past what a ratio-1.0 config already reaches.
   *
   * <p>Bottom uses {@link StashWindowCompat#getStableOrNavBottomPx} (keyboard-free), not {@link
   * StashWindowCompat#getSystemBottomInsetPx} -- the latter's legacy {@code
   * getSystemWindowInsetBottom()} includes the IME height while the keyboard is visible, which
   * would shrink this ceiling by the keyboard height and starve the keyboard-triggered {@code
   * expand()} in {@link StashCheckoutImeSupport#applyImeOverlap}.
   */
  private static int phoneSheetMaxHeightPx(StashNativeCardPortraitActivity activity, int portraitHeight) {
    int top = StashWindowCompat.getSystemTopInsetPx(activity.getWindow());
    int bottom = StashWindowCompat.getStableOrNavBottomPx(activity.rootLayout);
    int maxH = portraitHeight - top - bottom;
    if (maxH <= 0) {
      maxH = portraitHeight - top;
    }
    if (maxH <= 0) {
      maxH = portraitHeight;
    }
    return maxH;
  }

  static int[] calculateModalCardSize(StashNativeCardPortraitActivity activity, DisplayMetrics metrics) {
    int screenWidth = metrics.widthPixels;
    int screenHeight = metrics.heightPixels;
    boolean isLandscape = screenWidth > screenHeight;
    boolean isTablet = activity.cachedIsTablet;

    float widthRatio;
    float heightRatio;
    if (isTablet) {
      if (isLandscape) {
        widthRatio = activity.modalTabletWidthRatioLandscape;
        heightRatio = activity.modalTabletHeightRatioLandscape;
      } else {
        widthRatio = activity.modalTabletWidthRatioPortrait;
        heightRatio = activity.modalTabletHeightRatioPortrait;
      }
    } else {
      if (isLandscape) {
        widthRatio = activity.modalPhoneWidthRatioLandscape;
        heightRatio = activity.modalPhoneHeightRatioLandscape;
      } else {
        widthRatio = activity.modalPhoneWidthRatioPortrait;
        heightRatio = activity.modalPhoneHeightRatioPortrait;
      }
    }

    int cardWidth = (int) (screenWidth * widthRatio);
    int cardHeight = (int) (screenHeight * heightRatio);

    // Apply minimum sizes
    int minWidth = isTablet
        ? (int) CardConstants.MIN_TABLET_CARD_WIDTH_DP
        : (int) CardConstants.MIN_PHONE_CARD_WIDTH_DP;
    int minHeight = isTablet
        ? (int) CardConstants.MIN_TABLET_CARD_HEIGHT_DP
        : (int) CardConstants.MIN_PHONE_CARD_WIDTH_DP;

    if (cardWidth < minWidth) {
      cardWidth = minWidth;
    }
    if (cardHeight < minHeight) {
      cardHeight = minHeight;
    }

    return new int[]{cardWidth, cardHeight};
  }

  /**
   * Collapsed phone card height for the current orientation and config (matches {@code createCard}
   * logic). Used as a fallback when {@code collapsedCardTargetHeightPx} is unset.
   */
  static int computeCollapsedPhoneCardHeight(StashNativeCardPortraitActivity activity, DisplayMetrics metrics) {
    boolean isLandscape = activity.getResources().getConfiguration().orientation
        == Configuration.ORIENTATION_LANDSCAPE;
    if (isLandscape && !activity.forcePortraitOnCheckout) {
      // Subtract both insets, not just top -- a bottom-inset-blind ceiling here previously let this
      // fallback disagree with calculatePhoneCheckoutCardSize's landscape ceiling, which does account
      // for the bottom inset.
      int maxH = phoneSheetMaxHeightPx(activity, metrics.heightPixels);
      int h = (int) (metrics.heightPixels * activity.cardHeightRatioLandscape);
      int minPx = (int) StashWebViewUtils.dpToPx(
          activity, (int) CardConstants.MIN_PHONE_CARD_WIDTH_DP);
      if (h < minPx) {
        h = minPx;
      }
      return Math.min(h, maxH);
    }
    return computePhonePortraitSheetHeightPx(activity, metrics);
  }

  /**
   * Computes phone checkout card dimensions for current orientation (portrait or landscape).
   * Used by createCard() and animatePhoneCheckoutRotation().
   */
  static int[] calculatePhoneCheckoutCardSize(StashNativeCardPortraitActivity activity, DisplayMetrics metrics) {
    boolean isLandscape = activity.getResources().getConfiguration().orientation
        == Configuration.ORIENTATION_LANDSCAPE;
    int screenWidth = metrics.widthPixels;
    int screenHeight = metrics.heightPixels;
    int cardWidth;
    int cardHeight;
    if (isLandscape) {
      // Always compute the inset-based content height first -- reliable even before the first
      // onApplyWindowInsets dispatch has landed on rootLayout. rootLayout.getHeight() can be
      // positive (laid out) before its inset padding has been applied, in which case its content
      // height would read as the full (unpadded) screen height and this ceiling would silently
      // permit the card to sit behind the status bar. Intersecting the two instead of trusting
      // rootLayout alone whenever it's positive closes that race (mirrors expandedCardHeightCapPx).
      int contentHeight = phoneSheetMaxHeightPx(activity, screenHeight);
      if (activity.rootLayout != null && activity.rootLayout.getHeight() > 0) {
        int rootContentHeight = activity.rootLayout.getHeight()
            - activity.rootLayout.getPaddingTop() - activity.rootLayout.getPaddingBottom();
        if (rootContentHeight > 0) {
          contentHeight = Math.min(contentHeight, rootContentHeight);
        }
      }
      if (contentHeight <= 0) contentHeight = screenHeight;

      int w = (int) (screenWidth * activity.cardWidthRatioLandscape);
      int h = (int) (contentHeight * activity.cardHeightRatioLandscape);
      int minPx = (int) StashWebViewUtils.dpToPx(
          activity, (int) CardConstants.MIN_PHONE_CARD_WIDTH_DP);
      if (w < minPx) {
        w = minPx;
      }
      if (h < minPx) {
        h = minPx;
      }
      cardWidth = w;
      cardHeight = h;
    } else {
      cardWidth = FrameLayout.LayoutParams.MATCH_PARENT;
      cardHeight = computePhonePortraitSheetHeightPx(activity, metrics);
    }
    return new int[]{cardWidth, cardHeight};
  }

  /**
   * Expanded-card height cap: EXPANDED_CARD_HEIGHT_RATIO of the screen, clamped so the card
   * never overflows the inset content box and gets clipped by the root's inset padding -- the
   * bottom-pinned phone sheet loses its header behind the status bar, a centered tablet card
   * loses both edges (mirrors the collapsed clamp in computePhonePortraitSheetHeightPx and iOS
   * height - safeTop). The phone expanded height IS this cap; the tablet expand target is
   * min(base * multiplier, this cap).
   *
   * <p>Intersects two independent sources rather than trusting either alone: the inset-based
   * ceiling (always computed, reliable even before insets have been dispatched) and, when {@code
   * rootLayoutSettled}, the root layout's real content box (keyboard-free on every API path,
   * immune to DisplayMetrics nav-bar semantics which vary by API level). Pass {@code
   * rootLayoutSettled=false} from rotation callbacks -- there the root layout still has the
   * previous orientation's geometry.
   */
  static int expandedCardHeightCapPx(
      StashNativeCardPortraitActivity activity, DisplayMetrics metrics, boolean rootLayoutSettled) {
    // Always compute the inset-based ceiling directly from the window -- this is reliable even
    // before the first onApplyWindowInsets dispatch has landed on rootLayout (see
    // StashWindowCompat.getSystemTopInsetPx's dimen fallback). rootContentHeightPx() depends on
    // rootLayout's padding, which is only set async by that first dispatch: if expand() runs
    // before it lands, rootLayout already has its full (unpadded) height, so rootContentHeightPx()
    // returns a positive but WRONG (too-large) value. Intersecting with the inset-based ceiling
    // instead of trusting rootContentHeightPx() alone closes that race.
    int top = StashWindowCompat.getSystemTopInsetPx(activity.getWindow());
    int bottom = StashWindowCompat.getStableOrNavBottomPx(activity.rootLayout);
    int maxHeight = metrics.heightPixels - top - bottom;
    if (rootLayoutSettled) {
      int rootMax = StashCheckoutImeSupport.rootContentHeightPx(activity);
      if (rootMax > 0) {
        maxHeight = maxHeight > 0 ? Math.min(maxHeight, rootMax) : rootMax;
      }
    }
    if (!activity.cachedIsTablet) {
      // Phone sheet must never expand past the same ceiling a ratio=1.0 (100%) card is clamped
      // to, regardless of what the root content box / stable-nav fallback above report.
      boolean isLandscape = activity.getResources().getConfiguration().orientation
          == Configuration.ORIENTATION_LANDSCAPE;
      int portraitHeight = (activity.forcePortraitOnCheckout && isLandscape)
          ? metrics.widthPixels : metrics.heightPixels;
      maxHeight = Math.min(maxHeight, phoneSheetMaxHeightPx(activity, portraitHeight));
    }
    return clampExpandedHeight(
        (int) (metrics.heightPixels * CardConstants.EXPANDED_CARD_HEIGHT_RATIO), maxHeight);
  }

  /** Raw expanded height capped to the available content box; unclamped when the box is unknown. */
  static int clampExpandedHeight(int rawHeightPx, int maxHeightPx) {
    if (maxHeightPx <= 0) {
      return rawHeightPx;
    }
    return Math.min(rawHeightPx, maxHeightPx);
  }
}
