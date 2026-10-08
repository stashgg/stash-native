package com.stash.stashnative;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Path;
import android.graphics.RectF;
import android.view.MotionEvent;
import android.widget.FrameLayout;

/** Clips the live WebView and coordinates its vertical gestures with the sheet. */
final class StashSheetLayout extends FrameLayout {
  private final Path clip = new Path();
  private final float radius;
  private boolean bottomAttached;
  StashPresentationController controller;

  StashSheetLayout(Context context, float radius) {
    super(context);
    this.radius = radius;
  }

  void setBottomAttached(boolean attached) {
    bottomAttached = attached;
    invalidate();
  }

  @Override
  public void draw(Canvas canvas) {
    clip.reset();
    float bottomRadius = bottomAttached ? 0 : radius;
    clip.addRoundRect(
        new RectF(0, 0, getWidth(), getHeight()),
        new float[] {
          radius, radius, radius, radius, bottomRadius, bottomRadius, bottomRadius, bottomRadius
        },
        Path.Direction.CW);
    int save = canvas.save();
    canvas.clipPath(clip);
    super.draw(canvas);
    canvas.restoreToCount(save);
  }

  @Override
  public boolean onInterceptTouchEvent(MotionEvent event) {
    return controller != null && controller.interceptTouch(event);
  }

  @Override
  public boolean onTouchEvent(MotionEvent event) {
    return controller != null && controller.onTouch(this, event);
  }
}
