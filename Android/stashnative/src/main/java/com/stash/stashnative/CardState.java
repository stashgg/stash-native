package com.stash.stashnative;

/**
 * Represents the current state of the checkout card.
 * Reserved for future state management (animations/gestures); not yet referenced in code.
 */
public enum CardState {
  /**
   * Default state - card is at configured height (60-70% of screen on phones).
   */
  COLLAPSED,

  /**
   * Full screen state - card fills the screen minus safe areas (phones only).
   */
  EXPANDED,

  /**
   * Card is being dismissed with animation.
   */
  DISMISSING,

  /**
   * Card has been dismissed and removed from screen.
   */
  DISMISSED
}
