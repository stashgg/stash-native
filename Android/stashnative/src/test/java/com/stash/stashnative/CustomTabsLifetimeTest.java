package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.pm.ResolveInfo;
import android.content.pm.ServiceInfo;
import android.net.Uri;
import android.os.Bundle;
import android.os.Looper;
import androidx.browser.customtabs.CustomTabsCallback;
import androidx.browser.customtabs.CustomTabsService;
import androidx.browser.customtabs.CustomTabsSessionToken;
import androidx.browser.customtabs.EngagementSignalsCallback;
import java.time.Duration;
import java.util.List;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.LooperMode;

/** Exercises the SDK's real Custom Tabs binding with browser-provided callbacks. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
@LooperMode(LooperMode.Mode.PAUSED)
public class CustomTabsLifetimeTest {
  private Activity host;
  private BrowserService browser;
  private int closed;

  @Before public void prepare() {
    host = Robolectric.buildActivity(Activity.class).setup().get();
    browser = Robolectric.buildService(BrowserService.class).create().get();
    String pkg = "com.example.browser";
    ResolveInfo activity = new ResolveInfo();
    activity.activityInfo = new ActivityInfo();
    activity.activityInfo.packageName = pkg;
    activity.activityInfo.name = "BrowserActivity";
    Shadows.shadowOf(host.getPackageManager()).addResolveInfoForIntent(
        new Intent(Intent.ACTION_VIEW, Uri.parse("http://")), activity);
    Intent serviceIntent = new Intent(CustomTabsService.ACTION_CUSTOM_TABS_CONNECTION).setPackage(pkg);
    ResolveInfo service = new ResolveInfo();
    service.serviceInfo = new ServiceInfo();
    service.serviceInfo.packageName = pkg;
    service.serviceInfo.name = BrowserService.class.getName();
    Shadows.shadowOf(host.getPackageManager()).addResolveInfoForIntent(serviceIntent, service);
    Shadows.shadowOf(host.getApplication()).setComponentNameAndServiceForBindService(
        new ComponentName(pkg, service.serviceInfo.name), browser.onBind(serviceIntent));
  }

  @After public void cleanup() {
    StashCustomTabsEngagement.unbindIfBound(host);
    browser.onDestroy();
  }

  private void launch() {
    assertTrue(StashCustomTabsEngagement.tryLaunchForResult(host,
        Uri.parse("https://example.invalid/payment"), CardConstants.REQUEST_CODE_STASH_CUSTOM_TAB,
        mode -> assertEquals(StashUrlLauncher.OPEN_EXTERNAL_CCT_ACTIVITY_FOR_RESULT, mode),
        () -> closed++));
    Shadows.shadowOf(Looper.getMainLooper()).idle();
    assertNotNull(browser.navigation);
    assertNotNull(Shadows.shadowOf(host).getNextStartedActivityForResult());
  }

  @Test public void abortingInitialOrLaterNavigationDoesNotCloseTheTab() {
    launch();
    browser.navigation.onNavigationEvent(CustomTabsCallback.TAB_SHOWN, Bundle.EMPTY);
    for (boolean loaded : new boolean[] {false, true}) {
      if (loaded) browser.navigation.onNavigationEvent(CustomTabsCallback.NAVIGATION_FINISHED, Bundle.EMPTY);
      browser.navigation.onNavigationEvent(CustomTabsCallback.NAVIGATION_STARTED, Bundle.EMPTY);
      browser.navigation.onNavigationEvent(CustomTabsCallback.NAVIGATION_ABORTED, Bundle.EMPTY);
      Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(2));
      assertEquals(0, closed);
      assertFalse(host.isFinishing());
    }
  }

  @Test public void sessionEndStillReportsClosure() {
    launch();
    assertNotNull(browser.engagement);
    browser.engagement.onSessionEnded(true, Bundle.EMPTY);
    browser.engagement.onSessionEnded(true, Bundle.EMPTY);
    Shadows.shadowOf(Looper.getMainLooper()).idle();
    assertEquals(1, closed);
  }

  @Test public void unbindingBeforeServiceConnectCannotLaunchLater() {
    assertTrue(StashCustomTabsEngagement.tryLaunchForResult(host,
        Uri.parse("https://example.invalid/payment"), CardConstants.REQUEST_CODE_STASH_CUSTOM_TAB,
        mode -> { throw new AssertionError("Cancelled binding launched a browser"); }, () -> closed++));
    StashCustomTabsEngagement.unbindIfBound(host);
    Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(3));
    org.junit.Assert.assertNull(Shadows.shadowOf(host).getNextStartedActivityForResult());
    assertEquals(0, closed);
  }

  @Test public void retiredEngagementCallbackCannotCloseOrUnbindReplacement() {
    launch();
    EngagementSignalsCallback retired = browser.engagement;
    launch();
    retired.onSessionEnded(true, Bundle.EMPTY);
    Shadows.shadowOf(Looper.getMainLooper()).idle();
    assertEquals(0, closed);
    browser.engagement.onSessionEnded(true, Bundle.EMPTY);
    Shadows.shadowOf(Looper.getMainLooper()).idle();
    assertEquals(1, closed);
  }

  public static class BrowserService extends CustomTabsService {
    CustomTabsCallback navigation;
    EngagementSignalsCallback engagement;
    @Override protected boolean newSession(CustomTabsSessionToken token) {
      navigation = token.getCallback();
      return true;
    }
    @Override protected boolean isEngagementSignalsApiAvailable(CustomTabsSessionToken token, Bundle extras) {
      return true;
    }
    @Override protected boolean setEngagementSignalsCallback(CustomTabsSessionToken token,
        EngagementSignalsCallback callback, Bundle extras) {
      engagement = callback;
      return true;
    }
    @Override protected boolean warmup(long flags) { return true; }
    @Override protected boolean mayLaunchUrl(CustomTabsSessionToken token, Uri uri, Bundle extras,
        List<Bundle> other) { return false; }
    @Override protected Bundle extraCommand(String command, Bundle args) { return null; }
    @Override protected boolean updateVisuals(CustomTabsSessionToken token, Bundle extras) { return false; }
    @Override protected boolean requestPostMessageChannel(CustomTabsSessionToken token, Uri uri) { return false; }
    @Override protected int postMessage(CustomTabsSessionToken token, String message, Bundle extras) { return 0; }
    @Override protected boolean validateRelationship(CustomTabsSessionToken token, int relation,
        Uri uri, Bundle extras) { return false; }
    @Override protected boolean receiveFile(CustomTabsSessionToken token, Uri uri, int purpose,
        Bundle extras) { return false; }
  }
}
