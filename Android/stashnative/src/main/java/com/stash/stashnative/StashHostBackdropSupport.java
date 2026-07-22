package com.stash.stashnative;

import android.graphics.Bitmap;
import android.graphics.Matrix;
import android.view.Surface;
import android.widget.ImageView;

/**
 * Host-backdrop rendering for force-portrait phone checkout: the host app supplies a landscape
 * screenshot that is rotated to fill the portrait window, then restored to plain CENTER_CROP for
 * the return-to-landscape handoff. The deferred-finish state machine stays in
 * {@link StashNativeCardPortraitActivity}.
 */
final class StashHostBackdropSupport {

  private StashHostBackdropSupport() {}

  static void applyPortraitCheckoutMatrix(
      ImageView imageView, Bitmap bitmap, int sourceDisplayRotation) {
    if (imageView == null || bitmap == null || bitmap.isRecycled()) {
      return;
    }
    int viewW = imageView.getWidth();
    int viewH = imageView.getHeight();
    int bmpW = bitmap.getWidth();
    int bmpH = bitmap.getHeight();
    if (viewW == 0 || viewH == 0 || bmpW == 0 || bmpH == 0) {
      return;
    }
    imageView.setScaleType(ImageView.ScaleType.MATRIX);
    // Landscape-left vs landscape-right: opposite ±90° (swap vs earlier build fixes horizontal
    // mirror from game buffer vs Display rotation convention).
    float rotateDeg;
    switch (sourceDisplayRotation) {
      case Surface.ROTATION_270:
        rotateDeg = -90f;
        break;
      case Surface.ROTATION_90:
        rotateDeg = 90f;
        break;
      default:
        rotateDeg = -90f;
        break;
    }
    float cx = bmpW / 2f;
    float cy = bmpH / 2f;
    // Cover scale for ±90°: rotated bounds are bmpH × bmpW
    float scale = Math.max((float) viewW / bmpH, (float) viewH / bmpW);
    Matrix m = new Matrix();
    m.postTranslate(-cx, -cy);
    m.postRotate(rotateDeg);
    m.postScale(scale, scale);
    m.postTranslate(viewW / 2f, viewH / 2f);
    imageView.setImageMatrix(m);
  }

  static void prepareForLandscapeDisplay(ImageView imageView) {
    if (imageView == null) {
      return;
    }
    imageView.setScaleX(1f);
    imageView.setScaleY(1f);
    imageView.setScaleType(ImageView.ScaleType.CENTER_CROP);
    imageView.setImageMatrix(new Matrix());
  }
}
