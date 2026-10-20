package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.content.Context;
import android.os.PowerManager;
import android.webkit.ValueCallback;
import android.webkit.WebView;
import android.widget.FrameLayout;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Set;
import org.json.JSONException;
import org.json.JSONObject;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowSystemClock;

/** Native telemetry schema, navigation accounting, and document isolation. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public class TelemetryTest {
  private StashCardActivity activity;
  private RecordingWebView web;
  private StashTelemetrySupport telemetry;

  @Before
  public void prepare() {
    activity = Robolectric.buildActivity(StashCardActivity.class).get();
    web = new RecordingWebView(activity);
    activity.webView = web;
    activity.rootLayout = new FrameLayout(activity);
    activity.rootLayout.layout(0, 0, 400, 800);
    activity.cardContainer = new StashSheetLayout(activity, 28);
    activity.cardContainer.layout(0, 240, 400, 800);
    activity.options = StashPresentationOptions.card(null);
    activity.presentation = new StashPresentationController(activity, activity.options);
    telemetry = new StashTelemetrySupport(activity);
    activity.telemetrySupport = telemetry;
    telemetry.navigationStarted();
  }

  @After
  public void cleanup() {
    telemetry.dispose();
    web.destroy();
  }

  private static void keys(JSONObject value, String... expected) {
    Set<String> actual = new HashSet<>();
    value.keys().forEachRemaining(actual::add);
    assertEquals(new HashSet<>(Arrays.asList(expected)), actual);
  }

  @Test
  public void snapshotHasCommonSchemaAndLivePresentation() throws Exception {
    JSONObject value = telemetry.snapshot();
    keys(
        value,
        "schemaVersion",
        "platform",
        "hardware",
        "os",
        "app",
        "runtime",
        "presentation",
        "power",
        "timing");
    assertEquals(1, value.getInt("schemaVersion"));
    assertEquals("android", value.getString("platform"));
    keys(value.getJSONObject("hardware"), "manufacturer", "model", "memoryBytes");
    keys(value.getJSONObject("os"), "version", "apiLevel");
    keys(value.getJSONObject("app"), "id", "version", "build", "targetSdkVersion");
    keys(
        value.getJSONObject("runtime"),
        "sdkVersion",
        "webViewEngine",
        "webViewPackage",
        "webViewVersion");
    assertEquals("3.0.0", value.getJSONObject("runtime").getString("sdkVersion"));
    keys(value.getJSONObject("power"), "lowPowerMode", "thermalState");
    assertTrue(value.getJSONObject("power").isNull("thermalState"));
    keys(
        value.getJSONObject("timing"),
        "firstCallAt",
        "pageLoadStartedAt",
        "pageLoadedAt",
        "pageLoadTimeMs");
    JSONObject presentation = value.getJSONObject("presentation");
    keys(
        presentation,
        "state",
        "keyboardVisible",
        "orientationPreference",
        "portraitApplied",
        "window",
        "card",
        "safeAreaInsets",
        "multiWindow",
        "fold");
    keys(presentation.getJSONObject("window"), "width", "height");
    keys(presentation.getJSONObject("card"), "width", "height");
    keys(presentation.getJSONObject("safeAreaInsets"), "top", "right", "bottom", "left");
    keys(presentation.getJSONObject("fold"), "state", "orientation", "separating");
    assertTrue(presentation.getJSONObject("fold").isNull("state"));
    assertEquals("resting", presentation.getString("state"));
    activity.presentation.state.selectExpanded(true);
    activity.presentation.state.keyboardVisible = true;
    JSONObject changed = telemetry.snapshot().getJSONObject("presentation");
    assertEquals("expanded", changed.getString("state"));
    assertTrue(changed.getBoolean("keyboardVisible"));
    assertEquals("resting", presentation.getString("state"));
  }

  private static void paths(JSONObject value, String prefix, List<String> out) throws JSONException {
    Iterator<String> keys = value.keys();
    while (keys.hasNext()) {
      String key = keys.next();
      String path = prefix.isEmpty() ? key : prefix + "." + key;
      out.add(path);
      Object child = value.get(key);
      if (child instanceof JSONObject) {
        paths((JSONObject) child, path, out);
      }
    }
  }

  @Test
  public void snapshotKeysKeepTheOrderSharedWithIos() throws Exception {
    // iOS TelemetryTests asserts the same paths; pages see one key order on both platforms.
    List<String> actual = new ArrayList<>();
    paths(telemetry.snapshot(), "", actual);
    assertEquals(
        Arrays.asList(
            "schemaVersion", "platform",
            "hardware", "hardware.manufacturer", "hardware.model", "hardware.memoryBytes",
            "os", "os.version", "os.apiLevel",
            "app", "app.id", "app.version", "app.build", "app.targetSdkVersion",
            "runtime", "runtime.sdkVersion", "runtime.webViewEngine", "runtime.webViewPackage",
            "runtime.webViewVersion",
            "presentation", "presentation.state", "presentation.keyboardVisible",
            "presentation.window", "presentation.window.width", "presentation.window.height",
            "presentation.card", "presentation.card.width", "presentation.card.height",
            "presentation.safeAreaInsets", "presentation.safeAreaInsets.top",
            "presentation.safeAreaInsets.right", "presentation.safeAreaInsets.bottom",
            "presentation.safeAreaInsets.left",
            "presentation.fold", "presentation.fold.state", "presentation.fold.orientation",
            "presentation.fold.separating",
            "presentation.orientationPreference", "presentation.portraitApplied",
            "presentation.multiWindow",
            "power", "power.lowPowerMode", "power.thermalState",
            "timing", "timing.firstCallAt", "timing.pageLoadStartedAt", "timing.pageLoadedAt",
            "timing.pageLoadTimeMs"),
        actual);
  }

  @Test
  public void loadCompletionIsOncePerNavigationAndFirstCallIsOncePerSession() throws Exception {
    JSONObject first = telemetry.snapshot().getJSONObject("timing");
    assertTrue(first.getLong("firstCallAt") > 0);
    assertTrue(first.isNull("pageLoadedAt"));
    assertTrue(first.isNull("pageLoadTimeMs"));
    ShadowSystemClock.advanceBy(Duration.ofMillis(125));
    telemetry.documentFinished(web, web.url);
    JSONObject loaded = telemetry.snapshot().getJSONObject("timing");
    assertEquals(125, loaded.getLong("pageLoadTimeMs"));
    ShadowSystemClock.advanceBy(Duration.ofMillis(300));
    telemetry.documentFinished(web, web.url);
    assertEquals(loaded.toString(), telemetry.snapshot().getJSONObject("timing").toString());
    telemetry.navigationStarted();
    JSONObject next = telemetry.snapshot().getJSONObject("timing");
    assertTrue(next.isNull("pageLoadedAt"));
    assertTrue(next.isNull("pageLoadTimeMs"));
    assertEquals(first.getLong("firstCallAt"), next.getLong("firstCallAt"));
    ShadowSystemClock.advanceBy(Duration.ofMillis(40));
    telemetry.documentFinished(web, web.url);
    assertEquals(40, telemetry.snapshot().getJSONObject("timing").getLong("pageLoadTimeMs"));
    StashTelemetrySupport replacement = new StashTelemetrySupport(activity);
    assertTrue(replacement.snapshot().getJSONObject("timing").isNull("pageLoadedAt"));
  }

  @Test
  public void stalePageCannotFinishTheNewNavigation() throws Exception {
    telemetry.documentFinished(web, "https://previous.invalid");
    assertTrue(telemetry.snapshot().getJSONObject("timing").isNull("pageLoadedAt"));
    activity.webView = null;
    telemetry.documentFinished(web, web.url);
    assertTrue(telemetry.snapshot().getJSONObject("timing").isNull("pageLoadedAt"));
  }

  @Test
  public void successfulCachedLoadDoesNotDependOnProgressNotificationOrder() throws Exception {
    web.progress = 0;
    ShadowSystemClock.advanceBy(Duration.ofMillis(125));
    telemetry.documentFinished(web, web.url);
    JSONObject timing = telemetry.snapshot().getJSONObject("timing");
    assertFalse(timing.isNull("pageLoadedAt"));
    assertEquals(125, timing.getLong("pageLoadTimeMs"));
  }

  @Test
  public void requestsRequireCurrentCommittedDocumentAndActiveSession() {
    telemetry.documentCommitted(web, web.url);
    String script = web.lastScript;
    String prefix = "var token=\"";
    int start = script.indexOf(prefix) + prefix.length();
    String token = script.substring(start, script.indexOf('"', start));
    telemetry.request("iframe-cannot-read-the-token", 1);
    assertEquals(script, web.lastScript);
    telemetry.request(token, 1);
    assertTrue(web.lastScript.contains("\"schemaVersion\":1"));
    telemetry.navigationStarted();
    web.lastScript = "";
    telemetry.request(token, 2);
    assertEquals("", web.lastScript);
    telemetry.dispose();
    telemetry.documentCommitted(web, web.url);
    assertEquals("", web.lastScript);
  }

  @Test
  @Config(sdk = 21)
  public void oldestSupportedAndroidRetainsKeysForUnsupportedFields() throws Exception {
    JSONObject value = telemetry.snapshot();
    assertTrue(value.getJSONObject("power").isNull("thermalState"));
    assertTrue(value.getJSONObject("presentation").isNull("multiWindow"));
    assertTrue(value.getJSONObject("runtime").isNull("webViewPackage"));
    assertTrue(value.getJSONObject("runtime").isNull("webViewVersion"));
    assertEquals(21, value.getJSONObject("os").getInt("apiLevel"));
  }

  @Test
  public void thermalLevelsUseTheSharedSeverityScale() {
    assertEquals("nominal", StashTelemetrySupport.thermalState(PowerManager.THERMAL_STATUS_NONE));
    assertEquals("fair", StashTelemetrySupport.thermalState(PowerManager.THERMAL_STATUS_LIGHT));
    assertEquals("fair", StashTelemetrySupport.thermalState(PowerManager.THERMAL_STATUS_MODERATE));
    assertEquals("serious", StashTelemetrySupport.thermalState(PowerManager.THERMAL_STATUS_SEVERE));
    assertEquals(
        "critical", StashTelemetrySupport.thermalState(PowerManager.THERMAL_STATUS_CRITICAL));
    assertEquals(
        "critical", StashTelemetrySupport.thermalState(PowerManager.THERMAL_STATUS_EMERGENCY));
    assertEquals(
        "critical", StashTelemetrySupport.thermalState(PowerManager.THERMAL_STATUS_SHUTDOWN));
    assertEquals(JSONObject.NULL, StashTelemetrySupport.thermalState(999));
  }

  private static final class RecordingWebView extends WebView {
    String url = "https://checkout.invalid/test";
    String lastScript;
    int progress = 100;

    RecordingWebView(Context context) {
      super(context);
    }

    @Override
    public String getUrl() {
      return url;
    }

    @Override
    public int getProgress() {
      return progress;
    }

    @Override
    public void evaluateJavascript(String script, ValueCallback<String> callback) {
      lastScript = script;
    }
  }
}
