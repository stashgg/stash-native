package com.stash.stashnative;

import android.annotation.SuppressLint;
import android.app.ActivityManager;
import android.content.Context;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageInfo;
import android.content.res.Configuration;
import android.os.Build;
import android.os.PowerManager;
import android.os.SystemClock;
import android.webkit.WebView;
import java.util.UUID;
import org.json.JSONException;
import org.json.JSONObject;

/** Permission-free telemetry for one checkout session. Accessed on the UI thread. */
final class StashTelemetrySupport {
  static final String API_SCRIPT =
      "window.stash_sdk.getTelemetry=function(){"
          + "return new Promise(function(resolve,reject){"
          + "if(window!==window.top||!window.__stashTelemetry){"
          + "reject(new Error('Stash telemetry is not ready'));return;}"
          + "window.__stashTelemetry.request(resolve,reject);});};";

  private final StashCheckoutActivity activity;
  private String documentToken;
  private boolean committed;
  private boolean disposed;
  private long firstCallAt;
  private long pageLoadStartedAt;
  private long pageLoadStartedElapsed;
  private Long pageLoadedAt;
  private Long pageLoadTimeMs;

  StashTelemetrySupport(StashCheckoutActivity activity) {
    this.activity = activity;
  }

  void navigationStarted() {
    documentToken = UUID.randomUUID().toString();
    committed = false;
    pageLoadStartedAt = System.currentTimeMillis();
    pageLoadStartedElapsed = SystemClock.elapsedRealtime();
    pageLoadedAt = null;
    pageLoadTimeMs = null;
  }

  private boolean isCurrentPage(WebView view, String url) {
    return !disposed
        && documentToken != null
        && view == activity.webView
        && url != null
        && url.equals(view.getUrl())
        && !activity.isDismissing;
  }

  void documentCommitted(WebView view, String url) {
    if (!isCurrentPage(view, url)) {
      return;
    }
    committed = true;
    view.evaluateJavascript(documentScript(documentToken), null);
  }

  void documentFinished(WebView view, String url) {
    if (!isCurrentPage(view, url)) {
      return;
    }
    // Cached loads can finish while getProgress() still reports zero.
    if (pageLoadedAt == null) {
      pageLoadedAt = System.currentTimeMillis();
      pageLoadTimeMs = Math.max(0, SystemClock.elapsedRealtime() - pageLoadStartedElapsed);
    }
    documentCommitted(view, url);
  }

  void request(String token, int requestId) {
    if (disposed
        || !committed
        || token == null
        || !token.equals(documentToken)
        || requestId <= 0
        || activity.webView == null
        || activity.isDismissing) {
      return;
    }
    String value;
    try {
      value = snapshot().toString();
    } catch (JSONException | RuntimeException expected) {
      value = "null";
    }
    String script =
        "window.__stashTelemetry&&window.__stashTelemetry.reply("
            + JSONObject.quote(token)
            + ","
            + requestId
            + ","
            + value
            + ");";
    activity.webView.evaluateJavascript(
        script.replace("\u2028", "\\u2028").replace("\u2029", "\\u2029"), null);
  }

  // The platform provider API is sufficient; older OS versions report null provider fields.
  @SuppressLint("WebViewApiAvailability")
  JSONObject snapshot() throws JSONException {
    if (firstCallAt == 0) {
      firstCallAt = System.currentTimeMillis();
    }
    JSONObject app =
        new JSONObject()
            .put("id", activity.getPackageName())
            .put("version", JSONObject.NULL)
            .put("build", JSONObject.NULL)
            .put("targetSdkVersion", activity.getApplicationInfo().targetSdkVersion);
    try {
      PackageInfo info = activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0);
      app.put("version", nullable(info.versionName));
      app.put(
          "build",
          Long.toString(
              Build.VERSION.SDK_INT >= 28 ? info.getLongVersionCode() : info.versionCode));
    } catch (android.content.pm.PackageManager.NameNotFoundException expected) {
      // An unavailable package record leaves optional values null.
    }
    Object memory = JSONObject.NULL;
    ActivityManager manager = (ActivityManager) activity.getSystemService(Context.ACTIVITY_SERVICE);
    if (manager != null) {
      try {
        ActivityManager.MemoryInfo info = new ActivityManager.MemoryInfo();
        manager.getMemoryInfo(info);
        if (info.totalMem > 0) {
          memory = info.totalMem;
        }
      } catch (RuntimeException expected) {
        // System services can be unavailable during shutdown or on vendor builds.
      }
    }
    JSONObject runtime =
        new JSONObject()
            .put("sdkVersion", StashNativeCard.getVersion())
            .put("webViewEngine", "chromium")
            .put("webViewPackage", JSONObject.NULL)
            .put("webViewVersion", JSONObject.NULL);
    if (Build.VERSION.SDK_INT >= 26) {
      try {
        PackageInfo provider = WebView.getCurrentWebViewPackage();
        if (provider != null) {
          runtime.put("webViewPackage", nullable(provider.packageName));
          runtime.put("webViewVersion", nullable(provider.versionName));
        }
      } catch (Throwable expected) {
        // Broken or unavailable providers must not break a telemetry request.
      }
    }
    PowerManager power = (PowerManager) activity.getSystemService(Context.POWER_SERVICE);
    Object lowPower = JSONObject.NULL;
    Object thermal = JSONObject.NULL;
    if (power != null) {
      try {
        lowPower = power.isPowerSaveMode();
        if (Build.VERSION.SDK_INT >= 29) {
          thermal = thermalState(power.getCurrentThermalStatus());
        }
      } catch (RuntimeException expected) {
        // Keep unavailable power fields null.
      }
    }
    boolean portraitRequested =
        activity.options != null
            && activity.options.orientation == StashNativeCard.CardConfig.ORIENTATION_PORTRAIT;
    JSONObject presentation =
        activity.presentation == null ? emptyPresentation() : activity.presentation.telemetry();
    presentation
        .put("orientationPreference", portraitRequested ? "portrait" : "followHost")
        .put(
            "portraitApplied",
            portraitRequested
                && activity.getRequestedOrientation() == ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                && activity.getResources().getConfiguration().orientation
                    == Configuration.ORIENTATION_PORTRAIT)
        .put(
            "multiWindow",
            Build.VERSION.SDK_INT >= 24 ? activity.isInMultiWindowMode() : JSONObject.NULL);
    return new JSONObject()
        .put("schemaVersion", 1)
        .put("platform", "android")
        .put(
            "hardware",
            new JSONObject()
                .put("manufacturer", nullable(Build.MANUFACTURER))
                .put("model", nullable(Build.MODEL))
                .put("memoryBytes", memory))
        .put(
            "os",
            new JSONObject()
                .put("version", nullable(Build.VERSION.RELEASE))
                .put("apiLevel", Build.VERSION.SDK_INT))
        .put("app", app)
        .put("runtime", runtime)
        .put("presentation", presentation)
        .put("power", new JSONObject().put("lowPowerMode", lowPower).put("thermalState", thermal))
        .put(
            "timing",
            new JSONObject()
                .put("firstCallAt", firstCallAt)
                .put(
                    "pageLoadStartedAt",
                    pageLoadStartedAt == 0 ? JSONObject.NULL : pageLoadStartedAt)
                .put("pageLoadedAt", pageLoadedAt == null ? JSONObject.NULL : pageLoadedAt)
                .put("pageLoadTimeMs", pageLoadTimeMs == null ? JSONObject.NULL : pageLoadTimeMs));
  }

  static Object thermalState(int status) {
    switch (status) {
      case PowerManager.THERMAL_STATUS_NONE:
        return "nominal";
      case PowerManager.THERMAL_STATUS_LIGHT:
      case PowerManager.THERMAL_STATUS_MODERATE:
        return "fair";
      case PowerManager.THERMAL_STATUS_SEVERE:
        return "serious";
      case PowerManager.THERMAL_STATUS_CRITICAL:
      case PowerManager.THERMAL_STATUS_EMERGENCY:
      case PowerManager.THERMAL_STATUS_SHUTDOWN:
        return "critical";
      default:
        return JSONObject.NULL;
    }
  }

  private static Object nullable(String value) {
    return value == null || value.isEmpty() || Build.UNKNOWN.equals(value)
        ? JSONObject.NULL
        : value;
  }

  static JSONObject emptyPresentation() throws JSONException {
    return new JSONObject()
        .put("state", JSONObject.NULL)
        .put("keyboardVisible", JSONObject.NULL)
        .put("window", dimensions(null, null))
        .put("card", dimensions(null, null))
        .put(
            "safeAreaInsets",
            new JSONObject()
                .put("top", JSONObject.NULL)
                .put("right", JSONObject.NULL)
                .put("bottom", JSONObject.NULL)
                .put("left", JSONObject.NULL))
        .put(
            "fold",
            new JSONObject()
                .put("state", JSONObject.NULL)
                .put("orientation", JSONObject.NULL)
                .put("separating", JSONObject.NULL));
  }

  static JSONObject dimensions(Number width, Number height) throws JSONException {
    return new JSONObject()
        .put("width", width == null ? JSONObject.NULL : width)
        .put("height", height == null ? JSONObject.NULL : height);
  }

  void dispose() {
    disposed = true;
    documentToken = null;
  }

  static String documentScript(String token) {
    return "(function(){if(window!==window.top)return;var token="
        + JSONObject.quote(token)
        + ";"
        + "if(window.__stashTelemetry&&window.__stashTelemetry.token===token)return;"
        + "if(window.__stashTelemetry)window.__stashTelemetry.cancel();"
        + "var pending=Object.create(null),next=0;"
        + "function settle(id,value,error){var p=pending[id];if(!p)return;"
        + "delete pending[id];clearTimeout(p.timer);"
        + "if(error)p.reject(new Error(error));else p.resolve(value);}"
        + "var bridge={token:token,request:function(resolve,reject){"
        + "var id=++next;pending[id]={resolve:resolve,reject:reject,"
        + "timer:setTimeout(function(){settle(id,null,'Stash telemetry timed out');},10000)};"
        + "try{StashAndroid.getTelemetry(token,id);}"
        + "catch(e){settle(id,null,'Stash telemetry is unavailable');}},"
        + "reply:function(t,id,value){if(t===token)settle(id,value,"
        + "value?null:'Stash telemetry is unavailable');},"
        + "cancel:function(){Object.keys(pending).forEach(function(id){"
        + "settle(id,null,'Stash telemetry document changed');});}};"
        + "window.__stashTelemetry=bridge;"
        + "window.addEventListener('pagehide',bridge.cancel);"
        + "window.stash_sdk=window.stash_sdk||{};"
        + API_SCRIPT
        + "})();";
  }
}
