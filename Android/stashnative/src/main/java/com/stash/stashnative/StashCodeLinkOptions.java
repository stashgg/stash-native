package com.stash.stashnative;

import android.content.Intent;

/** Immutable scanner options carried through activity creation and recreation. */
final class StashCodeLinkOptions {
  final String headerText;
  final String calloutTitle;
  final String calloutSubtitle;
  final String cameraUnavailableText;
  final String connectedText;
  final boolean showCallout;

  private StashCodeLinkOptions(String headerText, String calloutTitle,
      String calloutSubtitle, String cameraUnavailableText, String connectedText,
      boolean showCallout) {
    this.headerText = headerText;
    this.calloutTitle = calloutTitle;
    this.calloutSubtitle = calloutSubtitle;
    this.cameraUnavailableText = cameraUnavailableText;
    this.connectedText = connectedText;
    this.showCallout = showCallout;
  }

  static StashCodeLinkOptions from(StashNativeCard.CodeLinkConfig config) {
    StashNativeCard.CodeLinkConfig value = config == null
        ? new StashNativeCard.CodeLinkConfig() : config;
    return new StashCodeLinkOptions(value.headerText, value.calloutTitle,
        value.calloutSubtitle, value.cameraUnavailableText, value.connectedText, value.showCallout);
  }

  void put(Intent intent) {
    intent.putExtra("stash.codeLink.headerText", headerText);
    intent.putExtra("stash.codeLink.calloutTitle", calloutTitle);
    intent.putExtra("stash.codeLink.calloutSubtitle", calloutSubtitle);
    intent.putExtra("stash.codeLink.cameraUnavailableText", cameraUnavailableText);
    intent.putExtra("stash.codeLink.connectedText", connectedText);
    intent.putExtra("stash.codeLink.showCallout", showCallout);
  }

  static StashCodeLinkOptions read(Intent intent) {
    if (intent == null) {
      return from(null);
    }
    return new StashCodeLinkOptions(intent.getStringExtra("stash.codeLink.headerText"),
        intent.getStringExtra("stash.codeLink.calloutTitle"),
        intent.getStringExtra("stash.codeLink.calloutSubtitle"),
        intent.getStringExtra("stash.codeLink.cameraUnavailableText"),
        intent.getStringExtra("stash.codeLink.connectedText"),
        intent.getBooleanExtra("stash.codeLink.showCallout", true));
  }
}
