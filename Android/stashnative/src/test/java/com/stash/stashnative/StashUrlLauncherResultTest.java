package com.stash.stashnative;

import static org.junit.Assert.assertEquals;

import android.app.Activity;
import android.content.Intent;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public class StashUrlLauncherResultTest {

  private static final String URL = "https://example.invalid/pay";

  @Test
  public void invalidInputReportsNoLaunch() {
    Activity host = host();
    assertEquals(
        StashUrlLauncher.OPEN_EXTERNAL_NONE,
        StashUrlLauncher.launchExternalUrl(null, "https://example.invalid", 0));
    assertEquals(
        StashUrlLauncher.OPEN_EXTERNAL_NONE, StashUrlLauncher.launchExternalUrl(host, null, 0));
    assertEquals(
        StashUrlLauncher.OPEN_EXTERNAL_NONE,
        StashUrlLauncher.launchExternalUrl(host, "ftp://example.invalid/pay", 0));
    assertEquals(
        StashUrlLauncher.OPEN_EXTERNAL_ACTION_VIEW,
        StashUrlLauncher.openExternalUrl(host, "ftp://example.invalid/pay", 0));
  }

  @Test
  public void unresolvableBrowserReportsNoLaunchButPublicResultIsUnchanged() {
    Activity host = host();
    Shadows.shadowOf(host.getApplication()).checkActivities(true);
    try {
      assertEquals(
          StashUrlLauncher.OPEN_EXTERNAL_NONE, StashUrlLauncher.launchExternalUrl(host, URL, 0));
      assertEquals(
          StashUrlLauncher.OPEN_EXTERNAL_ACTION_VIEW,
          StashUrlLauncher.openExternalUrl(host, URL, 0));
      assertEquals(
          StashUrlLauncher.OPEN_EXTERNAL_ACTION_VIEW, StashUrlLauncher.openExternalUrl(host, URL));
    } finally {
      Shadows.shadowOf(host.getApplication()).checkActivities(false);
    }
  }

  @Test
  public void resolvableSystemBrowserReportsActionView() {
    Activity host = host();
    assertEquals(
        StashUrlLauncher.OPEN_EXTERNAL_ACTION_VIEW,
        StashUrlLauncher.launchExternalUrl(host, URL, 0));
    Intent started = Shadows.shadowOf(host).getNextStartedActivity();
    assertEquals(Intent.ACTION_VIEW, started.getAction());
    assertEquals(URL, started.getDataString());
  }

  private static Activity host() {
    return Robolectric.buildActivity(Activity.class).setup().get();
  }
}
