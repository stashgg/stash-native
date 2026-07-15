package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/** Pure math: endpoints, range, and that it no longer saturates in the first quarter. */
public class SpringInterpolatorTest {

  @Test
  public void endpoints() {
    SpringInterpolator si = new SpringInterpolator();
    assertEquals(0f, si.getInterpolation(0f), 1e-6f);
    assertEquals(1f, si.getInterpolation(1f), 1e-6f);
  }

  @Test
  public void staysInUnitRange() {
    SpringInterpolator si = new SpringInterpolator();
    for (int i = 0; i <= 100; i++) {
      float v = si.getInterpolation(i / 100f);
      assertTrue("value " + v + " out of range at t=" + (i / 100f), v >= 0f && v <= 1f);
    }
  }

  @Test
  public void doesNotSaturateEarly() {
    SpringInterpolator si = new SpringInterpolator();
    // Old STIFFNESS=400 hit ~1.0 by t=0.25; the retune must leave visible travel after that.
    assertTrue(si.getInterpolation(0.2f) < 0.95f);
    assertTrue(si.getInterpolation(0.6f) > si.getInterpolation(0.2f));
  }
}
