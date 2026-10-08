package com.stash.stashnative;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.ValueAnimator;
import android.graphics.Rect;
import android.os.Build;
import android.view.MotionEvent;
import android.view.VelocityTracker;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.animation.DecelerateInterpolator;
import android.widget.FrameLayout;
import androidx.core.graphics.Insets;
import androidx.core.util.Consumer;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsAnimationCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.window.java.layout.WindowInfoTrackerCallbackAdapter;
import androidx.window.layout.DisplayFeature;
import androidx.window.layout.FoldingFeature;
import androidx.window.layout.WindowInfoTracker;
import androidx.window.layout.WindowLayoutInfo;
import java.util.List;

/** Owns the sheet's geometry, selection, gestures, keyboard response, and animations. */
final class StashPresentationController implements View.OnTouchListener {
  private final StashCheckoutActivity activity;
  final StashPresentationState state = new StashPresentationState();
  private final StashPresentationOptions options;
  private Insets bars = Insets.NONE;
  private int keyboardBottom;
  private StashCheckoutSizing.Box hinge;
  private boolean verticalHinge;
  private WindowInfoTrackerCallbackAdapter windowTracker;
  private final Consumer<WindowLayoutInfo> windowListener = this::onWindowLayout;
  private android.view.ViewTreeObserver.OnGlobalLayoutListener legacyKeyboardListener;
  private ValueAnimator animator;
  private int animationEpoch;
  private boolean entered;
  private boolean disposed;
  private StashCheckoutSizing.Layout layout;
  private StashCheckoutSizing.Box shownFrame;
  private float touchX;
  private float touchY;
  private boolean dragging;
  private boolean gestureCancelled;
  private int dragHeight;
  private VelocityTracker velocity;

  StashPresentationController(StashCheckoutActivity activity, StashPresentationOptions options) {
    this.activity = activity;
    this.options = options;
  }

  void attach() {
    activity.rootLayout.addOnLayoutChangeListener(
        (v, l, t, r, b, ol, ot, or, ob) -> {
          if (r - l != or - ol || b - t != ob - ot) {
            environmentChanged();
          }
        });
    ViewCompat.setOnApplyWindowInsetsListener(
        activity.rootLayout,
        (v, insets) -> {
          applyInsets(insets);
          return insets;
        });
    ViewCompat.setWindowInsetsAnimationCallback(
        activity.rootLayout,
        new WindowInsetsAnimationCompat.Callback(
            WindowInsetsAnimationCompat.Callback.DISPATCH_MODE_CONTINUE_ON_SUBTREE) {
          @Override
          public WindowInsetsCompat onProgress(
              WindowInsetsCompat insets, List<WindowInsetsAnimationCompat> runningAnimations) {
            applyInsets(insets);
            return insets;
          }
        });
    ViewCompat.requestApplyInsets(activity.rootLayout);
    if (Build.VERSION.SDK_INT < 30) {
      legacyKeyboardListener =
          () -> {
            Rect visible = new Rect();
            activity.rootLayout.getWindowVisibleDisplayFrame(visible);
            int[] location = new int[2];
            activity.rootLayout.getLocationOnScreen(location);
            int overlap =
                Math.max(0, location[1] + activity.rootLayout.getHeight() - visible.bottom);
            int next = overlap > dp(80) ? overlap : 0;
            if (next != keyboardBottom) {
              keyboardBottom = next;
              state.keyboardVisible = next > 0;
              environmentChanged();
            }
          };
      activity.rootLayout.getViewTreeObserver().addOnGlobalLayoutListener(legacyKeyboardListener);
    }
    try {
      windowTracker = new WindowInfoTrackerCallbackAdapter(WindowInfoTracker.getOrCreate(activity));
      windowTracker.addWindowLayoutInfoListener(activity, activity::runOnUiThread, windowListener);
    } catch (Throwable ignored) {
      // Devices without a folding extension still follow the current window bounds.
    }
    activity.rootLayout.post(this::environmentChanged);
  }

  private void applyInsets(WindowInsetsCompat insets) {
    Insets nextBars =
        insets.getInsets(
            WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout());
    int nextKeyboard = insets.getInsets(WindowInsetsCompat.Type.ime()).bottom;
    if (bars.equals(nextBars) && keyboardBottom == nextKeyboard) {
      return;
    }
    bars = nextBars;
    keyboardBottom = nextKeyboard;
    state.keyboardVisible = nextKeyboard > nextBars.bottom;
    environmentChanged();
  }

  private void onWindowLayout(WindowLayoutInfo info) {
    hinge = null;
    for (DisplayFeature feature : info.getDisplayFeatures()) {
      if (feature instanceof FoldingFeature) {
        FoldingFeature fold = (FoldingFeature) feature;
        if (fold.isSeparating() || fold.getOcclusionType() == FoldingFeature.OcclusionType.FULL) {
          Rect bounds = fold.getBounds();
          int[] rootLocation = new int[2];
          activity.rootLayout.getLocationInWindow(rootLocation);
          hinge =
              new StashCheckoutSizing.Box(
                  bounds.left - rootLocation[0],
                  bounds.top - rootLocation[1],
                  bounds.right - rootLocation[0],
                  bounds.bottom - rootLocation[1]);
          verticalHinge = fold.getOrientation() == FoldingFeature.Orientation.VERTICAL;
          break;
        }
      }
    }
    environmentChanged();
  }

  private StashCheckoutSizing.Layout resolve() {
    int width = activity.rootLayout.getWidth();
    int height = activity.rootLayout.getHeight();
    StashCheckoutSizing.Box safe =
        new StashCheckoutSizing.Box(
            bars.left,
            bars.top,
            Math.max(bars.left + 1, width - bars.right),
            Math.max(bars.top + 1, height - Math.max(bars.bottom, keyboardBottom)));
    StashCheckoutSizing.Box pane =
        StashCheckoutSizing.choosePane(
            safe,
            hinge,
            verticalHinge,
            activity.rootLayout.getLayoutDirection() == View.LAYOUT_DIRECTION_RTL);
    StashCheckoutSizing.Layout base =
        StashCheckoutSizing.resolve(pane, density(), options, state.effectiveExpanded(), 0);
    return StashCheckoutSizing.resolve(
        pane,
        density(),
        options,
        state.effectiveExpanded(),
        state.contentForWidth(base.frame.width()));
  }

  void environmentChanged() {
    if (disposed
        || activity.isDismissing
        || activity.rootLayout == null
        || activity.rootLayout.getWidth() <= 0
        || activity.rootLayout.getHeight() <= 0) {
      return;
    }
    StashCheckoutSizing.Layout next = resolve();
    final boolean widthChanged = layout != null && layout.frame.width() != next.frame.width();
    cancelAnimation();
    dragging = false;
    layout = next;
    applyFrame(next.frame);
    activity.cardContainer.setTranslationY(0);
    activity.cardContainer.setAlpha(1);
    activity.backdropView.setAlpha(1);
    if (widthChanged && activity.contentSizeSupport != null) {
      activity.contentSizeSupport.widthChanged();
    }
    if (!entered) {
      entered = true;
      animateVisibility(true, null);
    }
  }

  void setExpanded(boolean expanded) {
    if (activity.isDismissing || disposed) {
      return;
    }
    state.selectExpanded(expanded);
    relayoutAnimated();
  }

  void contentChanged(double height, int width) {
    if (disposed || activity.isDismissing) {
      return;
    }
    state.contentHeightPx = height;
    state.measuredWidthPx = width;
    if (!dragging) {
      relayoutAnimated();
    }
  }

  void clearContent() {
    state.invalidateContent();
    relayoutAnimated();
  }

  private void relayoutAnimated() {
    if (layout == null || disposed || activity.isDismissing) {
      return;
    }
    layout = resolve();
    StashCheckoutSizing.Box start = shownFrame;
    StashCheckoutSizing.Box end = layout.frame;
    float translation = activity.cardContainer.getTranslationY();
    if (start == null) {
      applyFrame(end);
      return;
    }
    animate(
        280,
        value -> {
          applyFrame(
              new StashCheckoutSizing.Box(
                  lerp(start.left, end.left, value),
                  lerp(start.top, end.top, value),
                  lerp(start.right, end.right, value),
                  lerp(start.bottom, end.bottom, value)));
          activity.cardContainer.setTranslationY(translation * (1 - value));
        },
        null);
  }

  private void applyFrame(StashCheckoutSizing.Box frame) {
    shownFrame = frame;
    FrameLayout.LayoutParams p =
        (FrameLayout.LayoutParams) activity.cardContainer.getLayoutParams();
    p.width = Math.max(1, frame.width());
    p.height = Math.max(1, frame.height());
    p.leftMargin = frame.left;
    p.topMargin = frame.top;
    activity.cardContainer.setLayoutParams(p);
    activity.cardContainer.setBottomAttached(layout != null && layout.bottomAttached);
  }

  void dismiss(Runnable completion) {
    animateVisibility(false, completion);
  }

  private void animateVisibility(boolean showing, Runnable completion) {
    boolean bottom = layout != null && layout.bottomAttached;
    int height = shownFrame != null ? shownFrame.height() : activity.cardContainer.getHeight();
    float initialY = activity.cardContainer.getTranslationY();
    animate(
        showing ? 300 : 220,
        value -> {
          float visibility = showing ? value : 1 - value;
          activity.backdropView.setAlpha(visibility);
          activity.cardContainer.setAlpha(bottom ? 1 : visibility);
          activity.cardContainer.setTranslationY(
              bottom
                  ? (showing ? height * (1 - value) : initialY + (height - initialY) * value)
                  : 0);
        },
        completion);
  }

  private interface FrameUpdate {
    void update(float value);
  }

  private void animate(int duration, FrameUpdate update, Runnable completion) {
    cancelAnimation();
    final int epoch = animationEpoch;
    animator = ValueAnimator.ofFloat(0, 1);
    animator.setDuration(duration);
    animator.setInterpolator(new DecelerateInterpolator());
    animator.addUpdateListener(
        animation -> {
          if (epoch == animationEpoch && !disposed) {
            update.update((Float) animation.getAnimatedValue());
          }
        });
    animator.addListener(
        new AnimatorListenerAdapter() {
          @Override
          public void onAnimationEnd(Animator animation) {
            if (epoch == animationEpoch && !disposed) {
              animator = null;
              if (completion != null) {
                completion.run();
              }
            }
          }
        });
    animator.start();
  }

  private void cancelAnimation() {
    animationEpoch++;
    if (!activity.isDismissing && activity.cardContainer != null) {
      activity.cardContainer.setAlpha(1);
      activity.backdropView.setAlpha(1);
    }
    if (animator != null) {
      animator.cancel();
      animator = null;
    }
  }

  private boolean canDrag() {
    return !activity.isPurchaseProcessing && !activity.isDismissing && !disposed;
  }

  boolean interceptTouch(MotionEvent event) {
    if (!canDrag()) {
      return false;
    }
    if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
      beginTouch(event);
      return false;
    }
    if (ignoreMultiplePointers(event)) {
      return false;
    }
    if (event.getActionMasked() == MotionEvent.ACTION_MOVE) {
      float delta = event.getRawY() - touchY;
      boolean vertical = Math.abs(delta) > Math.abs(event.getRawX() - touchX);
      boolean atTop = activity.webView == null || !activity.webView.canScrollVertically(-1);
      if (vertical
          && Math.abs(delta) > ViewConfiguration.get(activity).getScaledTouchSlop()
          && ((delta < 0 && !state.effectiveExpanded()) || (delta > 0 && atTop))) {
        dragging = true;
        cancelAnimation();
        return true;
      }
    }
    return dragging;
  }

  private void beginTouch(MotionEvent event) {
    touchX = event.getRawX();
    touchY = event.getRawY();
    dragHeight = shownFrame == null ? 0 : shownFrame.height();
    dragging = false;
    gestureCancelled = false;
    if (velocity != null) {
      velocity.recycle();
    }
    velocity = VelocityTracker.obtain();
    velocity.addMovement(event);
  }

  private boolean ignoreMultiplePointers(MotionEvent event) {
    if (event.getPointerCount() > 1) {
      gestureCancelled = true;
      if (dragging) {
        dragging = false;
        relayoutAnimated();
      }
    }
    return gestureCancelled;
  }

  void processingStarted() {
    gestureCancelled = true;
    if (velocity != null) {
      velocity.recycle();
      velocity = null;
    }
    if (dragging) {
      environmentChanged();
    }
  }

  @Override
  public boolean onTouch(View view, MotionEvent event) {
    if (!canDrag() || layout == null) {
      return false;
    }
    if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
      beginTouch(event);
      cancelAnimation();
      return true;
    }
    if (ignoreMultiplePointers(event)) {
      return true;
    }
    if (velocity != null) {
      velocity.addMovement(event);
    }
    float delta = event.getRawY() - touchY;
    if (event.getActionMasked() == MotionEvent.ACTION_MOVE) {
      dragging = true;
      int height =
          Math.max(
              layout.restingHeight,
              Math.min(layout.expandedHeight, Math.round(dragHeight - delta)));
      applyFrame(StashCheckoutSizing.frameAtHeight(layout, height));
      activity.cardContainer.setTranslationY(
          options.allowDismiss ? Math.max(0, delta - (dragHeight - height)) : 0);
      return true;
    }
    if (event.getActionMasked() == MotionEvent.ACTION_UP
        || event.getActionMasked() == MotionEvent.ACTION_CANCEL) {
      float speed = 0;
      if (velocity != null) {
        velocity.computeCurrentVelocity(1000);
        speed = velocity.getYVelocity() / density();
        velocity.recycle();
        velocity = null;
      }
      boolean cancel = event.getActionMasked() == MotionEvent.ACTION_CANCEL;
      if (!cancel && !dragging) {
        view.performClick();
        return true;
      }
      dragging = false;
      float translation = activity.cardContainer.getTranslationY();
      if (!cancel
          && options.allowDismiss
          && (translation > dp(100) || (translation > dp(20) && speed > 700))) {
        activity.dismissWithAnimation();
      } else {
        if (!cancel && !state.keyboardVisible) {
          boolean expanded =
              speed < -400
                  || (speed <= 400
                      && shownFrame.height() > (layout.restingHeight + layout.expandedHeight) / 2);
          state.selectExpanded(expanded);
        }
        relayoutAnimated();
      }
      return true;
    }
    return true;
  }

  void dispose() {
    disposed = true;
    cancelAnimation();
    if (velocity != null) {
      velocity.recycle();
      velocity = null;
    }
    if (windowTracker != null) {
      windowTracker.removeWindowLayoutInfoListener(windowListener);
    }
    if (legacyKeyboardListener != null && activity.rootLayout != null) {
      activity
          .rootLayout
          .getViewTreeObserver()
          .removeOnGlobalLayoutListener(legacyKeyboardListener);
    }
  }

  private float density() {
    return activity.getResources().getDisplayMetrics().density;
  }

  private int dp(float value) {
    return Math.round(value * density());
  }

  private static int lerp(int start, int end, float value) {
    return Math.round(start + (end - start) * value);
  }
}
