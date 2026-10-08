package com.stash.stashnative.consumer;

import android.app.Activity;
import android.os.Bundle;
import com.stash.stashnative.StashNativeCard;

/** Minimal Java integration built against the release AAR with R8 enabled. */
public class MainActivity extends Activity {
  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    android.widget.Button button = new android.widget.Button(this);
    button.setText("Open checkout");
    button.setOnClickListener(view -> StashNativeCard.getInstance().openCard(
        this, "https://test.stashpreview.com", new StashNativeCard.CardConfig()));
    setContentView(button);
  }

  @Override
  protected void onDestroy() {
    StashNativeCard.getInstance().resetPresentationState();
    super.onDestroy();
  }
}
