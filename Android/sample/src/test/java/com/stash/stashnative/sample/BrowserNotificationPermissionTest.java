package com.stash.stashnative.sample;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;

import android.Manifest;
import android.content.pm.PackageManager;
import android.view.View;
import android.widget.FrameLayout;
import androidx.recyclerview.widget.RecyclerView;
import com.stash.stashnative.StashNative;
import java.lang.reflect.Method;
import java.util.Collections;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowActivity;
import org.robolectric.util.ReflectionHelpers;

/**
 * A-115: keep-alive's notification permission is asked once and never blocks the browser. U-20:
 * card opens, whose external payments start the same service, ask too, and the keep-alive switch
 * reaches the SDK at once.
 */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public class BrowserNotificationPermissionTest {
  @Test public void browserOpenAsksOnceAndContinuesWhenDenied() throws Exception {
    ActivityController<MainActivity> controller =
        Robolectric.buildActivity(MainActivity.class).setup();
    try {
      MainActivity activity = controller.get();
      ShadowActivity shadow = Shadows.shadowOf(activity);
      Method gate = MainActivity.class.getDeclaredMethod("withNotificationPermission",
          Runnable.class);
      gate.setAccessible(true);
      AtomicInteger opens = new AtomicInteger();
      Runnable open = opens::incrementAndGet;

      assertNull(shadow.getLastRequestedPermission());
      gate.invoke(activity, open);
      ShadowActivity.PermissionsRequest request = shadow.getLastRequestedPermission();
      assertArrayEquals(new String[] {Manifest.permission.POST_NOTIFICATIONS},
          request.requestedPermissions);
      assertEquals("the open waits for the answer", 0, opens.get());

      activity.onRequestPermissionsResult(request.requestCode, request.requestedPermissions,
          new int[] {PackageManager.PERMISSION_DENIED});
      assertEquals("denial still opens the browser", 1, opens.get());

      gate.invoke(activity, open);
      assertEquals(2, opens.get());
      assertSame("asked only once", request, shadow.getLastRequestedPermission());
    } finally {
      controller.pause().stop().destroy();
    }
  }

  @Test public void cardOpensAskBeforeStartingCheckout() {
    String[] opens = {"onOpenCard", "onGenerateCheckout"};
    for (String open : opens) {
      ActivityController<MainActivity> controller =
          Robolectric.buildActivity(MainActivity.class).setup();
      try {
        MainActivity activity = controller.get();
        ShadowActivity shadow = Shadows.shadowOf(activity);
        SettingsAdapter adapter = ReflectionHelpers.getField(activity, "adapter");
        SettingsAdapter.Callbacks callbacks = ReflectionHelpers.getField(adapter, "callbacks");
        ReflectionHelpers.callInstanceMethod(callbacks, open);
        ShadowActivity.PermissionsRequest request = shadow.getLastRequestedPermission();
        assertNotNull(open, request);
        assertArrayEquals(new String[] {Manifest.permission.POST_NOTIFICATIONS},
            request.requestedPermissions);
        assertEquals(open, 0, activity.cardOpenRequests);
        assertNull("no generate request yet", ReflectionHelpers.getField(activity, "pendingRequest"));
        if (open.equals("onOpenCard")) {
          activity.onRequestPermissionsResult(request.requestCode, request.requestedPermissions,
              new int[] {PackageManager.PERMISSION_DENIED});
          assertEquals("denial still opens the card", 1, activity.cardOpenRequests);
        }
      } finally {
        controller.pause().stop().destroy();
        StashNative.getInstance().resetPresentationState();
      }
    }
  }

  @Test public void keepAliveSwitchReachesTheSdkImmediately() {
    ActivityController<MainActivity> controller =
        Robolectric.buildActivity(MainActivity.class).setup();
    try {
      MainActivity activity = controller.get();
      SettingsAdapter adapter = ReflectionHelpers.getField(activity, "adapter");
      FrameLayout parent = new FrameLayout(activity);
      RecyclerView.ViewHolder holder =
          adapter.onCreateViewHolder(parent, SettingsItem.TYPE_SWITCH_PREFERENCE);
      parent.addView(holder.itemView);
      activity.setContentView(parent);
      adapter.submitList(Collections.singletonList(SettingsItem.switchPreference(
          R.string.option_keep_alive, 0, true, true, true)));
      adapter.onBindViewHolder(holder, 0);
      View toggle = holder.itemView.findViewById(R.id.switchPreference);
      assertTrue(StashNative.getInstance().isKeepAliveEnabled());
      toggle.performClick();
      assertFalse(StashNative.getInstance().isKeepAliveEnabled());
      toggle.performClick();
      assertTrue(StashNative.getInstance().isKeepAliveEnabled());
    } finally {
      controller.pause().stop().destroy();
    }
  }
}
