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
    int top = StashWindowCompat.getSystemTopInsetPx(activity.getWindow());
    int bottom = StashWindowCompat.getSystemBottomInsetPx(activity.getWindow());
    int maxH = portraitHeight - top - bottom;
    if (maxH <= 0) {
      maxH = portraitHeight - top;
    }
    if (maxH <= 0) {
      maxH = portraitHeight;
    }
    return Math.min((int) (portraitHeight * activity.cardHeightRatioPortrait), maxH);
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
      int maxH = metrics.heightPixels - StashWindowCompat.getSystemTopInsetPx(activity.getWindow());
      if (maxH <= 0) maxH = metrics.heightPixels;
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
      // Use activity.rootLayout content height (after inset padding) when available; this is the
      // actual drawable area. Fall back to screen height minus insets before first layout.
      int contentHeight = screenHeight;
      if (activity.rootLayout != null && activity.rootLayout.getHeight() > 0) {
        contentHeight = activity.rootLayout.getHeight() - activity.rootLayout.getPaddingTop() - activity.rootLayout.getPaddingBottom();
      } else {
        int topInset = StashWindowCompat.getSystemTopInsetPx(activity.getWindow());
        int bottomInset = StashWindowCompat.getSystemBottomInsetPx(activity.getWindow());
        if (topInset + bottomInset > 0) {
          contentHeight = screenHeight - topInset - bottomInset;
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
}
