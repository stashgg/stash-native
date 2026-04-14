# Consumer ProGuard rules for StashNative
# Applied automatically when host apps enable R8/ProGuard.

# Public API facade and all inner classes (config, listener, adapter)
-keep public class com.stash.stashnative.StashNativeCard { public *; protected *; }
-keep public class com.stash.stashnative.StashNativeCard$* { public *; protected *; }

# JS bridge methods invoked by name from JavaScript
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Manifest-declared components
-keep public class com.stash.stashnative.StashNativeCardPortraitActivity
-keep public class com.stash.stashnative.StashKeepAliveService
