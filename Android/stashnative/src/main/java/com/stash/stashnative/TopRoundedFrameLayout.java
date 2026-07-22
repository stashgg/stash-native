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
 * Prior to API 33, {@link Outline} from a {@link Path} often cannot be used for
 * {@link View#setClipToOutline(boolean)} ({@link Outline#canClip()} is false), so a full-bleed
 * {@link android.webkit.WebView} draws a square and hides the top radius. Canvas clipping
 * works on all supported API levels.
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

  /** Shared with {@link ViewOutlineProvider} so elevation shadow matches the visible shape. */
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

  private final Path clipPath = new Path();
  private final RectF clipRect = new RectF();
  private final float[] clipRadii = new float[8];
  private int lastClipW = -1;
  private int lastClipH = -1;
  private float lastClipRadius = -1f;

  @Override
  protected void dispatchDraw(Canvas canvas) {
    int w = getWidth();
    int h = getHeight();
    if (w <= 0 || h <= 0) {
      super.dispatchDraw(canvas);
      return;
    }
    // Runs every frame of entry/drag/spring/IME animations; rebuild the path only on size change.
    if (w != lastClipW || h != lastClipH || topCornerRadiusPx != lastClipRadius) {
      float r = topCornerRadiusPx;
      clipRadii[0] = r; clipRadii[1] = r; clipRadii[2] = r; clipRadii[3] = r;
      clipRadii[4] = 0f; clipRadii[5] = 0f; clipRadii[6] = 0f; clipRadii[7] = 0f;
      clipRect.set(0, 0, w, h);
      clipPath.rewind();
      clipPath.addRoundRect(clipRect, clipRadii, Path.Direction.CW);
      lastClipW = w; lastClipH = h; lastClipRadius = topCornerRadiusPx;
    }
    int save = canvas.save();
    canvas.clipPath(clipPath);
    try {
      super.dispatchDraw(canvas);
    } finally {
      canvas.restoreToCount(save);
    }
  }

  /**
   * Outline for {@link #setElevation(float)} only; clipping is done in {@link #dispatchDraw}.
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
        // Sheet is bottom-pinned, so extending the round-rect radiusPx below the bottom edge
        // pushes the square bottom corners off-screen while the top corners match the clip.
        // Round-rect outlines use the fast analytic shadow (no per-frame tessellation/alloc).
        outline.setRoundRect(0, 0, w, (int) (h + radiusPx), radiusPx);
      }
    };
  }
}
