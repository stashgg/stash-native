package com.stash.stashnative;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Outline;
import android.graphics.Path;
import android.graphics.RectF;
import android.os.Build;
import android.util.AttributeSet;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.widget.FrameLayout;

/**
 * Bottom sheet container: clips children to a round-rect with only the top corners rounded.
 * <p>
 * Clipping is applied via {@link Canvas#clipPath(Path)} in {@link #dispatchDraw}, which works on
 * all supported API levels.
 */
public class TopRoundedFrameLayout extends FrameLayout {

  private float topCornerRadiusPx;

  public TopRoundedFrameLayout(Context context, float topCornerRadiusPx) {
    super(context);
    this.topCornerRadiusPx = topCornerRadiusPx;
  }

  public TopRoundedFrameLayout(Context context, AttributeSet attrs) {
    super(context, attrs);
  }

  public TopRoundedFrameLayout(Context context, AttributeSet attrs, int defStyleAttr) {
    super(context, attrs, defStyleAttr);
  }

  /** Builds the top-rounded round-rect {@link Path} for the given dimensions and corner radius. */
  public static Path buildTopRoundedClipPath(float width, float height, float radiusPx) {
    Path path = new Path();
    if (width <= 0f || height <= 0f) {
      return path;
    }
    float r = radiusPx;
    path.addRoundRect(
        new RectF(0, 0, width, height),
        new float[]{
            r, r,
            r, r,
            0f, 0f,
            0f, 0f
        },
        Path.Direction.CW);
    return path;
  }

  @Override
  protected void dispatchDraw(Canvas canvas) {
    int w = getWidth();
    int h = getHeight();
    if (w <= 0 || h <= 0) {
      super.dispatchDraw(canvas);
      return;
    }
    Path path = buildTopRoundedClipPath(w, h, topCornerRadiusPx);
    int save = canvas.save();
    canvas.clipPath(path);
    try {
      super.dispatchDraw(canvas);
    } finally {
      canvas.restoreToCount(save);
    }
  }

  /**
   * Returns a {@link ViewOutlineProvider} that sets a top-rounded outline for elevation shadows.
   */
  public static ViewOutlineProvider outlineProviderForElevation(final float radiusPx) {
    return new ViewOutlineProvider() {
      @Override
      public void getOutline(View view, Outline outline) {
        int w = view.getWidth();
        int h = view.getHeight();
        if (w <= 0 || h <= 0) {
          outline.setEmpty();
          return;
        }
        Path path = buildTopRoundedClipPath(w, h, radiusPx);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
          outline.setPath(path);
        } else {
          outline.setConvexPath(path);
        }
      }
    };
  }
}
