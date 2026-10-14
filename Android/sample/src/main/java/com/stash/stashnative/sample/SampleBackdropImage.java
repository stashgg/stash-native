package com.stash.stashnative.sample;

import android.content.ContentResolver;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.net.Uri;
import android.provider.OpenableColumns;
import android.util.Log;
import androidx.exifinterface.media.ExifInterface;
import java.io.IOException;
import java.io.InputStream;

/** Keeps a bounded, oriented image for repeated backdrop tests. */
final class SampleBackdropImage {
  private static final int MAX_DIMENSION = 2400;
  final String name;
  private final Bitmap bitmap;

  private SampleBackdropImage(String name, Bitmap bitmap) {
    this.name = name;
    this.bitmap = bitmap;
  }

  static SampleBackdropImage load(ContentResolver resolver, Uri uri) {
    Bitmap bitmap = null;
    try {
      final String name = displayName(resolver, uri);
      BitmapFactory.Options options = new BitmapFactory.Options();
      options.inJustDecodeBounds = true;
      try (InputStream stream = open(resolver, uri)) {
        BitmapFactory.decodeStream(stream, null, options);
      }
      if (options.outWidth <= 0 || options.outHeight <= 0) {
        return null;
      }
      options.inSampleSize = 1;
      int longest = Math.max(options.outWidth, options.outHeight);
      while ((long) longest > (long) MAX_DIMENSION * options.inSampleSize) {
        options.inSampleSize *= 2;
      }
      options.inJustDecodeBounds = false;
      options.inPreferredConfig = Bitmap.Config.ARGB_8888;
      try (InputStream stream = open(resolver, uri)) {
        bitmap = BitmapFactory.decodeStream(stream, null, options);
      }
      if (bitmap == null) {
        return null;
      }
      Matrix orientation = orientation(resolver, uri);
      Bitmap oriented = Bitmap.createBitmap(bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(),
          orientation, true);
      if (oriented != bitmap) {
        bitmap.recycle();
        bitmap = oriented;
      }
      return new SampleBackdropImage(name, bitmap);
    } catch (IOException | RuntimeException | OutOfMemoryError expected) {
      if (bitmap != null) {
        bitmap.recycle();
      }
      Log.w("StashNativeDemo", "Could not load backdrop image", expected);
      return null;
    }
  }

  Bitmap copy() {
    try {
      return bitmap.copy(Bitmap.Config.ARGB_8888, false);
    } catch (RuntimeException | OutOfMemoryError expected) {
      return null;
    }
  }

  void recycle() {
    bitmap.recycle();
  }

  private static InputStream open(ContentResolver resolver, Uri uri) throws IOException {
    InputStream stream = resolver.openInputStream(uri);
    if (stream == null) {
      throw new IOException("Image provider returned no data");
    }
    return stream;
  }

  private static Matrix orientation(ContentResolver resolver, Uri uri) {
    try (InputStream stream = open(resolver, uri)) {
      ExifInterface exif = new ExifInterface(stream);
      Matrix matrix = new Matrix();
      if (exif.isFlipped()) {
        matrix.postScale(-1, 1);
      }
      matrix.postRotate(exif.getRotationDegrees());
      return matrix;
    } catch (IOException | RuntimeException expected) {
      // Images without readable EXIF metadata keep their decoded orientation.
      return new Matrix();
    }
  }

  private static String displayName(ContentResolver resolver, Uri uri) {
    try (Cursor cursor = resolver.query(uri, new String[] {OpenableColumns.DISPLAY_NAME},
        null, null, null)) {
      if (cursor != null && cursor.moveToFirst() && !cursor.isNull(0)) {
        return cursor.getString(0);
      }
    } catch (RuntimeException expected) {
      // A provider may supply readable image data without a display name.
    }
    String path = uri.getLastPathSegment();
    return path != null ? path : "";
  }
}
