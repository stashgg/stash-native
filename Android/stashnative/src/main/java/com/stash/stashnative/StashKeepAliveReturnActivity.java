package com.stash.stashnative;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;

/**
 * Invisible target of the keep-alive notification. Returns to a card covered by a keepOpen
 * browser, otherwise to the host's launcher activity. Decides at tap time instead of baking task
 * flags into the notification: relaunching the host's launcher activity with clear-top would
 * finish a presented card above it and report a user dismissal.
 */
public final class StashKeepAliveReturnActivity extends Activity {
  private static final String TAG = "StashKeepAlive";

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    try {
      if (savedInstanceState == null
          && !StashNativeCardPlugin.getInstance().returnToKeepOpenCard()) {
        launchApp();
      }
    } catch (Exception e) {
      Log.w(TAG, "Cannot return from the notification: " + e.getMessage(), e);
    }
    finish();
    overridePendingTransition(0, 0);
  }

  /** No keepOpen browser covers a card: returning to the host's launcher activity. */
  private void launchApp() {
    try {
      Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
      if (launch != null) {
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        startActivity(launch);
      }
    } catch (Exception e) {
      Log.w(TAG, "Cannot return to the app: " + e.getMessage(), e);
    }
  }
}
