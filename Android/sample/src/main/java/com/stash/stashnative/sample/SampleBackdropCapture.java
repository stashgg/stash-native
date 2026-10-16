package com.stash.stashnative.sample;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.util.Log;
import android.view.View;

/** Captures the sample's view hierarchy before checkout changes the window orientation. */
final class SampleBackdropCapture {
  private static final int MAX_DIMENSION = 2400;

  private SampleBackdropCapture() {}

  static Bitmap capture(View view) {
    int width = view.getWidth();
    int height = view.getHeight();
    if (width <= 0 || height <= 0) {
      return null;
    }
    Bitmap bitmap = null;
    try {
      float scale = Math.min(1f, (float) MAX_DIMENSION / Math.max(width, height));
      bitmap = Bitmap.createBitmap(Math.max(1, Math.round(width * scale)),
          Math.max(1, Math.round(height * scale)), Bitmap.Config.ARGB_8888);
      Canvas canvas = new Canvas(bitmap);
      canvas.scale((float) bitmap.getWidth() / width, (float) bitmap.getHeight() / height);
      view.draw(canvas);
      return bitmap;
    } catch (RuntimeException | OutOfMemoryError expected) {
      if (bitmap != null) {
        bitmap.recycle();
      }
      Log.w("StashNativeDemo", "Could not capture screenshot backdrop", expected);
      return null;
    }
  }
}
