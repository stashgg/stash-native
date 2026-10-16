package com.stash.stashnative;

import static org.junit.Assert.*;
import org.junit.Test;

public class PresentationStateTest {
  @Test public void keyboardExpansionRestoresUserSelection() {
    StashPresentationState state = new StashPresentationState();
    state.keyboardVisible = true;
    assertTrue(state.effectiveExpanded());
    state.selectExpanded(true);
    state.keyboardVisible = false;
    assertTrue(state.effectiveExpanded());
    state.selectExpanded(true);
    state.keyboardVisible = true;
    state.selectExpanded(false);
    state.keyboardVisible = false;
    assertFalse(state.effectiveExpanded());
  }

  @Test public void measurementOnlyAppliesAtReportedNativeWidth() {
    StashPresentationState state = new StashPresentationState();
    state.contentHeightPx = 330;
    state.measuredWidthPx = 390;
    assertEquals(330, state.contentForWidth(390), 0);
    assertEquals(0, state.contentForWidth(480), 0);
    state.invalidateContent();
    assertEquals(0, state.contentForWidth(390), 0);
  }
}
