package com.stash.stashnative;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

/**
 * Opens http(s) URLs in Chrome Custom Tabs when {@code androidx.browser} is on the classpath and
 * reflection succeeds; otherwise falls back to {@link Intent#ACTION_VIEW}. No compile-time
 * references to {@code androidx.browser.*}.
 */
public final class StashUrlLauncher {

  private static final String TAG = "StashUrlLauncher";

  /** Custom Tabs launched with {@link Activity#startActivityForResult}; the result is owned internally by {@link StashNativeBrowserProxyActivity}. */
  public static final int OPEN_EXTERNAL_CCT_ACTIVITY_FOR_RESULT = 1;
  /** Custom Tabs via {@code launchUrl} / {@code startActivity} (no activity result). */
  public static final int OPEN_EXTERNAL_CCT = 2;
  /** System browser ({@code ACTION_VIEW}). */
  public static final int OPEN_EXTERNAL_ACTION_VIEW = 3;

  /** Delivers the same launch mode values as {@link #openExternalUrl(Context, String, int)}. */
  public interface LaunchModeCallback {
    void onLaunchMode(int launchMode);
  }

  private static final String CLASS_CUSTOM_TABS_INTENT = "androidx.browser.customtabs.CustomTabsIntent";
  private static final String CLASS_CUSTOM_TABS_INTENT_BUILDER =
      "androidx.browser.customtabs.CustomTabsIntent$Builder";
  private static final String CLASS_COLOR_SCHEME_PARAMS =
      "androidx.browser.customtabs.CustomTabColorSchemeParams";
  private static final String CLASS_COLOR_SCHEME_PARAMS_BUILDER =
      "androidx.browser.customtabs.CustomTabColorSchemeParams$Builder";

  private StashUrlLauncher() {}

  /**
   * True if {@code androidx.browser.customtabs.CustomTabsIntent} is loadable (dependency present).
   */
  public static boolean isCustomTabsClassAvailable() {
    try {
      Class.forName(CLASS_CUSTOM_TABS_INTENT);
      return true;
    } catch (ClassNotFoundException e) {
      return false;
    }
  }

  /**
   * Opens URL with Chrome Custom Tabs when possible. When {@code context} is an {@link Activity}
   * and {@code activityRequestCode} is non-zero, CCT uses {@code startActivityForResult} and {@link
   * StashNativeBrowserProxyActivity} receives the result; otherwise CCT
   * uses {@code startActivity}. Falls back to {@link Intent#ACTION_VIEW}.
   *
   * @param activityRequestCode 0 for no result contract; else pass {@link
   *     CardConstants#REQUEST_CODE_STASH_CUSTOM_TAB}
   * @return one of {@link #OPEN_EXTERNAL_CCT_ACTIVITY_FOR_RESULT}, {@link #OPEN_EXTERNAL_CCT},
   *     {@link #OPEN_EXTERNAL_ACTION_VIEW}
   */
  public static int openExternalUrl(
      @Nullable Context context, @Nullable String url, int activityRequestCode) {
    if (context == null || url == null) {
      return OPEN_EXTERNAL_ACTION_VIEW;
    }
    Uri uri = parseHttpUri(url);
    if (uri == null) {
      Log.w(TAG, "Invalid URL or unsupported scheme");
      return OPEN_EXTERNAL_ACTION_VIEW;
    }

    if (context instanceof Activity
        && activityRequestCode != 0
        && tryLaunchCustomTabsForResult((Activity) context, uri, activityRequestCode)) {
      return OPEN_EXTERNAL_CCT_ACTIVITY_FOR_RESULT;
    }
    if (tryLaunchCustomTabsNoResult(context, uri)) {
      return OPEN_EXTERNAL_CCT;
    }
    try {
      startActionView(context, uri);
      return OPEN_EXTERNAL_ACTION_VIEW;
    } catch (ActivityNotFoundException e) {
      Log.w(TAG, "No application can open URL: " + uri);
      return OPEN_EXTERNAL_ACTION_VIEW;
    }
  }

  /**
   * Like {@link #openExternalUrl(Context, String, int)} for an {@link Activity}, but may bind Custom
   * Tabs first. Engagement signals ({@code EngagementSignalsCallback}) deliver {@code
   * onSessionEnded} when the tab is closed from floating/minimized UI. Pass a runnable that forwards
   * to {@code StashNativeCardPlugin.onCustomTabsEngagementSessionEnded}.
   */
  public static void openExternalUrl(
      @Nullable Activity activity,
      @Nullable String url,
      int activityRequestCode,
      @NonNull LaunchModeCallback callback,
      @Nullable Runnable engagementSessionEnded) {
    Uri uri = parseHttpUri(url);
    if (activity == null || uri == null) {
      if (activity != null && uri != null) {
        try {
          startActionView(activity, uri);
        } catch (ActivityNotFoundException e) {
          Log.w(TAG, "No application can open URL");
        }
      }
      callback.onLaunchMode(OPEN_EXTERNAL_ACTION_VIEW);
      return;
    }
    if (activityRequestCode == 0 || !isCustomTabsClassAvailable()) {
      callback.onLaunchMode(openExternalUrl(activity, url, activityRequestCode));
      return;
    }
    try {
      Class<?> eng = Class.forName("com.stash.stashnative.StashCustomTabsEngagement");
      Method m =
          eng.getMethod(
              "tryLaunchForResult",
              Activity.class,
              Uri.class,
              int.class,
              LaunchModeCallback.class,
              Runnable.class);
      Runnable ended = engagementSessionEnded != null ? engagementSessionEnded : () -> {};
      Boolean started =
          (Boolean)
              m.invoke(null, activity, uri, activityRequestCode, callback, ended);
      if (Boolean.TRUE.equals(started)) {
        return;
      }
    } catch (Throwable t) {
      Log.w(TAG, "Engagement path failed: " + t.getMessage());
    }
    callback.onLaunchMode(openExternalUrl(activity, url, activityRequestCode));
  }

  /**
   * Unbinds the Custom Tabs service used for engagement callbacks after the tab finishes or when
   * {@link StashNativeBrowserProxyActivity} receives the activity result.
   */
  public static void unbindCustomTabsEngagement(@Nullable Context context) {
    if (context == null) {
      return;
    }
    try {
      Class<?> eng = Class.forName("com.stash.stashnative.StashCustomTabsEngagement");
      eng.getMethod("unbindIfBound", Context.class).invoke(null, context.getApplicationContext());
    } catch (Throwable ignored) {
      // Engagement class or androidx.browser absent
    }
  }

  @Nullable
  private static Uri parseHttpUri(@Nullable String url) {
    if (url == null) {
      return null;
    }
    String trimmed = url.trim();
    if (trimmed.isEmpty()) {
      return null;
    }
    Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (Exception e) {
      return null;
    }
    String scheme = uri.getScheme();
    if (scheme == null) {
      return null;
    }
    String sch = scheme.toLowerCase();
    if (!"http".equals(sch) && !"https".equals(sch)) {
      return null;
    }
    if (uri.getHost() == null || uri.getHost().isEmpty()) {
      return null;
    }
    return uri;
  }

  /**
   * Same as {@link #openExternalUrl(Context, String, int)} with {@link
   * CardConstants#REQUEST_CODE_STASH_CUSTOM_TAB} when {@code context} is an {@link Activity},
   * otherwise request code 0.
   */
  public static int openExternalUrl(@Nullable Context context, @Nullable String url) {
    int code =
        (context instanceof Activity) ? CardConstants.REQUEST_CODE_STASH_CUSTOM_TAB : 0;
    return openExternalUrl(context, url, code);
  }

  private static void startActionView(Context context, Uri uri) {
    Intent intent = new Intent(Intent.ACTION_VIEW, uri);
    if (!(context instanceof Activity)) {
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    }
    context.startActivity(intent);
  }

  private static boolean tryLaunchCustomTabsForResult(
      Activity activity, Uri uri, int requestCode) {
    try {
      Object customTabsIntent = buildCustomTabsIntent();
      if (customTabsIntent == null) {
        return false;
      }
      Class<?> ctiCls = Class.forName(CLASS_CUSTOM_TABS_INTENT);
      return launchCustomTabsIntentForResult(ctiCls, customTabsIntent, activity, uri, requestCode);
    } catch (ClassNotFoundException e) {
      return false;
    } catch (Throwable t) {
      Log.w(TAG, "Custom Tabs forResult failed: " + t.getMessage());
      return false;
    }
  }

  private static boolean tryLaunchCustomTabsNoResult(Context context, Uri uri) {
    try {
      Object customTabsIntent = buildCustomTabsIntent();
      if (customTabsIntent == null) {
        return false;
      }
      Class<?> ctiCls = Class.forName(CLASS_CUSTOM_TABS_INTENT);
      if (invokeLaunchUrl(ctiCls, customTabsIntent, context, uri)) {
        return true;
      }
      return launchViaIntentFieldStartActivity(ctiCls, customTabsIntent, context, uri);
    } catch (ClassNotFoundException e) {
      return false;
    } catch (Throwable t) {
      Log.w(TAG, "Custom Tabs reflection failed: " + t.getMessage());
      return false;
    }
  }

  @Nullable
  private static Object buildCustomTabsIntent() throws Exception {
    Class<?> builderCls = Class.forName(CLASS_CUSTOM_TABS_INTENT_BUILDER);
    Object builder = builderCls.getConstructor().newInstance();

    try {
      Method setShowTitle = builderCls.getMethod("setShowTitle", boolean.class);
      setShowTitle.invoke(builder, true);
    } catch (Throwable ignored) {
      // older API
    }

    try {
      applyToolbarColorReflect(builder, builderCls);
    } catch (Throwable ignored) {
      // optional styling
    }

    return builderCls.getMethod("build").invoke(builder);
  }

  private static void applyToolbarColorReflect(Object builder, Class<?> builderCls)
      throws Exception {
    Class<?> schemeBuilderCls = Class.forName(CLASS_COLOR_SCHEME_PARAMS_BUILDER);
    Object schemeBuilder = schemeBuilderCls.getConstructor().newInstance();
    int toolbarColor = Color.parseColor(CardConstants.COLOR_DARK_BG);
    schemeBuilderCls.getMethod("setToolbarColor", int.class).invoke(schemeBuilder, toolbarColor);
    Object colorParams = schemeBuilderCls.getMethod("build").invoke(schemeBuilder);
    Class<?> colorParamsCls = Class.forName(CLASS_COLOR_SCHEME_PARAMS);
    Method setDefault =
        builderCls.getMethod("setDefaultColorSchemeParams", colorParamsCls);
    setDefault.invoke(builder, colorParams);
  }

  private static boolean invokeLaunchUrl(
      Class<?> ctiCls, Object customTabsIntent, Context context, Uri uri) {
    try {
      Method m = ctiCls.getMethod("launchUrl", Context.class, Uri.class);
      m.invoke(customTabsIntent, context, uri);
      return true;
    } catch (NoSuchMethodException e) {
      try {
        if (context instanceof Activity) {
          Method m = ctiCls.getMethod("launchUrl", Activity.class, Uri.class);
          m.invoke(customTabsIntent, context, uri);
          return true;
        }
      } catch (Throwable t) {
        Log.w(TAG, "launchUrl(Activity) failed: " + t.getMessage());
      }
      return false;
    } catch (Throwable t) {
      Log.w(TAG, "launchUrl(Context) failed: " + t.getMessage());
      return false;
    }
  }

  private static boolean launchCustomTabsIntentForResult(
      Class<?> ctiCls,
      Object customTabsIntent,
      Activity activity,
      Uri uri,
      int requestCode) {
    try {
      Field intentField = ctiCls.getField("intent");
      Object intentObj = intentField.get(customTabsIntent);
      if (!(intentObj instanceof Intent)) {
        return false;
      }
      Intent intent = new Intent((Intent) intentObj);
      intent.setData(uri);
      activity.startActivityForResult(intent, requestCode);
      return true;
    } catch (Throwable t) {
      Log.w(TAG, "Custom Tabs startActivityForResult failed: " + t.getMessage());
      return false;
    }
  }

  private static boolean launchViaIntentFieldStartActivity(
      Class<?> ctiCls, Object customTabsIntent, Context context, Uri uri) {
    try {
      Field intentField = ctiCls.getField("intent");
      Object intentObj = intentField.get(customTabsIntent);
      if (!(intentObj instanceof Intent)) {
        return false;
      }
      Intent intent = new Intent((Intent) intentObj);
      intent.setData(uri);
      if (!(context instanceof Activity)) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
      }
      context.startActivity(intent);
      return true;
    } catch (Throwable t) {
      Log.w(TAG, "Custom Tabs intent field launch failed: " + t.getMessage());
      return false;
    }
  }
}
