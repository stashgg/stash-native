package com.stash.stashnative.sample;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertSame;

import android.Manifest;
import android.content.pm.PackageManager;
import java.lang.reflect.Method;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowActivity;

/** A-115: keep-alive's notification permission is asked once and never blocks the browser. */
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
}
