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
-keep class com.stash.stashnative.StashCustomTabsEngagement { *; }
