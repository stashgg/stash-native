package com.stash.stashnative;

import android.content.Intent;

/**
 * Immutable scanner copy carried through card creation and recreation. Read by the optional
 * {@code stashnative-codelink} module through {@link StashScannerHost#getScannerOptions()}.
 */
public final class StashScannerOptions {
  public final String headerText;
  public final String calloutTitle;
  public final String calloutSubtitle;
  public final String cameraUnavailableText;
  public final String connectedText;
  public final boolean showCallout;

  private StashScannerOptions(String headerText, String calloutTitle,
      String calloutSubtitle, String cameraUnavailableText, String connectedText,
      boolean showCallout) {
    this.headerText = headerText;
    this.calloutTitle = calloutTitle;
    this.calloutSubtitle = calloutSubtitle;
    this.cameraUnavailableText = cameraUnavailableText;
    this.connectedText = connectedText;
    this.showCallout = showCallout;
  }

  /** Snapshots a config; null uses the bundled defaults. */
  public static StashScannerOptions from(StashNative.ScannerConfig config) {
    StashNative.ScannerConfig value = config == null
        ? new StashNative.ScannerConfig() : config;
    return new StashScannerOptions(value.headerText, value.calloutTitle,
        value.calloutSubtitle, value.cameraUnavailableText, value.connectedText, value.showCallout);
  }

  void put(Intent intent) {
    intent.putExtra("stash.scanner.headerText", headerText);
    intent.putExtra("stash.scanner.calloutTitle", calloutTitle);
    intent.putExtra("stash.scanner.calloutSubtitle", calloutSubtitle);
    intent.putExtra("stash.scanner.cameraUnavailableText", cameraUnavailableText);
    intent.putExtra("stash.scanner.connectedText", connectedText);
    intent.putExtra("stash.scanner.showCallout", showCallout);
  }

  static StashScannerOptions read(Intent intent) {
    if (intent == null) {
      return from(null);
    }
    return new StashScannerOptions(intent.getStringExtra("stash.scanner.headerText"),
        intent.getStringExtra("stash.scanner.calloutTitle"),
        intent.getStringExtra("stash.scanner.calloutSubtitle"),
        intent.getStringExtra("stash.scanner.cameraUnavailableText"),
        intent.getStringExtra("stash.scanner.connectedText"),
        intent.getBooleanExtra("stash.scanner.showCallout", true));
  }
}
