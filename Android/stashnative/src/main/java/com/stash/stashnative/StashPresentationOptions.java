package com.stash.stashnative;

import android.content.Intent;

/** Immutable snapshot of presentation options, taken before dispatch to the main thread. */
final class StashPresentationOptions {
  final float width;
  final float height;
  final float maximumHeight;
  final float margin;
  final boolean allowDismiss;
  final boolean autoClose;
  final int orientation;

  private StashPresentationOptions(
      float width,
      float height,
      float maximumHeight,
      float margin,
      boolean allowDismiss,
      boolean autoClose,
      int orientation) {
    this.width = positive(width, 400f);
    this.height = positive(height, 560f);
    this.maximumHeight = nonnegative(maximumHeight, 720f);
    this.margin = nonnegative(margin, 16f);
    this.allowDismiss = allowDismiss;
    this.autoClose = autoClose;
    this.orientation =
        orientation == StashNativeCard.CardConfig.ORIENTATION_PORTRAIT
            ? StashNativeCard.CardConfig.ORIENTATION_PORTRAIT
            : StashNativeCard.CardConfig.ORIENTATION_FOLLOW_HOST;
  }

  static StashPresentationOptions card(StashNativeCard.CardConfig config) {
    StashNativeCard.CardConfig c = config == null ? new StashNativeCard.CardConfig() : config;
    return new StashPresentationOptions(
        c.preferredContentWidth,
        c.preferredContentHeight,
        c.maximumContentHeight,
        c.edgeMargin,
        c.allowDismiss,
        c.autoClose,
        c.orientationPreference);
  }

  void put(Intent intent) {
    intent.putExtra("stash.width", width);
    intent.putExtra("stash.height", height);
    intent.putExtra("stash.maxHeight", maximumHeight);
    intent.putExtra("stash.margin", margin);
    intent.putExtra("stash.allowDismiss", allowDismiss);
    intent.putExtra("stash.autoClose", autoClose);
    intent.putExtra("stash.orientation", orientation);
  }

  static StashPresentationOptions read(Intent intent) {
    return new StashPresentationOptions(
        intent.getFloatExtra("stash.width", 400f),
        intent.getFloatExtra("stash.height", 560f),
        intent.getFloatExtra("stash.maxHeight", 720f),
        intent.getFloatExtra("stash.margin", 16f),
        intent.getBooleanExtra("stash.allowDismiss", true),
        intent.getBooleanExtra("stash.autoClose", true),
        intent.getIntExtra("stash.orientation", 0));
  }

  static float positive(float value, float fallback) {
    return Float.isNaN(value) || Float.isInfinite(value) || value <= 0 ? fallback : value;
  }

  static float nonnegative(float value, float fallback) {
    return Float.isNaN(value) || Float.isInfinite(value) || value < 0 ? fallback : value;
  }
}
