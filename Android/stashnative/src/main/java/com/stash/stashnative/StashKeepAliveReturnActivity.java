package com.stash.stashnative;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;

/**
 * Invisible target of the keep-alive notification. Decides at tap time instead of baking task
 * flags into the notification: relaunching the host's launcher activity with clear-top (or into a
 * singleTask host) would finish a presented card above it and report a user dismissal.
 */
public final class StashKeepAliveReturnActivity extends Activity {
  private static final String TAG = "StashKeepAlive";

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    if (savedInstanceState == null
        && !StashNativePlugin.getInstance().returnToPresentedCard()) {
      launchApp();
    }
    finish();
    overridePendingTransition(0, 0);
  }

  /** No card is presented: the previous behavior, returning to the host's launcher activity. */
  private void launchApp() {
    try {
      Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
      if (launch != null) {
        // Clear-top closes a browser above the app's root; single-top keeps a standard-mode root
        // instead of recreating it.
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP
            | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        startActivity(launch);
      }
    } catch (Exception e) {
      Log.w(TAG, "Cannot return to the app: " + e.getMessage(), e);
    }
  }
}
