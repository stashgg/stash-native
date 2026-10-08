package com.stash.stashnative;

/** User selection survives temporary keyboard and window constraints. */
final class StashPresentationState {
  boolean expanded;
  boolean keyboardVisible;
  double contentHeightPx;
  int measuredWidthPx;

  boolean effectiveExpanded() {
    return expanded || keyboardVisible;
  }

  void selectExpanded(boolean value) {
    expanded = value;
  }

  void invalidateContent() {
    contentHeightPx = 0;
    measuredWidthPx = 0;
  }

  double contentForWidth(int width) {
    return width == measuredWidthPx ? contentHeightPx : 0;
  }
}
