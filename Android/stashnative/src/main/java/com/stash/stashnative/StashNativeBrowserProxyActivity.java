package com.stash.stashnative;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;

/**
 * Invisible activity that owns the Chrome Custom Tabs launch and its
 * {@code startActivityForResult} lifecycle. Removes the host-side requirement
 * to forward {@code onActivityResult} for {@link
 * com.stash.stashnative.StashNative.StashNativeListener#onBrowserDismissed()}.
 *
 * <p>The plugin's existing close-tracking flag ({@code browserCloseAwaitingCctResult})
 * is set before this activity is started, so dispatches from this activity and from
 * the engagement-session-ended path dedupe via the same gate.
 */
public final class StashNativeBrowserProxyActivity extends Activity {

  private static final String TAG = "StashNativeProxyAct";

  static final String EXTRA_URL = "com.stash.stashnative.PROXY_URL";
  static final String EXTRA_SESSION_ID = "com.stash.stashnative.PROXY_SESSION_ID";

  private boolean awaitingResult;
  private boolean initialResumeConsumed;

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);

    if (savedInstanceState != null
        || !StashNativePlugin.getInstance().isCurrentBrowserSession(getBrowserSessionId())) {
      // A recreated or retired proxy must not relaunch a browser after reset.
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
      // Plugin already set browserCloseAwaitingCctResult before starting us, so we
      // dispatch (a no-op for the listener if it wasn't expecting one) to clear that
      // flag and run any pending checkout dismiss. Browser never actually opened.
      Log.w(TAG, "Invalid URL; finishing");
      StashNative.notifyBrowserClosedFromProxyInternal(getBrowserSessionId());
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
          () -> StashNative.notifyBrowserEngagementSessionEndedFromProxyInternal(
              getBrowserSessionId()));
    } catch (Throwable t) {
      Log.w(TAG, "Engagement launch threw: " + t.getMessage());
    }

    if (!launched) {
      int mode = StashUrlLauncher.openExternalUrl(
          this, url, CardConstants.REQUEST_CODE_STASH_CUSTOM_TAB);
      onLaunchMode(mode);
      return;
    }

    // Engagement bind is async (up to ~2.5s). Arm awaitingResult now so a very-early
    // onResume isn't misread as the close fallback.
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
      StashNative.notifyBrowserClosedFromProxyInternal(getBrowserSessionId());
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
    // Second onResume without a delivered result: CCT closed without onActivityResult
    // (OEM Chrome quirk, ACTION_VIEW fallback, etc.). Treat as closed.
    if (awaitingResult) {
      awaitingResult = false;
      StashNative.notifyBrowserClosedFromProxyInternal(getBrowserSessionId());
      finish();
    }
  }

  private long getBrowserSessionId() {
    return getIntent() != null ? getIntent().getLongExtra(EXTRA_SESSION_ID, 0L) : 0L;
  }

  private static Uri parseUri(String url) {
    return StashWebViewUtils.parseAcceptedHttpUri(url);
  }
}
