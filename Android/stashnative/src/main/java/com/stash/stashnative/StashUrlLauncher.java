package com.stash.stashnative;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.util.Log;
import androidx.annotation.Nullable;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

/**
 * Opens http(s) URLs in Chrome Custom Tabs when {@code androidx.browser} is on the classpath and
 * reflection succeeds; otherwise falls back to {@link Intent#ACTION_VIEW}. No compile-time
 * references to {@code androidx.browser.*} so hosts (Unity, minimal Gradle) are not forced to add
 * that dependency.
 */
public final class StashUrlLauncher {

  private static final String TAG = "StashUrlLauncher";

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
   * Tries Custom Tabs via reflection, then {@link Intent#ACTION_VIEW}. Safe when {@code
   * androidx.browser} is absent.
   */
  public static void openExternalUrl(@Nullable Context context, @Nullable String url) {
    if (context == null || url == null) {
      return;
    }
    String trimmed = url.trim();
    if (trimmed.isEmpty()) {
      return;
    }
    Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (Exception e) {
      Log.w(TAG, "Invalid URL: " + e.getMessage());
      return;
    }
    String scheme = uri.getScheme();
    if (scheme == null) {
      return;
    }
    String sch = scheme.toLowerCase();
    if (!"http".equals(sch) && !"https".equals(sch)) {
      return;
    }
    if (uri.getHost() == null || uri.getHost().isEmpty()) {
      return;
    }

    if (tryLaunchCustomTabsReflect(context, uri)) {
      return;
    }
    try {
      startActionView(context, uri);
    } catch (ActivityNotFoundException e) {
      Log.w(TAG, "No application can open URL: " + trimmed);
    }
  }

  private static void startActionView(Context context, Uri uri) {
    Intent intent = new Intent(Intent.ACTION_VIEW, uri);
    if (!(context instanceof Activity)) {
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    }
    context.startActivity(intent);
  }

  /**
   * @return true if launch was attempted via Custom Tabs (caller assumes success; failures inside
   *     reflection return false).
   */
  private static boolean tryLaunchCustomTabsReflect(Context context, Uri uri) {
    try {
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

      Object customTabsIntent = builderCls.getMethod("build").invoke(builder);
      Class<?> ctiCls = Class.forName(CLASS_CUSTOM_TABS_INTENT);

      if (invokeLaunchUrl(ctiCls, customTabsIntent, context, uri)) {
        return true;
      }
      return launchViaIntentField(ctiCls, customTabsIntent, context, uri);
    } catch (ClassNotFoundException e) {
      return false;
    } catch (Throwable t) {
      Log.w(TAG, "Custom Tabs reflection failed: " + t.getMessage());
      return false;
    }
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

  private static boolean launchViaIntentField(
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
