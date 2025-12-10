# StashPay ProGuard Rules

# Keep the public API
-keep class com.stash.popup.StashPayCard { *; }
-keep class com.stash.popup.StashPayCard$* { *; }
-keep interface com.stash.popup.StashPayCard$* { *; }

# Keep internal classes that are accessed via reflection
-keep class com.stash.popup.StashPayCardPlugin { *; }
-keep class com.stash.popup.StashPayCardPortraitActivity { *; }
-keep class com.stash.popup.StashWebViewUtils { *; }
-keep class com.stash.popup.SpringInterpolator { *; }
