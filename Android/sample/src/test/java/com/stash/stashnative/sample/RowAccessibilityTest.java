package com.stash.stashnative.sample;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.view.View;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.FrameLayout;
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat;
import androidx.recyclerview.widget.RecyclerView;
import java.util.Collections;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.util.ReflectionHelpers;

/** URL and instance rows announce their purpose; test ids stay in view tags. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = {21, 28, 30})
public class RowAccessibilityTest {
  @Test public void urlRowsSpeakTheirLabelsAndKeepTestIdsInTags() {
    ActivityController<MainActivity> controller = Robolectric.buildActivity(MainActivity.class).setup();
    try {
      MainActivity activity = controller.get();
      SettingsAdapter adapter = ReflectionHelpers.getField(activity, "adapter");
      FrameLayout parent = new FrameLayout(activity);
      RecyclerView.ViewHolder holder = adapter.onCreateViewHolder(
          parent, SettingsItem.TYPE_URL_PREFERENCE);
      parent.addView(holder.itemView);
      activity.setContentView(parent);
      int[] titles = {R.string.hint_checkout_url, R.string.hint_browser_url};
      String[] tags = {"card", "browser"};
      for (int i = 0; i < titles.length; i++) {
        adapter.submitList(Collections.singletonList(SettingsItem.urlPreference(
            titles[i], "https://example.invalid/" + tags[i], 0, true, true)));
        adapter.onBindViewHolder(holder, 0);
        View field = holder.itemView.findViewById(R.id.urlEditText);
        View open = holder.itemView.findViewById(R.id.urlOpenButton);
        assertEquals(tags[i] + "-url-field", field.getTag());
        assertEquals(tags[i] + "-open-button", open.getTag());
        AccessibilityNodeInfo fieldNode = field.createAccessibilityNodeInfo();
        assertNull(fieldNode.getContentDescription());
        // Older TextInputLayout delegates append the hint ("URL") after the value.
        assertTrue(fieldNode.getText().toString().startsWith("https://example.invalid/" + tags[i]));
        fieldNode.recycle();
        AccessibilityNodeInfo openNode = open.createAccessibilityNodeInfo();
        assertEquals(activity.getString(R.string.open_button),
            openNode.getContentDescription().toString());
        openNode.recycle();
      }
      // A recycled row without an Open button drops the ids.
      adapter.submitList(Collections.singletonList(SettingsItem.urlPreference(
          R.string.instance_name, "Howling Woods", 0, true, true)));
      adapter.onBindViewHolder(holder, 0);
      assertNull(holder.itemView.findViewById(R.id.urlEditText).getTag());
      assertNull(holder.itemView.findViewById(R.id.urlOpenButton).getTag());
    } finally {
      controller.pause().stop().destroy();
    }
  }

  @Test public void instanceRadioNamesTheInstanceAndExposesSelection() {
    ActivityController<MainActivity> controller = Robolectric.buildActivity(MainActivity.class).setup();
    try {
      MainActivity activity = controller.get();
      SettingsAdapter adapter = ReflectionHelpers.getField(activity, "adapter");
      FrameLayout parent = new FrameLayout(activity);
      RecyclerView.ViewHolder holder = adapter.onCreateViewHolder(parent, SettingsItem.TYPE_API_KEY);
      parent.addView(holder.itemView);
      activity.setContentView(parent);
      for (boolean selected : new boolean[] {true, false}) {
        adapter.submitList(Collections.singletonList(SettingsItem.apiKey(
            "id-1", "Howling Woods", false, selected, true, true)));
        adapter.onBindViewHolder(holder, 0);
        View radio = holder.itemView.findViewById(R.id.apiKeySelected);
        AccessibilityNodeInfo node = radio.createAccessibilityNodeInfo();
        assertEquals(activity.getString(R.string.instance_select_named, "Howling Woods"),
            node.getContentDescription().toString());
        assertEquals(activity.getString(
                selected ? R.string.instance_selected : R.string.instance_not_selected),
            AccessibilityNodeInfoCompat.wrap(node).getStateDescription().toString());
        node.recycle();
      }
    } finally {
      controller.pause().stop().destroy();
    }
  }
}
