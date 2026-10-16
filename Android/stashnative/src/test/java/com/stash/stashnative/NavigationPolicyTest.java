package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ComponentName;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import java.util.ArrayList;
import java.util.List;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowPackageManager;

/** Web-originated intents resolve only to activities that declare the browser category. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = {21, 23, 28})
public class NavigationPolicyTest {
  private Activity host;

  @Before public void prepare() {
    host = Robolectric.buildActivity(Activity.class).setup().get();
  }

  @Test public void customSchemeExcludesDefaultOnlyTargets() {
    StashCheckoutNavigationSupport.openDeeplinkExternally(host, "auditpay://checkout");
    assertBrowsableTargets(Shadows.shadowOf(host).getNextStartedActivity(), Intent.ACTION_VIEW);
  }

  @Test public void intentUriKeepsPaymentActionAndPackageButRequiresBrowsableTargets() {
    StashCheckoutNavigationSupport.openDeeplinkExternally(host,
        "intent://checkout#Intent;scheme=auditpay;action=com.example.PAY;"
            + "package=com.example.payment;component=com.example.payment/.Internal;end");
    Intent outgoing = Shadows.shadowOf(host).getNextStartedActivity();
    assertNotNull(outgoing);
    assertNull(outgoing.getComponent());
    assertNull(outgoing.getSelector());
    assertEquals("com.example.payment", outgoing.getPackage());
    assertEquals("com.example.PAY", outgoing.getAction());
    assertBrowsableTargets(outgoing, "com.example.PAY");
  }

  private void assertBrowsableTargets(Intent outgoing, String action) {
    assertNotNull(outgoing);
    assertTrue(outgoing.hasCategory(Intent.CATEGORY_BROWSABLE));
    ShadowPackageManager packages = Shadows.shadowOf(host.getPackageManager());
    for (boolean browsable : new boolean[] {false, true}) {
      ComponentName component = new ComponentName("com.example.payment",
          browsable ? "com.example.payment.BrowserPayment" : "com.example.payment.InternalPayment");
      ActivityInfo info = packages.addActivityIfNotPresent(component);
      info.exported = true;
      info.enabled = true;
      IntentFilter filter = new IntentFilter(action);
      filter.addCategory(Intent.CATEGORY_DEFAULT);
      filter.addDataScheme("auditpay");
      if (browsable) {
        filter.addCategory(Intent.CATEGORY_BROWSABLE);
      }
      packages.addIntentFilterForActivity(component, filter);
    }
    List<ResolveInfo> matches = host.getPackageManager().queryIntentActivities(
        outgoing, PackageManager.MATCH_DEFAULT_ONLY);
    assertEquals(1, matches.size());
    assertEquals("com.example.payment.BrowserPayment", matches.get(0).activityInfo.name);
  }

  @Test public void missingPaymentAppRetainsBrowsableWebFallback() {
    FallbackHost fallback = Robolectric.buildActivity(FallbackHost.class).setup().get();
    StashCheckoutNavigationSupport.openDeeplinkExternally(fallback,
        "intent://checkout#Intent;scheme=auditpay;package=com.example.payment;"
            + "S.browser_fallback_url=https%3A%2F%2Fexample.invalid%2Ffallback;end");
    assertEquals(2, fallback.attempts.size());
    Intent web = fallback.attempts.get(1);
    assertEquals("https://example.invalid/fallback", web.getDataString());
    assertTrue(web.hasCategory(Intent.CATEGORY_BROWSABLE));
  }

  @Test public void missingPaymentAppRetainsStoreFallback() {
    FallbackHost fallback = Robolectric.buildActivity(FallbackHost.class).setup().get();
    StashCheckoutNavigationSupport.openDeeplinkExternally(fallback,
        "intent://checkout#Intent;scheme=auditpay;package=com.example.payment;end");
    assertEquals(2, fallback.attempts.size());
    assertEquals("market://details?id=com.example.payment",
        fallback.attempts.get(1).getDataString());
  }

  public static class FallbackHost extends Activity {
    final List<Intent> attempts = new ArrayList<>();

    @Override public void startActivity(Intent intent) {
      attempts.add(intent);
      if ("auditpay".equals(intent.getScheme())) {
        throw new ActivityNotFoundException("No test payment app");
      }
    }
  }
}
