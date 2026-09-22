# Verification

Use commands from the selected source revision and discover installed toolchains before execution. These examples describe future audits and fixes; creating or editing this skill does not itself require running SDK builds or a baseline audit.

## Workspace and evidence

- Resolve the artifact root using [reporting](reporting.md). Use a new run directory for logs, source snapshots, caches, build outputs, screenshots, and probe consumers. Preserve existing logs.
- Set `AUDIT_RUN` to that run directory, `AUDIT_SOURCE` to a complete temporary copy of the current source tree, and `AUDIT_DESKTOP_SOURCE` to the selected desktop snapshot. Preserve relevant uncommitted/untracked source in a working-tree copy; `git archive HEAD` would omit it. An immutable branch snapshot can be extracted from its resolved commit.
- Both source directories must be under the temporary root before running commands that write beside their inputs. Never remove the original `.xcodeproj` to make tests work. Do not print local credentials while copying or inspecting configuration.
- Keep platform SDK installations in place; put new audit-owned output/caches under the run directory. Do not install toolchains, change signing/provisioning, or trigger release/upload workflows as an incidental verification step.
- Record each command, working directory/source label and SHA, tool/OS versions, configuration, exit status, discovered/executed tests, warnings, and log path. Preserve the failing command's exit status through any log pipeline.
- Classify checks as `PASS`, `FAIL`, `BLOCKED`, `NOT-RUN`, or justified `N/A`. An unavailable Windows runner, simulator, GUI session, engine project, or staging input is a blocker for that check, not a product failure or a pass.
- Existing CI results are supplementary evidence only when their exact commit, configuration, test discovery, and outcome are known. Record them as CI evidence rather than local execution. A job definition alone proves no execution.

Run applicable checks once. Repeat after relevant changes or to investigate a failure; do not loop builds without a reason. Use timeouts for UI proof runs, and stop only processes launched by the audit.

## Android

Discover JDK 17, the Android SDK, and the Gradle wrapper from the selected tree. On macOS `/usr/libexec/java_home -V` lists installed JDKs; use `-v 17` to resolve a matching home. Elsewhere inspect the configured toolchain. Set `AUDIT_JDK17` to the discovered path, not a hardcoded Homebrew location.

From `$AUDIT_SOURCE/Android`:

```sh
JAVA_HOME="$AUDIT_JDK17" GRADLE_USER_HOME="$AUDIT_RUN/gradle-home" ./gradlew \
  --project-cache-dir "$AUDIT_RUN/gradle-cache" \
  :stashnative:assembleRelease :stashnative:testDebugUnitTest \
  :sample:assembleDebug :sample:assembleRelease \
  :stashnative:lintRelease :sample:lintDebug
```

Read JUnit XML and lint reports, including warnings and suppressed findings. Confirm the Robolectric tests execute the expected paths and the JVM suite discovers tests. Lint may return zero despite findings because its configuration is non-blocking.

Run Checkstyle against both source roots using the version and configuration in the source snapshot's lint workflow. Put a downloaded JAR under `AUDIT_RUN` and set `AUDIT_CHECKSTYLE_JAR` to it:

```sh
"$AUDIT_JDK17/bin/java" -jar "$AUDIT_CHECKSTYLE_JAR" \
  -c "$AUDIT_SOURCE/Android/checkstyle.xml" -f plain \
  "$AUDIT_SOURCE/Android/stashnative/src/main/java" \
  "$AUDIT_SOURCE/Android/sample/src/main/java"
```

For dependency/shrinking findings, use a temporary consumer to check the actual AAR with minification and the optional browser library present/absent or an older supported dependency. An unminified sample does not cover that contract. Keep such probes targeted and record their dependency versions.

Device/emulator checks cover real WebView/Custom Tabs, IME/insets, back/dismiss, host recreation, browser absence, supported old/new APIs, and representative engine lifecycle. Record available coverage without claiming every vendor/runtime was tested.

## iOS

Discover `xcodebuild -version`, `xcode-select -p`, and available devices with `xcrun simctl list devices available -j`. Choose an available iOS Simulator and record its UDID as `AUDIT_SIMULATOR_ID`; do not hardcode a model name.

Library device build and simulator analysis from the temporary source copy:

```sh
xcodebuild -project "$AUDIT_SOURCE/iOS/StashNative/StashNative.xcodeproj" \
  -scheme StashNative -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$AUDIT_RUN/ios-device" CODE_SIGNING_ALLOWED=NO build

xcodebuild -project "$AUDIT_SOURCE/iOS/StashNative/StashNative.xcodeproj" \
  -scheme StashNative -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$AUDIT_RUN/ios-analyze" \
  CLANG_ANALYZER_OUTPUT=plist-html \
  CLANG_ANALYZER_OUTPUT_DIR="$AUDIT_RUN/ios-analyzer-results" analyze
```

For XCTest, create a fresh package directory containing only `Package.swift`, `Sources`, and `Tests` copied from `iOS/StashNative`. The adjacent Xcode project otherwise hides the SPM test target:

```sh
mkdir -p "$AUDIT_RUN/ios-test-package"
cp "$AUDIT_SOURCE/iOS/StashNative/Package.swift" "$AUDIT_RUN/ios-test-package/"
cp -R "$AUDIT_SOURCE/iOS/StashNative/Sources" "$AUDIT_RUN/ios-test-package/"
cp -R "$AUDIT_SOURCE/iOS/StashNative/Tests" "$AUDIT_RUN/ios-test-package/"
```

From that new package directory:

```sh
xcodebuild test -scheme StashNative \
  -destination "platform=iOS Simulator,id=$AUDIT_SIMULATOR_ID" \
  -derivedDataPath "$AUDIT_RUN/ios-tests-derived" \
  -resultBundlePath "$AUDIT_RUN/ios-tests.xcresult"
```

Confirm XCTest discovery and results. Do not replace this with `swift test`, which targets macOS for the iOS package.

```sh
xcodebuild -project "$AUDIT_SOURCE/iOS/Sample/StashNativeSample/StashNativeSample.xcodeproj" \
  -scheme StashNativeSample -configuration Debug \
  -destination "platform=iOS Simulator,id=$AUDIT_SIMULATOR_ID" \
  -derivedDataPath "$AUDIT_RUN/ios-sample" CODE_SIGNING_ALLOWED=NO build

swiftlint lint "$AUDIT_SOURCE/iOS/Sample/StashNativeSample" \
  --strict --config "$AUDIT_SOURCE/.swiftlint.yml"
```

Run SwiftLint from the temporary source copy so any local cache stays there; inspect the installed CLI's supported cache options if it writes elsewhere. For ARC/non-ARC or packaging claims, compile a small public-header consumer in the required modes and check relevant implementation compilation paths, module imports, XCFramework slices and source membership. Scope findings to what the probe establishes.

Runtime checks include scene/window selection, repeated presentations, orientation-locked hosts, keyboard/safe areas, Safari return/cancel, processing locks, interrupted dismissal, and accessibility. Real device/game-engine behavior is separate from simulator unit-test success.

## Desktop shared contract: any supported build host

Discover CMake/CTest and a C++17 compiler. With `$AUDIT_DESKTOP_SOURCE` set to the pinned source snapshot:

```sh
cmake -S "$AUDIT_DESKTOP_SOURCE/Desktop/shared" \
  -B "$AUDIT_RUN/desktop-shared" -DCMAKE_BUILD_TYPE=Debug \
  -DSTASH_DESKTOP_SHARED_TESTS=ON
cmake --build "$AUDIT_RUN/desktop-shared" --config Debug
ctest --test-dir "$AUDIT_RUN/desktop-shared" -C Debug -N
ctest --test-dir "$AUDIT_RUN/desktop-shared" -C Debug \
  --output-on-failure --no-tests=error
```

On Windows, use an installed generator explicitly if the default cannot locate the compiler. Require at least one discovered test. If an older CTest lacks `--no-tests=error`, check `ctest -N` first and reject a zero-test run yourself. Review checks under Release/NDEBUG too when assessing release-test validity.

These tests cover session/config/URL/JSON/theme behavior. They do not substitute for native host tests, C ABI loading, or WebKit/WebView2 execution.

## macOS host and sample

Requires macOS, the selected Xcode/Swift toolchain, and a usable GUI session for AppKit/WebKit-dependent cases. The desktop package legitimately uses native `swift test`:

```sh
swift build --package-path "$AUDIT_DESKTOP_SOURCE/Desktop" \
  --scratch-path "$AUDIT_RUN/macos-spm"
swift test --package-path "$AUDIT_DESKTOP_SOURCE/Desktop" \
  --scratch-path "$AUDIT_RUN/macos-spm"
swift build --package-path "$AUDIT_DESKTOP_SOURCE/Desktop" \
  --scratch-path "$AUDIT_RUN/macos-spm" --product StashNativeDesktopSample
swift build --package-path "$AUDIT_DESKTOP_SOURCE/Desktop" \
  --scratch-path "$AUDIT_RUN/macos-spm" --show-bin-path
```

Set `AUDIT_MACOS_BIN` to the reported binary directory. Confirm XCTest discovery and inspect skipped tests; an AppKit test blocked by the GUI environment is not a pass.

```sh
"$AUDIT_MACOS_BIN/StashNativeDesktopSample" -stash-auto local
"$AUDIT_MACOS_BIN/StashNativeDesktopSample" -stash-auto secure
env -u STASH_SIGN_IDENTITY OUT_DIR="$AUDIT_RUN/macos-bundle" \
  bash "$AUDIT_DESKTOP_SOURCE/Desktop/macOS/build_bundle.sh"
swiftlint lint "$AUDIT_DESKTOP_SOURCE/Desktop/macOS/Sample" \
  --strict --config "$AUDIT_DESKTOP_SOURCE/.swiftlint.yml"
```

Capture each proof run separately using the criteria below. Build the audit bundle unsigned unless signing is specifically within the requested verification; inspect exports with `nm` and architecture slices with `lipo`, comparing the complete C ABI header. Follow the target snapshot's `lint-macos` compiler flags for Clang analysis over every host `.mm` and shared `.cpp`, with analyzer outputs under `AUDIT_RUN`.

Check a packaged sample outside the source tree with the shared test pages next to the executable. Document the difference between SPM output, the universal bundle, and shipping signing/notarization requirements; do not modify signing identities or release artifacts during an audit.

## Windows host and sample

Requires a Windows runner with Visual Studio's C++ workload, a compatible CMake generator, and WebView2 runtime for UI proofs. Inspect `cmake --help`, Visual Studio discovery, compiler versions, and runtime availability. Source review and portable C++ tests on macOS do not satisfy these checks.

In PowerShell, set `$auditSource` to the temporary desktop snapshot and `$auditRun` to a new run directory under `$env:HS_TEMP`, or the user's home `Temp` fallback. Set `$auditGenerator` to the exact installed Visual Studio generator; do not let Ninja be chosen implicitly with `-A x64`.

```powershell
cmake -S "$auditSource/Desktop/Windows" -B "$auditRun/windows" `
  -G $auditGenerator -A x64 -DCMAKE_TLS_VERIFY=ON
if ($LASTEXITCODE -ne 0) { throw 'Windows configure failed' }
cmake --build "$auditRun/windows" --config Release
if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
ctest --test-dir "$auditRun/windows" -C Release -N
if ($LASTEXITCODE -ne 0) { throw 'Windows test discovery failed' }
ctest --test-dir "$auditRun/windows" -C Release --output-on-failure --no-tests=error
if ($LASTEXITCODE -ne 0) { throw 'Windows tests failed' }

$auditSample = Join-Path $auditRun 'windows/Sample/Release/StashNativeDesktopSample.exe'
& $auditSample -stash-auto local
if ($LASTEXITCODE -ne 0) { throw 'Windows local proof failed' }
& $auditSample -stash-auto secure
if ($LASTEXITCODE -ne 0) { throw 'Windows secure proof failed' }
```

Also verify both proof success markers. Configure-time WebView2 SDK downloads must retain TLS verification. If a CA bundle is needed, use the installed valid bundle via `-DCMAKE_TLS_CAINFO`; record the SDK version, including a resolved latest version when the project leaves it unpinned. Do not bypass TLS checks to make a build pass.

Inspect DLL exports with `dumpbin /exports` or an equivalent installed tool against the C ABI header, and confirm the native facade/import library builds. Check runtime/DLL dependencies and packaged sample assets from outside the source tree. Missing-runtime behavior, window input/z-order/fullscreen, and engine reload need real Windows observations.

## Proof-run acceptance and manual matrix

For each desktop `local` and `secure` invocation require exit zero, the matching `STASH-PROOF <mode>: RESULT: PASS` marker, no FAIL marker, and completion within a bounded timeout. The current runner uses a 25-second timeout; a 45-second outer timeout catches a hung process. Preserve full redacted output and inspect the event/state assertions in the runner at that revision. Finding the word PASS or merely launching the executable is insufficient.

Keep separate rows for portable tests, native host tests, actual webview proof runs, packaged sample runs, and engine/payment scenarios. Review both proof runners for premature completion or assertions that ignore later events.

Use the target revision's desktop validation matrix for Unity/Unreal, reload/shutdown, attached versus standalone windows, exclusive fullscreen where relevant, staging wallet/redirect/3DS flows, and protected-game integration. Keep documented blocked cases open until they can be exercised. Use remote proof/payment inputs only within the user's requested environment; do not generate real purchases to complete an audit. Never post results to issues or messaging tools unless separately instructed.
