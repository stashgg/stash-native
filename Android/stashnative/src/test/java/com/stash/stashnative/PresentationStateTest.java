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
}
