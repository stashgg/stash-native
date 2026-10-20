package com.stash.stashnative;

import org.robolectric.annotation.Implementation;
import org.robolectric.annotation.Implements;

/** Lets the plugin admit the scanner although the core test classpath has no module. */
@Implements(StashScannerContent.class)
public class ResolvedScannerModuleShadow {
  @Implementation
  protected static boolean isAvailable() {
    return true;
  }
}
