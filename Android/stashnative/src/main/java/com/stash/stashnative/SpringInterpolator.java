package com.stash.stashnative;

import android.view.animation.Interpolator;

/**
 * Spring interpolator approximating iOS spring motion with damping 0.85.
 * Uses a damped harmonic oscillator model.
 */
public class SpringInterpolator implements Interpolator {
  private static final float DAMPING = 0.85f;
  private static final float STIFFNESS = 400f;
  private static final float MASS = 1f;
  
  private static final float OMEGA = (float) Math.sqrt(STIFFNESS / MASS);
  private static final float DAMPED_OMEGA = OMEGA * (float) Math.sqrt(1 - DAMPING * DAMPING);
  
  @Override
  public float getInterpolation(float input) {
    if (input <= 0f) {
      return 0f;
    }
    if (input >= 1f) {
      return 1f;
    }
    
    float t = input;
    float expTerm = (float) Math.exp(-DAMPING * OMEGA * t);
    float cosTerm = (float) Math.cos(DAMPED_OMEGA * t);
    float sinTerm = (float) Math.sin(DAMPED_OMEGA * t);
    float dampingRatio = DAMPING * OMEGA / DAMPED_OMEGA;
    
    float result = 1f - expTerm * (cosTerm + dampingRatio * sinTerm);
    
    return Math.max(0f, Math.min(1f, result));
  }
}
