# Compatibility & platform notes

Requirements, OS coverage, vendor notes, edge cases, and a summary of SDK techniques relevant to **platform APIs** and **app store review**. For integration and usage, see the [main README](README.md).

## Compatibility

Requirements, OS coverage, vendor notes, and edge cases for each platform are below.

### Android


| Attribute    | Requirement                              |
| ------------ | ---------------------------------------- |
| Minimum SDK  | API 21 (Android 5.0 Lollipop)            |
| Target SDK   | API 34 (Android 14)                      |
| Compile SDK  | 34                                       |
| Java Version | Java 8 (source/target), JDK 17 for build |
| Architecture | armeabi-v7a, arm64-v8a, x86, x86_64      |


**Game engines (Unity, Unreal, and similar):** `openCard` and `openModal` present checkout in `StashNativeCardPortraitActivity` in the **same app process** as the host (no `android:process` isolate). That keeps a single OS process so engines such as Unity are not killed when checkout takes the foreground. Use the [Unity / Unreal wrappers](README.md#game-engine-wrappers) for integrated builds.

#### Android version support


| Android Version               | API Level | Status        | Compatibility Notes                                           |
| ----------------------------- | --------- | ------------- | ------------------------------------------------------------- |
| Android 14 (Upside Down Cake) | 34        | Full          | Target SDK                                                    |
| Android 13 (Tiramisu)         | 33        | Full          |                                                               |
| Android 12/12L                | 31-32     | Full          |                                                               |
| Android 11                    | 30        | Full          | Enhanced window insets (For phones with notch/camera cut-out) |
| Android 10                    | 29        | Full          | Added automatic dark mode support                             |
| Android 9 (Pie)               | 28        | Full          |                                                               |
| Android 8/8.1 (Oreo)          | 26-27     | Full          |                                                               |
| Android 7/7.1 (Nougat)        | 24-25     | Full          |                                                               |
| Android 6 (Marshmallow)       | 23        | Full          |                                                               |
| Android 5/5.1 (Lollipop)      | 21-22     | Full          | Minimum SDK                                                   |
| Android 4.4 and below         | <=20      | Not Supported |                                                               |


#### Vendor-specific support


| Vendor / Skin                  | Compatibility | WebView Source                      | Notes                                                                                   |
| ------------------------------ | ------------- | ----------------------------------- | --------------------------------------------------------------------------------------- |
| Google Pixel / Stock Android   | Full          | Google WebView (Play Store updates) | Reference implementation                                                                |
| Samsung (One UI / TouchWiz)    | Full          | Samsung Internet / Chrome WebView   | No known issues                                                                         |
| Xiaomi (MIUI)                  | Full          | Chrome WebView                      | Some MIUI versions show "battery optimization" warnings, during browser flows.          |
| OnePlus (OxygenOS)             | Full          | Chrome WebView                      | Stock-like behavior                                                                     |
| Oppo (ColorOS)                 | Full          | Chrome WebView                      |                                                                                         |
| Vivo (Funtouch OS)             | Full          | Chrome WebView                      |                                                                                         |
| Realme (Realme UI)             | Full          | Chrome WebView                      |                                                                                         |
| Huawei (EMUI, pre-2019)        | Full          | Google WebView                      | Huawei devices with Google Mobile Services                                              |
| Huawei (HarmonyOS/EMUI, 2019+) | **Partial**   | Huawei WebView                      | No Google Mobile Services; Chrome Custom Tabs unavailable; in-app WebView works         |
| Honor (post-Huawei)            | Full          | Chrome WebView                      | Devices with GMS                                                                        |
| Nokia (Android One)            | Full          | Google WebView                      | Stock Android, **use keep-alive service** recommended.                                  |
| Motorola                       | Full          | Chrome WebView                      | Near-stock Android                                                                      |
| LG                             | Full          | Chrome WebView                      | Legacy devices supported, **use keep-alive service** recommended.                       |
| Sony Xperia                    | Full          | Chrome WebView                      |                                                                                         |
| ASUS (ZenUI)                   | Full          | Chrome WebView                      |                                                                                         |
| Android Go Edition             | Supported     | Chrome WebView                      | Limited memory; may experience slower load times, **use keep-alive service**.           |
| Amazon Fire OS                 | **Partial**   | Amazon WebView                      | Non-standard WebView; openCard/openModal work; openBrowser falls back to system browser |


#### Dependencies


| Dependency                   | Version | Required | Purpose                                                                   |
| ---------------------------- | ------- | -------- | ------------------------------------------------------------------------- |
| androidx.appcompat:appcompat | 1.6.1+  | Yes      | Activity/Fragment support                                                 |
| androidx.browser:browser     | 1.7.0+  | No       | Chrome Custom Tabs when present; otherwise system browser (`ACTION_VIEW`) |


#### Feature restrictions by API level

Core functionality (slide-up card, modal, WebView, animations, payment callbacks) works identically across all supported Android versions (API 21+). The following features have graceful fallbacks on older Android versions:

**API 21-28 (Android 5.0-9.0)**

- Dark mode: Not automatically detected. Light mode used as fallback.
- Window insets: Uses legacy status bar handling, there might be slight overlaps with menu/status bar on some devices or
visual artefacts.

### iOS


| Attribute     | Requirement                                 |
| ------------- | ------------------------------------------- |
| Minimum iOS   | iOS 13.0                                    |
| Swift Version | 5.5+                                        |
| Xcode         | 13.0+                                       |
| Architecture  | arm64, arm64e (devices), x86_64 (simulator) |


#### iOS version support


| iOS Version      | Status        | Notes           |
| ---------------- | ------------- | --------------- |
| iOS 18.x         | Full          | Latest          |
| iOS 17.x         | Full          |                 |
| iOS 16.x         | Full          |                 |
| iOS 15.x         | Full          |                 |
| iOS 14.x         | Full          |                 |
| iOS 13.x         | Full          | Minimum version |
| iOS 12 and below | Not Supported |                 |


#### Device support


| Device Type                    | Status   | Notes                                       |
| ------------------------------ | -------- | ------------------------------------------- |
| iPhone (all models iOS 13+)    | Full     | Portrait/landscape, card slides from bottom |
| iPad                           | Full     | Centered presentation, all orientations     |
| iPad (Split View / Slide Over) | Full     | Responsive layout                           |
| Mac (Catalyst)                 | Untested | Should work; not officially tested yet      |


### Testing

We test this library using BrowserStack App Automate devices. Supported environments are listed in the [App Automate list of browsers and platforms](https://www.browserstack.com/list-of-browsers-and-platforms/app_automate).

### Known limitations

**Android**

- Huawei (2019+ without GMS): openBrowser uses system browser instead of Chrome Custom Tabs; other features work normally.
- Android Go: Performance may vary on low-memory devices (<1GB RAM), please use the [keep-alive service](README.md#openbrowser) (see **Optional: Keep-alive service** under openBrowser).
- WebView updates: Devices without Play Store may have outdated WebView.
- Android emulator (arm64-v8a, Apple Silicon): see [Sample apps](README.md#sample-apps) (GPU / `swangle` note)

**iOS**

- iOS 13: Automatic theme detection not available on iOS 13.0-13.3. Fixed in iOS 13.4
- **Landscape-locked games (Unity, Unreal):** `forcePortrait` works automatically — the SDK hooks `application:supportedInterfaceOrientationsForWindow:` to unlock portrait for its windows without affecting the rest of the app. The one exception is an explicit `UISceneSupportedInterfaceOrientations` key set to landscape-only in the scene configuration in `Info.plist` — see [Forcing Portrait Orientation](README.md#forcing-portrait-orientation) for details and sizing guidance.


## Platform API & Store Compliance Notes

The SDK uses only public, documented APIs on both platforms. Below is a summary of techniques that are worth noting for store review awareness.

### iOS

| Technique | Purpose |
|-----------|---------|
| AppDelegate swizzle (`application:supportedInterfaceOrientationsForWindow:`) | Allows portrait window in landscape-locked games |
| `UIDevice` KVC (`setValue:forKey:@"orientation"`) | Forces orientation on older iOS |
| Remove WKWebView keyboard toolbar | Prevents orientation issues in game engines |
| Deprecated API usage | Backwards compatibility |

### Android

| Technique | Purpose |
|-----------|---------|
| `@JavascriptInterface` bridge | Native↔WebView communication |
| Reflection on AndroidX classes | Ensures compatibility with older libraries |
| Third-party cookies | Needed for payments and SSO |
| Short foreground service | Keeps app alive for payment in browser |
