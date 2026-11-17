package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.app.Application;
import android.app.ForegroundServiceStartNotAllowedException;
import android.app.Notification;
import android.app.Service;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Shadows;
import org.robolectric.android.controller.ServiceController;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.Implementation;
import org.robolectric.annotation.Implements;
import org.robolectric.annotation.LooperMode;
import org.robolectric.shadows.ShadowContextImpl;
import org.robolectric.shadows.ShadowService;

/** Foreground lifecycle of the optional keep-alive service on O and on 14's short-service rules. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = {26, 34})
@LooperMode(LooperMode.Mode.PAUSED)
public class KeepAliveServiceTest {

  @Before
  public void resetStartTracking() {
    StashKeepAliveService.resetStartTrackingForTests();
  }

  private ServiceController<StashKeepAliveService> started() {
    Application app = RuntimeEnvironment.getApplication();
    Intent intent =
        new Intent(app, StashKeepAliveService.class)
            .putExtra(StashKeepAliveService.EXTRA_TITLE, "Stash")
            .putExtra(StashKeepAliveService.EXTRA_TEXT, "Paying in the browser");
    return Robolectric.buildService(StashKeepAliveService.class, intent).create().startCommand(0, 1);
  }

  @Test
  public void startCommandEntersTheForegroundWithTheShortServiceTypeOn34() {
    ServiceController<StashKeepAliveService> controller = started();
    try {
      StashKeepAliveService service = controller.get();
      ShadowService shadow = Shadows.shadowOf(service);
      assertNotNull(shadow.getLastForegroundNotification());
      assertEquals(
          "Stash",
          shadow.getLastForegroundNotification().extras
              .getCharSequence(Notification.EXTRA_TITLE)
              .toString());
      assertFalse(shadow.isStoppedBySelf());
      assertFalse(shadow.isForegroundStopped());
      if (Build.VERSION.SDK_INT >= 34) {
        assertEquals(
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE, service.getForegroundServiceType());
      }
    } finally {
      controller.destroy();
    }
  }

  @Test
  @Config(sdk = 34)
  public void timeoutLeavesTheForegroundAndStopsTheService() {
    ServiceController<StashKeepAliveService> controller = started();
    try {
      StashKeepAliveService service = controller.get();
      service.onTimeout(1);
      ShadowService shadow = Shadows.shadowOf(service);
      assertTrue(shadow.isForegroundStopped());
      assertTrue(shadow.isStoppedBySelf());
    } finally {
      controller.destroy();
    }
  }

  @Test
  public void destroyRemovesTheForegroundNotification() {
    ServiceController<StashKeepAliveService> controller = started();
    controller.destroy();
    ShadowService shadow = Shadows.shadowOf(controller.get());
    assertTrue(shadow.isForegroundStopped());
    assertTrue(shadow.getNotificationShouldRemoved());
  }

  @Test
  public void stopAfterForegroundEntryReachesTheRunningService() {
    Application app = RuntimeEnvironment.getApplication();
    StashKeepAliveService.start(app, "Stash", "Paying", 0);
    Intent launched = Shadows.shadowOf(app).getNextStartedService();
    assertNotNull(launched);
    assertEquals(StashKeepAliveService.class.getName(), launched.getComponent().getClassName());
    ServiceController<StashKeepAliveService> controller =
        Robolectric.buildService(StashKeepAliveService.class, launched).create().startCommand(0, 1);
    try {
      StashKeepAliveService.stop(app);
      StashKeepAliveService.stop(null);
      assertNotNull(Shadows.shadowOf(app).getNextStoppedService());
      assertNull(Shadows.shadowOf(app).getNextStoppedService());
    } finally {
      controller.destroy();
    }
  }

  /** Stopping before startForeground crashes the host on 8+, so the service promotes first. */
  @Test
  public void stopBeforeTheServiceEntersTheForegroundWaitsForIt() {
    Application app = RuntimeEnvironment.getApplication();
    StashKeepAliveService.start(app, "Stash", "Paying", 0);
    Intent launched = Shadows.shadowOf(app).getNextStartedService();
    StashKeepAliveService.stop(app);
    assertNull(Shadows.shadowOf(app).getNextStoppedService());
    ServiceController<StashKeepAliveService> controller =
        Robolectric.buildService(StashKeepAliveService.class, launched).create().startCommand(0, 1);
    try {
      ShadowService shadow = Shadows.shadowOf(controller.get());
      assertNotNull(shadow.getLastForegroundNotification());
      assertTrue(shadow.isStoppedBySelf());
      // Later stops reach the running service directly again.
      StashKeepAliveService.stop(app);
      assertNotNull(Shadows.shadowOf(app).getNextStoppedService());
    } finally {
      controller.destroy();
    }
  }

  /** A start after a deferred stop cancels that stop. */
  @Test
  public void startAfterADeferredStopKeepsTheService() {
    Application app = RuntimeEnvironment.getApplication();
    StashKeepAliveService.start(app, "Stash", "Paying", 0);
    Intent launched = Shadows.shadowOf(app).getNextStartedService();
    StashKeepAliveService.stop(app);
    StashKeepAliveService.start(app, "Stash", "Paying", 0);
    ServiceController<StashKeepAliveService> controller =
        Robolectric.buildService(StashKeepAliveService.class, launched)
            .create()
            .startCommand(0, 1)
            .startCommand(0, 2);
    try {
      assertFalse(Shadows.shadowOf(controller.get()).isStoppedBySelf());
    } finally {
      controller.destroy();
    }
  }

  /** The deferred stop fires only once every overlapping start has settled. */
  @Test
  public void overlappingStartsDeferTheStopUntilTheLastOneSettles() {
    Application app = RuntimeEnvironment.getApplication();
    StashKeepAliveService.start(app, "Stash", "Paying", 0);
    StashKeepAliveService.start(app, "Stash", "Paying", 0);
    Intent launched = Shadows.shadowOf(app).getNextStartedService();
    StashKeepAliveService.stop(app);
    assertNull(Shadows.shadowOf(app).getNextStoppedService());
    ServiceController<StashKeepAliveService> controller =
        Robolectric.buildService(StashKeepAliveService.class, launched).create().startCommand(0, 1);
    try {
      ShadowService shadow = Shadows.shadowOf(controller.get());
      assertFalse(shadow.isStoppedBySelf());
      controller.startCommand(0, 2);
      assertTrue(shadow.isStoppedBySelf());
    } finally {
      controller.destroy();
    }
  }

  @Test
  @Config(sdk = 34, shadows = StartNotAllowed.class)
  public void startSwallowsAStartNotAllowedException() {
    Application app = RuntimeEnvironment.getApplication();
    StashKeepAliveService.start(app, "Stash", "Paying", 0);
    assertNull(Shadows.shadowOf(app).getNextStartedService());
  }

  /** A rejected start leaves no pending count, so a stop is not deferred forever. */
  @Test
  @Config(sdk = 34, shadows = StartNotAllowed.class)
  public void rejectedStartLeavesNoPendingCount() {
    Application app = RuntimeEnvironment.getApplication();
    StashKeepAliveService.start(app, "Stash", "Paying", 0);
    StashKeepAliveService.stop(app);
    assertNotNull(Shadows.shadowOf(app).getNextStoppedService());
  }

  /** A failed startForeground still settles the pending count. */
  @Test
  @Config(sdk = 26, shadows = ForegroundRejected.class)
  public void startForegroundFailureStillSettlesThePendingCount() {
    Application app = RuntimeEnvironment.getApplication();
    StashKeepAliveService.start(app, "Stash", "Paying", 0);
    Intent launched = Shadows.shadowOf(app).getNextStartedService();
    StashKeepAliveService.stop(app);
    assertNull(Shadows.shadowOf(app).getNextStoppedService());
    // No destroy: the replacement shadow has no stopForeground, and @Before resets the count.
    Robolectric.buildService(StashKeepAliveService.class, launched).create().startCommand(0, 1);
    // The deferred stop was consumed and the count settled, so a later stop is not deferred.
    StashKeepAliveService.stop(app);
    assertNotNull(Shadows.shadowOf(app).getNextStoppedService());
  }

  /** Android 12+ refuses foreground starts from the background with this exception. */
  @Implements(className = "android.app.ContextImpl")
  public static class StartNotAllowed extends ShadowContextImpl {
    @Implementation(minSdk = Build.VERSION_CODES.O)
    @Override
    protected ComponentName startForegroundService(Intent service) {
      throw new ForegroundServiceStartNotAllowedException("app is in the background");
    }
  }

  /** Forces the pre-14 startForeground call to fail. */
  @Implements(Service.class)
  public static class ForegroundRejected {
    @Implementation
    protected void startForeground(int id, Notification notification) {
      throw new IllegalStateException("startForeground rejected");
    }
  }
}
