package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.app.Application;
import android.app.ForegroundServiceStartNotAllowedException;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
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

  private ServiceController<StashKeepAliveService> started() {
    Application app = RuntimeEnvironment.getApplication();
    Intent intent = new Intent(app, StashKeepAliveService.class)
        .putExtra(StashKeepAliveService.EXTRA_TITLE, "Stash")
        .putExtra(StashKeepAliveService.EXTRA_TEXT, "Paying in the browser");
    return Robolectric.buildService(StashKeepAliveService.class, intent)
        .create().startCommand(0, 1);
  }

  @Test public void startCommandEntersTheForegroundWithTheShortServiceTypeOn34() {
    ServiceController<StashKeepAliveService> controller = started();
    try {
      StashKeepAliveService service = controller.get();
      ShadowService shadow = Shadows.shadowOf(service);
      assertNotNull(shadow.getLastForegroundNotification());
      assertEquals("Stash", shadow.getLastForegroundNotification().extras
          .getCharSequence(android.app.Notification.EXTRA_TITLE).toString());
      assertFalse(shadow.isStoppedBySelf());
      assertFalse(shadow.isForegroundStopped());
      if (Build.VERSION.SDK_INT >= 34) {
        assertEquals(ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE,
            service.getForegroundServiceType());
      }
    } finally {
      controller.destroy();
    }
  }

  @Test @Config(sdk = 34)
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

  @Test public void destroyRemovesTheForegroundNotification() {
    ServiceController<StashKeepAliveService> controller = started();
    controller.destroy();
    ShadowService shadow = Shadows.shadowOf(controller.get());
    assertTrue(shadow.isForegroundStopped());
    assertTrue(shadow.getNotificationShouldRemoved());
  }

  @Test public void stopIsIdempotentAndNullSafe() {
    Application app = RuntimeEnvironment.getApplication();
    StashKeepAliveService.start(app, "Stash", "Paying", 0);
    Intent launched = Shadows.shadowOf(app).getNextStartedService();
    assertNotNull(launched);
    assertEquals(StashKeepAliveService.class.getName(), launched.getComponent().getClassName());
    StashKeepAliveService.stop(app);
    StashKeepAliveService.stop(app);
    StashKeepAliveService.stop(null);
    assertNotNull(Shadows.shadowOf(app).getNextStoppedService());
    assertNotNull(Shadows.shadowOf(app).getNextStoppedService());
    assertNull(Shadows.shadowOf(app).getNextStoppedService());
  }

  @Test @Config(sdk = 34, shadows = StartNotAllowed.class)
  public void startSwallowsAStartNotAllowedException() {
    Application app = RuntimeEnvironment.getApplication();
    StashKeepAliveService.start(app, "Stash", "Paying", 0);
    assertNull(Shadows.shadowOf(app).getNextStartedService());
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
}
