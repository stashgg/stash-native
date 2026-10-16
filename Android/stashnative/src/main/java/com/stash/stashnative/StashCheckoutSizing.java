package com.stash.stashnative;

/** Pure geometry in physical pixels; all configured dimensions enter in dp. */
final class StashCheckoutSizing {
  static final float WIDE_WINDOW_DP = 600f;

  private StashCheckoutSizing() {}

  static final class Box {
    final int left;
    final int top;
    final int right;
    final int bottom;

    Box(int left, int top, int right, int bottom) {
      this.left = left;
      this.top = top;
      this.right = Math.max(left, right);
      this.bottom = Math.max(top, bottom);
    }

    int width() {
      return right - left;
    }

    int height() {
      return bottom - top;
    }

    long area() {
      return (long) width() * height();
    }
  }

  static final class Layout {
    final Box frame;
    final int restingHeight;
    final int expandedHeight;
    final boolean bottomAttached;
    final int bottomInset;

    Layout(
        Box frame,
        int restingHeight,
        int expandedHeight,
        boolean bottomAttached,
        int bottomInset) {
      this.frame = frame;
      this.restingHeight = restingHeight;
      this.expandedHeight = expandedHeight;
      this.bottomAttached = bottomAttached;
      this.bottomInset = bottomInset;
    }
  }

  /** A separating hinge belongs to neither pane. Ties select trailing or lower. */
  static Box choosePane(Box safe, Box hinge, boolean vertical, boolean rtl) {
    if (hinge == null
        || hinge.right < safe.left
        || hinge.left > safe.right
        || hinge.bottom < safe.top
        || hinge.top > safe.bottom) {
      return safe;
    }
    Box first;
    Box second;
    if (vertical) {
      first = new Box(safe.left, safe.top, Math.max(safe.left, hinge.left), safe.bottom);
      second = new Box(Math.min(safe.right, hinge.right), safe.top, safe.right, safe.bottom);
    } else {
      first = new Box(safe.left, safe.top, safe.right, Math.max(safe.top, hinge.top));
      second = new Box(safe.left, Math.min(safe.bottom, hinge.bottom), safe.right, safe.bottom);
    }
    if (first.area() == second.area()) {
      return vertical && rtl ? first : second;
    }
    return first.area() > second.area() ? first : second;
  }

  static Layout resolve(
      Box pane,
      float density,
      StashPresentationOptions options,
      boolean expanded,
      double intrinsicContentHeightPx) {
    density = StashPresentationOptions.positive(density, 1f);
    boolean bottom = pane.width() / density < WIDE_WINDOW_DP;
    int margin =
        Math.min(Math.round(options.margin * density), Math.min(pane.width(), pane.height()) / 4);
    int width =
        bottom
            ? pane.width()
            : Math.min(px(options.width, density), Math.max(1, pane.width() - 2 * margin));
    int outerHeight = Math.max(1, pane.height() - (bottom ? margin : 2 * margin));
    int contentCap = outerHeight;
    if (options.maximumHeight > 0) {
      contentCap = Math.min(contentCap, px(options.maximumHeight, density));
    }
    int restingContent = Math.min(contentCap, px(options.height, density));
    if (!Double.isNaN(intrinsicContentHeightPx)
        && !Double.isInfinite(intrinsicContentHeightPx)
        && intrinsicContentHeightPx > 0) {
      restingContent = Math.min(restingContent, (int) Math.ceil(intrinsicContentHeightPx));
    }
    int resting = Math.max(1, restingContent);
    int maximum = contentCap;
    int height = expanded ? maximum : resting;
    int left = pane.left + Math.max(0, (pane.width() - width) / 2);
    int top = bottom ? pane.bottom - height : pane.top + (pane.height() - height) / 2;
    return new Layout(
        new Box(left, top, left + width, top + height),
        resting,
        maximum,
        bottom,
        0);
  }

  /** Adds the paint-through area without changing the usable content height or top edge. */
  static Layout extendBottom(Layout layout, int inset) {
    if (!layout.bottomAttached || inset <= 0) {
      return layout;
    }
    Box frame = layout.frame;
    return new Layout(
        new Box(frame.left, frame.top, frame.right, frame.bottom + inset),
        layout.restingHeight + inset,
        layout.expandedHeight + inset,
        true,
        inset);
  }

  static Box frameAtHeight(Layout layout, int requestedHeight) {
    int height = Math.max(layout.restingHeight, Math.min(layout.expandedHeight, requestedHeight));
    int top = layout.bottomAttached ? layout.frame.bottom - height
        : layout.frame.top + (layout.frame.height() - height) / 2;
    return new Box(layout.frame.left, top, layout.frame.right, top + height);
  }

  private static int px(float dp, float density) {
    return Math.max(1, (int) Math.min(Integer.MAX_VALUE / 4d, Math.round((double) dp * density)));
  }
}
