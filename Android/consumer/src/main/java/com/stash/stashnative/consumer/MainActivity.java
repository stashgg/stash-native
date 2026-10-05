package com.stash.stashnative.consumer;

import android.app.Activity;
import android.os.Bundle;
import com.stash.stashnative.StashNativeCard;

/** Minimal Java integration built against the release AAR with R8 enabled. */
public class MainActivity extends Activity {
  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    StashNativeCard.getInstance().setActivity(this);
  }

  @Override
  protected void onDestroy() {
    StashNativeCard.getInstance().resetPresentationState();
    super.onDestroy();
  }
}
