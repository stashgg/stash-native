package com.stash.stashnative.sample;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.FrameLayout;
import android.widget.SeekBar;
import android.widget.TextView;
import androidx.recyclerview.widget.RecyclerView;
import java.util.Collections;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Shadows;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.util.ReflectionHelpers;

/** U-29: Maximum content height is 0 (available height) or at least the 240 dp floor. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public class CardOptionsTest {
  @Test public void maximumContentHeightSnapsBelowTheFloor() {
    MainViewModel model = new MainViewModel(RuntimeEnvironment.getApplication());
    int[][] cases = {{0, 0}, {8, 0}, {119, 0}, {120, 240}, {239, 240}, {240, 240}, {600, 600}};
    for (int[] c : cases) {
      model.setDimension(R.string.maximum_content_height, c[0]);
      assertEquals(String.valueOf(c[0]), c[1],
          Math.round(model.getCardConfig().maximumContentHeight));
    }
  }

  /**
   * TalkBack scroll actions step by a fraction of the range; they must cross between Available
   * and the 240 dp floor in one step each way, and touch positions map to legal values only.
   */
  @Test @Config(sdk = {21, 28, 33})
  public void maximumSliderCrossesTheGapByAccessibilityAndTouch() {
    ActivityController<MainActivity> controller =
        Robolectric.buildActivity(MainActivity.class).setup();
    try {
      MainActivity activity = controller.get();
      MainViewModel model = ReflectionHelpers.getField(activity, "viewModel");
      SettingsAdapter adapter = ReflectionHelpers.getField(activity, "adapter");
      FrameLayout parent = new FrameLayout(activity);
      RecyclerView.ViewHolder holder =
          adapter.onCreateViewHolder(parent, SettingsItem.TYPE_SLIDER_PREFERENCE);
      parent.addView(holder.itemView);
      activity.setContentView(parent);
      SeekBar seekBar = holder.itemView.findViewById(R.id.sliderSeekBar);
      TextView value = holder.itemView.findViewById(R.id.sliderValue);

      bindMaximum(adapter, holder, 0);
      assertEquals(0, seekBar.getProgress());
      assertTrue(seekBar.performAccessibilityAction(
          AccessibilityNodeInfo.ACTION_SCROLL_FORWARD, null));
      int forward = Math.round(model.getCardConfig().maximumContentHeight);
      assertTrue("forward from Available: " + forward, forward >= 240 && forward < 600);
      assertEquals(forward + " dp", value.getText().toString());

      bindMaximum(adapter, holder, 240);
      assertEquals(1, seekBar.getProgress());
      assertTrue(seekBar.performAccessibilityAction(
          AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD, null));
      assertEquals(0, seekBar.getProgress());
      assertEquals(0, Math.round(model.getCardConfig().maximumContentHeight));
      assertEquals("Available", value.getText().toString());

      SeekBar.OnSeekBarChangeListener drag =
          Shadows.shadowOf(seekBar).getOnSeekBarChangeListener();
      int[][] touches = {{1, 240}, {0, 0}, {seekBar.getMax(), 1200}, {361, 600}};
      for (int[] touch : touches) {
        seekBar.setProgress(touch[0]);
        drag.onProgressChanged(seekBar, touch[0], true);
        assertEquals(touch[1], Math.round(model.getCardConfig().maximumContentHeight));
        assertEquals(touch[1] == 0 ? "Available" : touch[1] + " dp", value.getText().toString());
      }
    } finally {
      controller.pause().stop().destroy();
    }
  }

  private static void bindMaximum(SettingsAdapter adapter, RecyclerView.ViewHolder holder,
      int maximum) {
    adapter.submitList(Collections.singletonList(SettingsItem.sliderPreference(
        R.string.maximum_content_height, maximum, true, true)));
    adapter.onBindViewHolder(holder, 0);
  }
}
