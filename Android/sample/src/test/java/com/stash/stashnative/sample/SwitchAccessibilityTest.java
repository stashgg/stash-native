package com.stash.stashnative.sample;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import android.view.View;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.FrameLayout;
import androidx.recyclerview.widget.RecyclerView;
import com.google.android.material.materialswitch.MaterialSwitch;
import java.util.Collections;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.util.ReflectionHelpers;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = {21, 28})
public class SwitchAccessibilityTest {
  @Test public void settingsSwitchExposesPurposeAndStateAfterRebinding() {
    ActivityController<MainActivity> controller = Robolectric.buildActivity(MainActivity.class).setup();
    try {
      MainActivity activity = controller.get();
      SettingsAdapter adapter = ReflectionHelpers.getField(activity, "adapter");
      FrameLayout parent = new FrameLayout(activity);
      RecyclerView.ViewHolder holder = adapter.onCreateViewHolder(
          parent, SettingsItem.TYPE_SWITCH_PREFERENCE);
      parent.addView(holder.itemView);
      activity.setContentView(parent);
      int[] titles = {
          R.string.option_force_portrait_on_checkout, R.string.option_card_allow_dismiss,
          R.string.option_card_auto_close, R.string.option_keep_alive,
          R.string.option_lock_landscape, R.string.instance_production,
          R.string.code_link_show_callout
      };
      for (int title : titles) {
        for (boolean checked : new boolean[] {false, true}) {
          adapter.submitList(Collections.singletonList(
              SettingsItem.switchPreference(title, 0, checked, true, true)));
          adapter.onBindViewHolder(holder, 0);
          View toggle = holder.itemView.findViewById(R.id.switchPreference);
          AccessibilityNodeInfo node = toggle.createAccessibilityNodeInfo();
          assertEquals(activity.getString(title), node.getContentDescription().toString());
          assertTrue(node.isCheckable());
          assertEquals(checked, node.isChecked());
          node.recycle();
        }
      }
    } finally {
      controller.pause().stop().destroy();
    }
  }

  @Test public void addInstanceProductionSwitchExposesPurposeAndState() {
    ActivityController<MainActivity> controller = Robolectric.buildActivity(MainActivity.class).setup();
    try {
      MainActivity activity = controller.get();
      View content = activity.getLayoutInflater().inflate(R.layout.dialog_add_api_key, null);
      activity.setContentView(content);
      MaterialSwitch toggle = content.findViewById(R.id.addKeyProduction);
      toggle.setChecked(true);
      AccessibilityNodeInfo node = toggle.createAccessibilityNodeInfo();
      assertEquals(activity.getString(R.string.add_api_key_production_label),
          node.getContentDescription().toString());
      assertTrue(node.isCheckable());
      assertTrue(node.isChecked());
      node.recycle();
    } finally {
      controller.pause().stop().destroy();
    }
  }
}
