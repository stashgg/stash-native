package com.stash.stashnative;

import android.graphics.Rect;
import com.google.zxing.BinaryBitmap;
import com.google.zxing.DecodeHintType;
import com.google.zxing.PlanarYUVLuminanceSource;
import com.google.zxing.ReaderException;
import com.google.zxing.ResultPoint;
import com.google.zxing.common.DetectorResult;
import com.google.zxing.common.HybridBinarizer;
import com.google.zxing.common.PerspectiveTransform;
import com.google.zxing.qrcode.decoder.Decoder;
import com.google.zxing.qrcode.detector.Detector;
import java.nio.ByteBuffer;
import java.util.Collections;

/** QR-only decoding of the visible scan region, on the camera analysis executor. */
final class StashCodeLinkDecoder {
  private final Decoder decoder = new Decoder();

  String decode(ByteBuffer buffer, int width, int height, int rowStride, int pixelStride,
      Rect region) {
    Rect crop = new Rect(region);
    if (!crop.intersect(0, 0, width, height) || crop.width() < 24 || crop.height() < 24) {
      return null;
    }
    byte[] luminance = new byte[crop.width() * crop.height()];
    ByteBuffer source = buffer.duplicate();
    int origin = source.position();
    for (int row = 0; row < crop.height(); row++) {
      int offset = origin + (crop.top + row) * rowStride + crop.left * pixelStride;
      for (int column = 0; column < crop.width(); column++) {
        int index = offset + column * pixelStride;
        if (index >= source.limit()) {
          return null;
        }
        luminance[row * crop.width() + column] = source.get(index);
      }
    }
    PlanarYUVLuminanceSource image = new PlanarYUVLuminanceSource(luminance,
        crop.width(), crop.height(), 0, 0, crop.width(), crop.height(), false);
    try {
      try {
        return read(new BinaryBitmap(new HybridBinarizer(image)));
      } catch (ReaderException expected) {
        return read(new BinaryBitmap(new HybridBinarizer(image.invert())));
      }
    } catch (ReaderException expected) {
      return null;
    }
  }

  private String read(BinaryBitmap image) throws ReaderException {
    DetectorResult detected = new Detector(image.getBlackMatrix()).detect(
        Collections.singletonMap(DecodeHintType.TRY_HARDER, Boolean.TRUE));
    if (!fullyInside(detected, image.getWidth(), image.getHeight())) {
      return null;
    }
    String content = decoder.decode(detected.getBits()).getText();
    return content == null || content.isEmpty() ? null : content;
  }

  private static boolean fullyInside(DetectorResult detected, int width, int height) {
    ResultPoint[] points = detected.getPoints();
    ResultPoint bottomLeft = points[0];
    ResultPoint topLeft = points[1];
    ResultPoint topRight = points[2];
    float dimension = detected.getBits().getWidth();
    float far = dimension - 3.5f;
    float alignment = points.length > 3 ? far - 3 : far;
    float right = points.length > 3 ? points[3].getX()
        : topRight.getX() - topLeft.getX() + bottomLeft.getX();
    float bottom = points.length > 3 ? points[3].getY()
        : topRight.getY() - topLeft.getY() + bottomLeft.getY();
    PerspectiveTransform transform = PerspectiveTransform.quadrilateralToQuadrilateral(
        3.5f, 3.5f, far, 3.5f, alignment, alignment, 3.5f, far,
        topLeft.getX(), topLeft.getY(), topRight.getX(), topRight.getY(),
        right, bottom, bottomLeft.getX(), bottomLeft.getY());
    float[] corners = {0, 0, dimension, 0, dimension, dimension, 0, dimension};
    transform.transformPoints(corners);
    for (int index = 0; index < corners.length; index += 2) {
      float x = corners[index];
      float y = corners[index + 1];
      if (!(x >= 0 && x <= width && y >= 0 && y <= height)) {
        return false;
      }
    }
    return true;
  }
}
