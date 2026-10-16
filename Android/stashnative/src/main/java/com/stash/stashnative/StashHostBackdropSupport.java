package com.stash.stashnative;

import android.app.Activity;
import android.content.pm.ActivityInfo;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.Matrix;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ImageView;

/** Owns a screenshot through portrait checkout and the return to the host's orientation. */
final class StashHostBackdropSupport {
  private static final int MAX_DIMENSION = 2400;
  private static final long RETURN_TIMEOUT_MS = 800;
  private final int sourceRotation;
  private final int sourceOrientation;
  private final int returnOrientation;
  private final Handler handler = new Handler(Looper.getMainLooper());
  private final Runnable completeReturn = this::completeFinish;
  private Bitmap bitmap;
  private Activity activity;
  private ImageView image;
  private Runnable finish;
  private boolean returning;

  private StashHostBackdropSupport(Activity host, Bitmap bitmap) {
    this.bitmap = bitmap;
    sourceRotation = displayRotation(host);
    sourceOrientation = host.getResources().getConfiguration().orientation;
    int requested = host.getRequestedOrientation();
    returnOrientation = requested == ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        || requested == ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
        || requested == ActivityInfo.SCREEN_ORIENTATION_USER_LANDSCAPE
        ? requested : ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE;
  }

  static StashHostBackdropSupport create(Activity host, Bitmap bitmap) {
    if (bitmap == null || bitmap.isRecycled()) {
      return null;
    }
    try {
      int longest = Math.max(bitmap.getWidth(), bitmap.getHeight());
      if (longest > MAX_DIMENSION) {
        float scale = (float) MAX_DIMENSION / longest;
        Bitmap reduced = Bitmap.createScaledBitmap(bitmap,
            Math.max(1, Math.round(bitmap.getWidth() * scale)),
            Math.max(1, Math.round(bitmap.getHeight() * scale)), true);
        recycle(bitmap);
        bitmap = reduced;
      }
      return new StashHostBackdropSupport(host, bitmap);
    } catch (RuntimeException | OutOfMemoryError expected) {
      recycle(bitmap);
      return null;
    }
  }

  static Bitmap decode(byte[] bytes) {
    if (bytes == null || bytes.length == 0) {
      return null;
    }
    try {
      BitmapFactory.Options bounds = new BitmapFactory.Options();
      bounds.inJustDecodeBounds = true;
      BitmapFactory.decodeByteArray(bytes, 0, bytes.length, bounds);
      if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
        return null;
      }
      BitmapFactory.Options options = new BitmapFactory.Options();
      options.inPreferredConfig = Bitmap.Config.RGB_565;
      options.inSampleSize = 1;
      int longest = Math.max(bounds.outWidth, bounds.outHeight);
      while (longest / options.inSampleSize > MAX_DIMENSION) {
        options.inSampleSize *= 2;
      }
      return BitmapFactory.decodeByteArray(bytes, 0, bytes.length, options);
    } catch (RuntimeException | OutOfMemoryError expected) {
      return null;
    }
  }

  void attach(Activity checkout, FrameLayout root) {
    activity = checkout;
    image = new ImageView(checkout);
    image.setBackgroundColor(Color.BLACK);
    image.setScaleType(ImageView.ScaleType.MATRIX);
    image.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
    image.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
    image.setImageBitmap(bitmap);
    image.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> geometryChanged());
    root.addView(image, new FrameLayout.LayoutParams(-1, -1));
  }

  void geometryChanged() {
    if (image == null || bitmap == null || image.getWidth() == 0 || image.getHeight() == 0) {
      return;
    }
    image.setImageMatrix(matrix(bitmap.getWidth(), bitmap.getHeight(),
        image.getWidth(), image.getHeight(), sourceRotation, displayRotation(activity)));
    if (returning
        && activity.getResources().getConfiguration().orientation == sourceOrientation
        && image.getWidth() > image.getHeight()) {
      // Let the restored landscape screenshot draw before releasing the checkout window.
      image.removeCallbacks(completeReturn);
      image.postOnAnimation(completeReturn);
    }
  }

  static Matrix matrix(int width, int height, int viewWidth, int viewHeight,
      int sourceRotation, int currentRotation) {
    int quarterTurns = (sourceRotation - currentRotation + 4) % 4;
    boolean sideways = quarterTurns % 2 != 0;
    float scale = Math.max((float) viewWidth / (sideways ? height : width),
        (float) viewHeight / (sideways ? width : height));
    Matrix matrix = new Matrix();
    matrix.postTranslate(-width / 2f, -height / 2f);
    matrix.postRotate(quarterTurns * 90f);
    matrix.postScale(scale, scale);
    matrix.postTranslate(viewWidth / 2f, viewHeight / 2f);
    return matrix;
  }

  boolean finishAfterRotation(Runnable completion) {
    if (returning) {
      return true;
    }
    if (activity == null || sourceOrientation != Configuration.ORIENTATION_LANDSCAPE
        || (Build.VERSION.SDK_INT >= 24 && activity.isInMultiWindowMode())) {
      return false;
    }
    returning = true;
    finish = completion;
    handler.postDelayed(completeReturn, RETURN_TIMEOUT_MS);
    try {
      activity.setRequestedOrientation(returnOrientation);
    } catch (RuntimeException expected) {
      completeFinish();
      return true;
    }
    geometryChanged();
    return true;
  }

  private void completeFinish() {
    Runnable completion = finish;
    cancelFinish();
    if (completion != null) {
      completion.run();
    }
  }

  void cancelFinish() {
    handler.removeCallbacks(completeReturn);
    if (image != null) {
      image.removeCallbacks(completeReturn);
    }
    finish = null;
  }

  void dispose() {
    cancelFinish();
    if (image != null) {
      image.setImageDrawable(null);
      if (image.getParent() instanceof FrameLayout) {
        ((FrameLayout) image.getParent()).removeView(image);
      }
      image = null;
    }
    activity = null;
    recycle(bitmap);
    bitmap = null;
  }

  static void recycle(Bitmap bitmap) {
    if (bitmap != null && !bitmap.isRecycled()) {
      bitmap.recycle();
    }
  }

  private static int displayRotation(Activity activity) {
    return activity.getWindowManager().getDefaultDisplay().getRotation();
  }
}
