package com.stash.stashnative.sample;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.net.Uri;
import android.widget.LinearLayout;
import android.widget.TextView;
import com.stash.stashnative.StashNative;
import com.stash.stashnative.sample.databinding.ActivityMainBinding;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import org.junit.After;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Shadows;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.util.ReflectionHelpers;

/** U-03: a stashdemo:// deeplink must not clear an open card above MainActivity. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public class DeepLinkActivityTest {
  private static final String PASSTHROUGH = "stashdemo://misc/passthrough";

  @After public void resetSdk() {
    StashNative.getInstance().resetPresentationState();
  }

  @Test public void stashdemoLinksResolveToTheTrampolineAndMainActivityIsStandard()
      throws Exception {
    PackageManager pm = RuntimeEnvironment.getApplication().getPackageManager();
    Intent view = new Intent(Intent.ACTION_VIEW, Uri.parse(PASSTHROUGH))
        .addCategory(Intent.CATEGORY_BROWSABLE);
    List<ResolveInfo> handlers = pm.queryIntentActivities(view, 0);
    assertEquals(1, handlers.size());
    assertEquals(DeepLinkActivity.class.getName(), handlers.get(0).activityInfo.name);
    ActivityInfo main = pm.getActivityInfo(
        new ComponentName(RuntimeEnvironment.getApplication(), MainActivity.class), 0);
    assertEquals(ActivityInfo.LAUNCH_MULTIPLE, main.launchMode);
  }

  @Test public void withoutACardTheLinkReturnsToMainActivityClosingTheBrowser() {
    DeepLinkActivity trampoline = Robolectric.buildActivity(DeepLinkActivity.class,
        new Intent(Intent.ACTION_VIEW, Uri.parse("stashdemo://stash-pay/success"))).create().get();
    assertTrue(trampoline.isFinishing());
    Intent forwarded = Shadows.shadowOf(trampoline).getNextStartedActivity();
    assertNotNull(forwarded);
    assertEquals(MainActivity.class.getName(), forwarded.getComponent().getClassName());
    // Launcher-equivalent root intent, so a later launcher tap resumes the task.
    assertEquals(Intent.ACTION_MAIN, forwarded.getAction());
    assertTrue(forwarded.hasCategory(Intent.CATEGORY_LAUNCHER));
    assertNull(forwarded.getData());
    int flags = Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP
        | Intent.FLAG_ACTIVITY_SINGLE_TOP;
    assertEquals(flags, forwarded.getFlags() & flags);
    assertEquals("stashdemo://stash-pay/success",
        forwarded.getStringExtra(MainActivity.EXTRA_DEEP_LINK));

    ActivityController<MainActivity> controller =
        Robolectric.buildActivity(MainActivity.class, forwarded).setup();
    try {
      assertEquals(Arrays.asList("Deeplink · Payment Success"), chips(controller.get()));
      controller.newIntent(DeepLinkActivity.mainIntent(
          controller.get(), Uri.parse("stashdemo://stash-pay/cancel")));
      assertEquals(Arrays.asList("Deeplink · Cancel", "Deeplink · Payment Success"),
          chips(controller.get()));
    } finally {
      controller.pause().stop().destroy();
    }
  }

  @Test public void withACardOpenTheLinkIsShownWithoutRelaunchingMainActivity() {
    ActivityController<MainActivity> controller =
        Robolectric.buildActivity(MainActivity.class).setup();
    try {
      MainActivity activity = controller.get();
      StashNative.getInstance().openCard(activity, "https://example.invalid/checkout",
          new StashNative.CardConfig());
      assertTrue(StashNative.getInstance().isCurrentlyPresented());
      assertNotNull("card started", Shadows.shadowOf(activity).getNextStartedActivity());

      DeepLinkActivity trampoline = Robolectric.buildActivity(DeepLinkActivity.class,
          new Intent(Intent.ACTION_VIEW, Uri.parse(PASSTHROUGH))).create().get();
      assertTrue(trampoline.isFinishing());
      assertNull("no clear-top relaunch", Shadows.shadowOf(trampoline).getNextStartedActivity());
      assertNull(Shadows.shadowOf(activity).getNextStartedActivity());
      assertTrue(StashNative.getInstance().isCurrentlyPresented());
      assertEquals(Arrays.asList("Deeplink · " + PASSTHROUGH), chips(activity));
    } finally {
      controller.pause().stop().destroy();
    }
  }

  @Test public void otherSchemesAreIgnored() {
    DeepLinkActivity trampoline = Robolectric.buildActivity(DeepLinkActivity.class,
        new Intent(Intent.ACTION_VIEW, Uri.parse("https://example.invalid/"))).create().get();
    assertTrue(trampoline.isFinishing());
    assertNull(Shadows.shadowOf(trampoline).getNextStartedActivity());
    assertFalse(StashNative.getInstance().isCurrentlyPresented());
  }

  private static List<String> chips(MainActivity activity) {
    ActivityMainBinding binding = ReflectionHelpers.getField(activity, "binding");
    LinearLayout container = binding.callbackChipContainer;
    List<String> labels = new ArrayList<>();
    for (int i = 0; i < container.getChildCount(); i++) {
      LinearLayout row = (LinearLayout) container.getChildAt(i);
      labels.add(((TextView) row.getChildAt(0)).getText().toString());
    }
    return labels;
  }
}
