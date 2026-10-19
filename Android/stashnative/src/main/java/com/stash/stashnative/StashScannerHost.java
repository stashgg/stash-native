package com.stash.stashnative;

import android.app.Activity;

/**
 * What the scanner needs from the card that hosts it. SPI for the optional
 * {@code stashnative-codelink} module, not a host API. All calls happen on the main thread.
 */
public interface StashScannerHost {
  /** The card activity; used for services, permissions, and starting Settings. */
  Activity getActivity();

  /** Copy and layout options snapshotted when the scanner opened. */
  StashScannerOptions getScannerOptions();

  /** True once the card started closing; late errors and results are dropped. */
  boolean isDismissing();

  /** The user tapped the scanner's close control. */
  void requestDismiss();

  /** Delivers a decoded QR payload once; the card shows Connected and closes. */
  void completeScan(String content);

  /** Reports a camera error to the listener. The scanner reports at most one per session. */
  void reportScannerError(StashNative.ScannerError error);
}
