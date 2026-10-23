package com.stash.stashnative.sample;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import com.stash.stashnative.StashNative;

/**
 * Receives stashdemo:// deeplinks and finishes at once. The checkout card runs above MainActivity
 * in the same task, so routing a link straight to MainActivity would either clear the card
 * (singleTask, clear-top) or stack a second MainActivity over it.
 */
public class DeepLinkActivity extends Activity {

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    Uri link = getIntent().getData();
    if (link != null && "stashdemo".equalsIgnoreCase(link.getScheme())) {
      if (StashNative.getInstance().isCurrentlyPresented()) {
        // The card stays open. closeBrowser closes a keepOpen browser over it, if any, and
        // MainActivity shows the link beneath the card.
        StashNative.getInstance().closeBrowser();
        MainActivity.deliverDeepLink(link.toString());
      } else {
        startActivity(mainIntent(this, link));
      }
    }
    finish();
  }

  /**
   * Returns to the existing MainActivity, finishing anything above it such as the SDK browser
   * (Custom Tabs cannot be closed programmatically). Action and category match the launcher
   * intent, so a later launcher tap resumes this task instead of stacking a new MainActivity.
   */
  static Intent mainIntent(Context context, Uri link) {
    return new Intent(Intent.ACTION_MAIN)
        .addCategory(Intent.CATEGORY_LAUNCHER)
        .setClass(context, MainActivity.class)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP
            | Intent.FLAG_ACTIVITY_SINGLE_TOP)
        .putExtra(MainActivity.EXTRA_DEEP_LINK, link.toString());
  }
}
