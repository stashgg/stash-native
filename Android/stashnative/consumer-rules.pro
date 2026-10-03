# Consumer ProGuard rules for StashNative
# Applied automatically when host apps enable R8/ProGuard.

# Public API facade and all inner classes (config, listener, adapter)
-keep public class com.stash.stashnative.StashNativeCard { public *; protected *; }
-keep public class com.stash.stashnative.StashNativeCard$* { public *; protected *; }

# JS bridge methods invoked by name from JavaScript
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Engagement + Custom Tabs bind helper (loaded via reflection from StashUrlLauncher)
-keep class com.stash.stashnative.StashCustomTabsEngagement {
    public static boolean tryLaunchForResult(android.app.Activity, android.net.Uri, int, com.stash.stashnative.StashUrlLauncher$LaunchModeCallback, java.lang.Runnable);
    public static void unbindIfBound(android.content.Context);
}
