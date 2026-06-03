package com.stash.stashnative;

import android.content.Context;
import android.util.DisplayMetrics;

/**
 * Sheet-size math for the tablet checkout card and the modal dialog. Output depends only on the
 * arguments and the context's display density ({@link StashWebViewUtils#dpToPx}).
 *
 * <p>Orientation is derived from the metrics (width > height). The caller passes the current
 * {@link DisplayMetrics}.
 */
final class StashSheetGeometry {

  private StashSheetGeometry() {}

  /**
   * Tablet checkout card size. Applies the orientation-appropriate tablet ratios to the screen,
   * falls back to fixed dimensions if the ratios degenerate, then enforces minimum dp sizes.
   */
  static int[] tabletCardSize(
      Context context,
      DisplayMetrics metrics,
      float widthRatioPortrait,
      float heightRatioPortrait,
      float widthRatioLandscape,
      float heightRatioLandscape) {
    int screenWidth = metrics.widthPixels;
    int screenHeight = metrics.heightPixels;

    boolean isLandscape = screenWidth > screenHeight;

    float widthRatio;
    float heightRatio;
    if (isLandscape) {
      widthRatio = widthRatioLandscape;
      heightRatio = heightRatioLandscape;
    } else {
      widthRatio = widthRatioPortrait;
      heightRatio = heightRatioPortrait;
    }

    int cardWidth = (int) (screenWidth * widthRatio);
    int cardHeight = (int) (screenHeight * heightRatio);

    if (cardWidth <= 0 || cardHeight <= 0) {
      return new int[] {
          CardConstants.FALLBACK_TABLET_CARD_WIDTH, CardConstants.FALLBACK_TABLET_CARD_HEIGHT};
    }

    int minWidth = StashWebViewUtils.dpToPx(context, (int) CardConstants.MIN_TABLET_CARD_WIDTH_DP);
    int minHeight = StashWebViewUtils.dpToPx(context, (int) CardConstants.MIN_TABLET_CARD_HEIGHT_DP);
    return StashWebViewUtils.applyMinFloors(cardWidth, cardHeight, minWidth, minHeight);
  }

  /**
   * Modal dialog size. Picks the tablet-or-phone ratio set for the current orientation, then
   * enforces minimum dp sizes. The phone minHeight uses MIN_PHONE_CARD_WIDTH_DP.
   */
  static int[] modalCardSize(
      Context context,
      DisplayMetrics metrics,
      boolean isTablet,
      float tabletWidthRatioPortrait,
      float tabletHeightRatioPortrait,
      float tabletWidthRatioLandscape,
      float tabletHeightRatioLandscape,
      float phoneWidthRatioPortrait,
      float phoneHeightRatioPortrait,
      float phoneWidthRatioLandscape,
      float phoneHeightRatioLandscape) {
    int screenWidth = metrics.widthPixels;
    int screenHeight = metrics.heightPixels;
    boolean isLandscape = screenWidth > screenHeight;

    float widthRatio;
    float heightRatio;
    if (isTablet) {
      if (isLandscape) {
        widthRatio = tabletWidthRatioLandscape;
        heightRatio = tabletHeightRatioLandscape;
      } else {
        widthRatio = tabletWidthRatioPortrait;
        heightRatio = tabletHeightRatioPortrait;
      }
    } else {
      if (isLandscape) {
        widthRatio = phoneWidthRatioLandscape;
        heightRatio = phoneHeightRatioLandscape;
      } else {
        widthRatio = phoneWidthRatioPortrait;
        heightRatio = phoneHeightRatioPortrait;
      }
    }

    int cardWidth = (int) (screenWidth * widthRatio);
    int cardHeight = (int) (screenHeight * heightRatio);

    int minWidth = StashWebViewUtils.dpToPx(context, isTablet
        ? (int) CardConstants.MIN_TABLET_CARD_WIDTH_DP
        : (int) CardConstants.MIN_PHONE_CARD_WIDTH_DP);
    int minHeight = StashWebViewUtils.dpToPx(context, isTablet
        ? (int) CardConstants.MIN_TABLET_CARD_HEIGHT_DP
        : (int) CardConstants.MIN_PHONE_CARD_WIDTH_DP);

    return StashWebViewUtils.applyMinFloors(cardWidth, cardHeight, minWidth, minHeight);
  }
}
