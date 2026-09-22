# Stash Native SDK project rules

Stash Native hosts checkout web content in native card, modal, and browser presentations. Native apps and Unity/Unreal wrappers consume it. These rules apply to every agent working in this repository.

## Temporary files

Put temporary scripts, screenshots, logs, build outputs, source snapshots, and audit reports in `$HS_TEMP`. If it is unset, use `~/Temp` and create it if needed. On Windows, use the same environment variable or the current user's home `Temp` directory. Only requested project deliverables belong in the repository.

## Architecture

- iOS: Objective-C `StashNativeCard` singleton with focused Configs, Geometry, Theme, ViewUtils, Internal, ViewControllers, and WebViewDelegates units. Shared state is defined in `StashNativeCard.m` and declared in `StashNativeCardPrivate.h`. Distribution uses SPM and an XCFramework.
- Android: Java `StashNativeCard` facade, internal `StashNativeCardPlugin`, and portrait checkout activity. Package-private `Stash*Support` and sizing helpers contain extracted logic; mutable state stays with its activity/plugin owner. Distribution uses an AAR.
- Desktop, when present: `Desktop/shared` contains the C++17 session, configuration, URL, theme, JSON, and JS bridge contract. The macOS host uses Objective-C++/AppKit/WKWebView with a Swift sample; Windows uses C++/Win32/WebView2 with a C++ sample. Both export `Desktop/include/StashNativeDesktop.h` through a bundle or DLL.
- Desktop development currently lives on `desktop/*` branches, with the combined implementation on `desktop/integration`. Discover the actual files and resolve refs before treating desktop as absent or using a branch's documentation.
- `window.stash_sdk` is the shared page contract; `docs/stash-sdk-js.md` describes it. Read documentation from the same revision as the implementation being examined.

## Compatibility requirements

- Preserve existing public APIs, observable callback behavior, and Unity, Unreal 4, and Unreal 5 integration.
- Preserve iOS ARC and non-ARC compatibility, including the delegate property's `__has_feature(objc_arc)` guard. An ARC build alone does not verify non-ARC consumers.
- Android checkout runs in the host app process. Do not introduce an `android:process` isolate.
- Preserve existing JS handler spellings, including `stashNativement*`; they are compatibility names.
- Desktop C exports, calling conventions, UTF-8 strings, callback payloads, and ownership rules are wrapper contracts. Preserve both native facades and the C ABI.
- No emojis in code, comments, or documentation. Keep comments terse, direct, and useful.

## Code patterns

### Bridge and callbacks

Mirror changes to common bridge behavior in every implementation present in the target release, and update the bridge specification and test page. Injection sources are `StashWebViewUtils.JS_SDK_SCRIPT` on Android, `stashSDKScript` in iOS `StashNativeCard.m`, and `Desktop/shared/StashSdkScript.h` for both desktop hosts.

Desktop callback ordering, once-guards, processing locks, navigation decisions, and dismissal semantics belong in the shared `Session`. Hosts own platform plumbing. Preserve documented differences: macOS marshals operations to the main queue; Windows operations use the host window's message-loop thread, with explicitly documented atomic queries treated separately. Desktop browser handoff does not promise a browser-closed callback.

### Sizing and presentation

- Mobile card and modal ratios clamp to `[0.1, 1.0]`, including non-finite inputs. iOS applies runtime normalization; constructor defaults alone are not validation.
- Popup multipliers legitimately exceed `1.0`. Validate positive, finite values using popup-specific fallbacks instead of the card/modal clamp.
- Respect iOS safe areas through the view helpers and Android system insets through `StashWindowCompat` and its fallback chain.
- Desktop accepts mobile configuration fields for wrapper compatibility, but uses its own surface sizing policy. Do not impose mobile ratio-driven layout, portrait behavior, or popup APIs on desktop.
- Android card resize currently uses per-frame layout updates. The previous audit guidance records this as an accepted cost after an unsuccessful pin-and-clip approach. Preserve that context; new regressions still need evidence and measurement.

### Android integration

- Keep sample UI and test dependencies out of the SDK runtime graph. Check source/resource usage and resolved transitive dependencies before adding libraries or version-alignment platforms; retain only what the SDK's supported behavior needs.
- Runtime reflection around optional/older dependencies must catch `Throwable` and degrade gracefully. Missing optional libraries must not crash the SDK. Follow `StashWindowCompat` and `StashUrlLauncher`; test reflection used to inspect internals is a different context.
- Keep consumer shrinking rules narrow and sufficient for the public API and reflection/bridge contracts. Do not add blanket keep rules or assume internal classes are already obfuscated in an unminified AAR.
- The portrait activity communicates with the plugin through package-local broadcasts in the same process, with a non-exported receiver on API 33+ and a host-specific signature permission on API 21–32.
- `StashNativeBrowserProxyActivity` consumes Custom Tabs results internally. Hosts do not forward `onActivityResult`; `StashCustomTabsEngagement` supplies the browser-close fallback.

### iOS state and file membership

Define shared mutable state and cross-file constants in `StashNativeCard.m` and declare them in `StashNativeCardPrivate.h`, alongside the internal interfaces. Other implementation files import that header. Keep single-file constants `static`. Do not duplicate definitions or move ownership without accounting for the existing coupling.

Add new iOS implementation files to `StashNative.xcodeproj` as well as the source tree. SPM discovers files automatically; the Xcode project does not.

## Builds and tests

Discover installed toolchains and simulator IDs. Use temporary source copies or redirect every generated output under the temporary root. The [audit verification reference](.agents/skills/stash-native-audit/references/verification.md) gives commands and required execution contexts.

| Target | Validation |
|---|---|
| Android SDK and sample | JDK 17; Gradle `:stashnative:assembleRelease`, `:stashnative:testDebugUnitTest`, `:sample:assembleDebug`, `:sample:assembleRelease`; Android Lint and repository Checkstyle configuration. |
| iOS SDK | `xcodebuild` build/analyze; XCTest on an available iOS Simulator. Copy the SPM package without its `.xcodeproj` before testing so the package test target is selected. Do not use macOS `swift test` for the iOS package. |
| iOS sample | Simulator build and SwiftLint using `.swiftlint.yml`; device testing for platform behavior. |
| Desktop shared contract | CMake/CTest against `Desktop/shared`, independently of either UI host. |
| macOS SDK and sample | `swift build`/`swift test` from `Desktop`, bundle export/architecture checks, SwiftLint, Clang analysis, and sample `-stash-auto local`/`secure` proof runs. |
| Windows SDK and sample | Windows, Visual Studio C++ workload, an explicit installed CMake generator, x64 build, CTest, DLL export checks, and WebView2 sample proof runs. |

Android tests use JUnit and Robolectric. `returnDefaultValues = true` also exists: determine which tests use real logic, shadows, or default-returning Android stubs. WebView-dependent behavior needs integration/runtime checks, but pure logic and lifecycle seams can still have useful automated tests.

Desktop shared tests can run without Windows. They do not establish that the Windows DLL, Win32 UI, or WebView2 works. Record unavailable host/device checks as unverified. Inspect CI results for the exact revision before treating them as evidence.

## Versions and samples

When releasing, keep version declarations and artifacts aligned within that release:

- iOS `+sdkVersion` in `StashNativeCard.m` and relevant bundle metadata.
- Android `SDK_VERSION` in `StashNativeCard.java`.
- Desktop `STASH_NATIVE_DESKTOP_VERSION` in `Desktop/include/StashNativeDesktopVersion.h`, when present.
- Changelog and release-workflow version gates.

Different development branches may intentionally carry different release versions; a mixed-revision audit must say so.

Samples under `Android/sample`, `iOS/Sample`, `Desktop/macOS/Sample`, and `Desktop/Windows/Sample` are integration references. Keep credential handling, lifecycle use, callback examples, and setup instructions clear. Sample-side request signing is demonstration behavior; production ingress secrets belong on a backend.

## Audit skill

For a full SDK/sample audit, quality assessment, or remediation of audit findings, load [stash-native-audit](.agents/skills/stash-native-audit/SKILL.md). It covers iOS, Android, macOS, Windows, their samples, and the shared desktop contract.

- Codex/Agent Skills: `$stash-native-audit` with optional `audit`, `status`, or `fix` instructions.
- Claude: `/stash-native-audit` with the same modes.
- Other agents: read the linked `SKILL.md` and follow the requested mode directly.

The default is a report. Fixing, committing, and publishing are separate actions governed by the user's request. Ordinary edits do not require a full audit.
