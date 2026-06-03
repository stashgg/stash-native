package com.stash.stashnative;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;

/**
 * Invisible activity that owns the Chrome Custom Tabs launch and its
 * {@code startActivityForResult} lifecycle. Dispatches {@link
 * com.stash.stashnative.StashNativeCard.StashNativeCardListener#onBrowserClosed()}
 * when the Custom Tab closes.
 *
 * <p>The plugin sets its close-tracking flag ({@code browserCloseAwaitingCctResult})
 * before this activity starts. Dispatches from this activity and from the
 * engagement-session-ended path dedupe via that gate.
 */
public final class StashNativeBrowserProxyActivity extends Activity {

  private static final String TAG = "StashNativeProxyAct";

  static final String EXTRA_URL = "com.stash.stashnative.PROXY_URL";

  private boolean awaitingResult;
  private boolean initialResumeConsumed;

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);

    if (savedInstanceState != null) {
      // Recreated after process death or a configuration change while CCT was on top.
      // Dispatches browser-closed (the plugin gate no-ops if no close was pending) and finishes
      // without relaunching CCT.
      StashNativeCard.notifyBrowserClosedFromProxyInternal();
      finish();
      return;
    }

    String url = getIntent() != null ? getIntent().getStringExtra(EXTRA_URL) : null;
    if (url == null || url.isEmpty()) {
      Log.w(TAG, "Missing URL extra; finishing");
      finish();
      return;
    }

    Uri uri = parseUri(url);
    if (uri == null) {
      // URL did not parse to an http/https URI with a host; browser never opened.
      // Dispatches browser-closed to clear the plugin gate and run any pending checkout dismiss.
      Log.w(TAG, "Invalid URL; finishing");
      StashNativeCard.notifyBrowserClosedFromProxyInternal();
      finish();
      return;
    }

    boolean launched = false;
    try {
      launched = StashCustomTabsEngagement.tryLaunchForResult(
          this,
          uri,
          CardConstants.REQUEST_CODE_STASH_CUSTOM_TAB,
          this::onLaunchMode,
          StashNativeCard::notifyBrowserEngagementSessionEndedFromProxyInternal);
    } catch (Throwable t) {
      Log.w(TAG, "Engagement launch threw: " + t.getMessage());
    }

    if (!launched) {
      int mode = StashUrlLauncher.openExternalUrl(
          this, url, CardConstants.REQUEST_CODE_STASH_CUSTOM_TAB);
      onLaunchMode(mode);
      return;
    }

    // Engagement bind is async (up to ~2.5s). Arms awaitingResult before bind completes.
    awaitingResult = true;
  }

  /** Called by the engagement helper (or the synchronous fallback) with the actual launch mode. */
  private void onLaunchMode(int launchMode) {
    awaitingResult = true;
  }

  @Override
  protected void onActivityResult(int requestCode, int resultCode, Intent data) {
    if (requestCode == CardConstants.REQUEST_CODE_STASH_CUSTOM_TAB) {
      awaitingResult = false;
      StashNativeCard.notifyBrowserClosedFromProxyInternal();
      finish();
      return;
    }
    super.onActivityResult(requestCode, resultCode, data);
  }

  @Override
  protected void onResume() {
    super.onResume();
    if (!initialResumeConsumed) {
      initialResumeConsumed = true;
      return;
    }
    // Second onResume while awaitingResult is set: CCT closed without delivering
    // onActivityResult. Treated as closed.
    if (awaitingResult) {
      awaitingResult = false;
      StashNativeCard.notifyBrowserClosedFromProxyInternal();
      finish();
    }
  }

  private static Uri parseUri(String url) {
    try {
      Uri uri = Uri.parse(url.trim());
      String scheme = uri.getScheme();
      if (scheme == null) {
        return null;
      }
      String s = scheme.toLowerCase();
      if (!"http".equals(s) && !"https".equals(s)) {
        return null;
      }
      if (uri.getHost() == null || uri.getHost().isEmpty()) {
        return null;
      }
      return uri;
    } catch (Throwable t) {
      return null;
    }
  }
}
