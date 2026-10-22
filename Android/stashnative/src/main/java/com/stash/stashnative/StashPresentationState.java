package com.stash.stashnative;

/** User selection survives temporary keyboard and window constraints. */
final class StashPresentationState {
  boolean expanded;
  boolean keyboardVisible;

  boolean effectiveExpanded() {
    return expanded || keyboardVisible;
  }

  void selectExpanded(boolean value) {
    expanded = value;
  }
}
