package com.stash.stashnative;

import android.content.Context;
import android.graphics.Outline;
import android.os.Build;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.widget.FrameLayout;

/** Clips the live WebView and coordinates its vertical gestures with the sheet. */
final class StashSheetLayout extends FrameLayout {
  private final float radius;
  private boolean bottomAttached;
  StashPresentationController controller;

  StashSheetLayout(Context context, float cornerRadius) {
    super(context);
    radius = cornerRadius;
    setClipToOutline(true);
    if (Build.VERSION.SDK_INT < 23) {
      // Lollipop's WebView renderer needs a layer to honor the native outline clip.
      setLayerType(View.LAYER_TYPE_HARDWARE, null);
    }
    setOutlineProvider(new ViewOutlineProvider() {
      @Override public void getOutline(View view, Outline outline) {
        int bottom = view.getHeight() + (bottomAttached ? Math.round(radius) : 0);
        outline.setRoundRect(0, 0, view.getWidth(), bottom, radius);
      }
    });
  }

  void setBottomAttached(boolean attached) {
    if (bottomAttached != attached) {
      bottomAttached = attached;
      invalidateOutline();
    }
  }

  @Override
  protected void onSizeChanged(int width, int height, int oldWidth, int oldHeight) {
    super.onSizeChanged(width, height, oldWidth, oldHeight);
    invalidateOutline();
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
