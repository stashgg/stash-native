# Modern Android host verification

This independent build runs the shared sample against the release AAR with Android 16 and 17 target behavior enabled. It uses AGP 9.1.1, Gradle 9.3.1, JDK 17, compile SDK 37, and minimum SDK 21. The SDK's own build remains independent.

Install Android platform 37.0 and Build Tools 36.0.0, then build the SDK AAR using the repository's usual verification process. Set `ANDROID_HOME` to the SDK directory and `JAVA_HOME` to JDK 17.

```sh
./gradlew -PstashAar=/absolute/path/to/stashnative-release.aar \
    assembleApi36Debug assembleApi37Debug assembleApi36Release assembleApi37Release
```

The wrapper puts caches, temporary files, the debug signing key, and build outputs below `$HS_TEMP/stash-modern-host`, or `~/Temp/stash-modern-host` when `HS_TEMP` is unset. APKs are under `build/outputs/apk`. Release variants enable shrinking and use a debug key so they can be installed for verification. Do not distribute them.

The app IDs end in `.modern.api36` and `.modern.api37`. Run target 36 on Android 16 and 17, and target 37 on Android 17. Check phone, foldable, split-screen, tablet, and desktop-window layouts, including resizing while the keyboard or a payment page is open. Verify that checkout state survives, content remains reachable, and dismissal still obeys processing state.

Debug variants accept the sample's launch extras and local HTTP test pages:

```sh
adb shell am force-stop com.stash.stashnative.sample.modern.api37
adb shell am start -f 0x10008000 \
    -n com.stash.stashnative.sample.modern.api37/com.stash.stashnative.sample.MainActivity \
    --es stash-url 'https://example.com/test-checkout'
```

Release variants ignore the launch extra and do not enable cleartext traffic.

On the tested Apple Silicon host, Android Emulator 37.1.11 ran API 36 with `-gpu host -feature -Vulkan`. API 37 checkout WebGL content crashed that GPU backend; `-gpu swiftshader_indirect -feature -Vulkan` rendered it successfully. This is an emulator configuration workaround, not an SDK runtime setting.

Both variants reuse `../sample/src/main`. Update this build's explicitly declared dependencies when the SDK or sample dependencies change: a file-based AAR does not include Maven dependency metadata. Validate the existing standalone consumer separately to cover older host toolchains and optional browser dependencies.
