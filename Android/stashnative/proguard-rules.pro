# StashNative ProGuard Rules

# Keep the public API
-keep class com.stash.stashnative.StashNativeCard { *; }
-keep class com.stash.stashnative.StashNativeCard$* { *; }
-keep interface com.stash.stashnative.StashNativeCard$* { *; }

# Keep internal classes that are accessed via reflection
-keep class com.stash.stashnative.StashNativeCardPlugin { *; }
-keep class com.stash.stashnative.StashNativeCardPortraitActivity { *; }
-keep class com.stash.stashnative.StashWebViewUtils { *; }
-keep class com.stash.stashnative.SpringInterpolator { *; }
