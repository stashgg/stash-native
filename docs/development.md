---
title: Development
nav_order: 8
description: Repository layout, local builds and tests, CI workflows, releases, manual test surfaces, and this documentation site.
---

# Development

This page is for engineers working on the SDK itself.

## Repository layout

| Path | Contents |
|---|---|
| `iOS/StashNative` | iOS library: `Sources`, `Tests/StashNativeTests`, `Tests/RegressionSupport`, `Tests/TestHost` (UIKit app host for XCTest), nested `Package.swift`, `StashNative.xcodeproj` with the `StashNative` and `StashNativeTests` schemes |
| `iOS/Sample` | iOS sample app and the sample regression runner (`Tests/run_regressions.py`) |
| `Package.swift` | Root Swift package for installation from the repository URL |
| `Android/stashnative` | Android library module, consumer R8 rules, unit tests |
| `Android/sample` | Android sample app |
| `Android/consumer` | Minimal AAR consumers built with R8 in four dependency variants |
| `Android/modern-host` | Separate build of the sample against the release AAR with target SDK 36 and 37 |
| `.github/workflows` | CI and release workflows |
| `.github/test` | Manual test pages |
| `docs` | This documentation site |

Samples are integration references. Their request signing is demonstration code; production checkout links must be created by a backend that holds the secrets.

## Prerequisites

| Tool | Version |
|---|---|
| JDK | 17. Set `JAVA_HOME`. |
| Android SDK | Platform 34 and matching build tools. Set `ANDROID_HOME`. Platform 37 and Build Tools 36 for `Android/modern-host`. |
| Xcode | 27.1 for release validation. Select it per command with `DEVELOPER_DIR` instead of changing the machine default. |
| iOS Simulator | Any installed runtime. Find IDs with `xcrun simctl list devices available`. |
| SwiftLint | Uses the repository's `.swiftlint.yml` |
| Python 3 | Sample regression runner |

Build in a temporary copy so generated output never lands in the repository:

```sh
WORK=$(mktemp -d "${HS_TEMP:-$HOME/Temp}/stash-build.XXXXXX")
rsync -a --exclude='.git' --exclude='.build' --exclude='build' ./ "$WORK/source/"
cd "$WORK/source"
```

## Android

```sh
export GRADLE_USER_HOME="$WORK/gradle-home"
cd Android
./gradlew :stashnative:assembleRelease :stashnative:testDebugUnitTest \
  :sample:testDebugUnitTest :sample:assembleDebug :sample:assembleRelease \
  :stashnative:lintRelease :sample:lintDebug
./gradlew :consumer:assembleCurrentRelease :consumer:assembleLegacyRelease \
  :consumer:assembleAbsentRelease :consumer:assembleCameraOnlyRelease
```

Checkstyle uses [`Android/checkstyle.xml`](https://github.com/stashgg/stash-native/blob/main/Android/checkstyle.xml) with Checkstyle 10.12.7:

```sh
java -jar checkstyle.jar -c Android/checkstyle.xml -f plain Android/stashnative/src/main/java/
```

| Consumer variant | Optional libraries present | Verifies |
|---|---|---|
| `current` | Browser 1.7.0, CameraX, ZXing | Full feature set under R8 |
| `legacy` | Browser 1.3.0 | Old Browser library, no scanner |
| `absent` | None | System browser fallback, CodeLink failure path |
| `cameraOnly` | CameraX without ZXing | Partial scanner installation |

Unit tests use JUnit and Robolectric. The library sets `unitTests.returnDefaultValues = true`, so plain JUnit tests get default-returning Android stubs; tests that depend on real URI parsing or lifecycle behavior must run under Robolectric. WebView behavior, browser return, activity recreation, and a differently signed sender APK need device checks.

`Android/modern-host` builds the sample with AGP 9.1.1, Gradle 9.3.1, and compile SDK 37 against a release AAR. See its [README](https://github.com/stashgg/stash-native/blob/main/Android/modern-host/README.md).

## iOS

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer   # Xcode 27.1
xcodebuild build -project iOS/StashNative/StashNative.xcodeproj -scheme StashNative \
  -sdk iphoneos -derivedDataPath "$WORK/ios-build" CODE_SIGNING_ALLOWED=NO
xcodebuild analyze -project iOS/StashNative/StashNative.xcodeproj -scheme StashNative \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$WORK/ios-analysis"
xcodebuild build -project iOS/StashNative/StashNative.xcodeproj -scheme StashNative \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$WORK/ios-non-arc" CLANG_ENABLE_OBJC_ARC=NO CODE_SIGNING_ALLOWED=NO
swiftlint lint iOS/Sample/StashNativeSample --strict --no-cache --config .swiftlint.yml
python3 iOS/Sample/Tests/run_regressions.py --output "$WORK/sample-regressions"
xcodebuild build -project iOS/Sample/StashNativeSample/StashNativeSample.xcodeproj \
  -scheme StashNativeSample -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath "$WORK/ios-sample" CODE_SIGNING_ALLOWED=NO
```

XCTest runs through the `StashNativeTests` scheme, which hosts the tests in a UIKit app so WebKit has an active application and window scene:

```sh
mkdir "$WORK/ios-tests"
cp -R iOS/StashNative/Sources iOS/StashNative/Tests \
  iOS/StashNative/StashNative.xcodeproj iOS/StashNative/Info.plist "$WORK/ios-tests/"
xcrun simctl bootstatus "$SIM_ID" -b
xcodebuild test -project "$WORK/ios-tests/StashNative.xcodeproj" \
  -scheme StashNativeTests -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath "$WORK/ios-tests-derived" \
  -resultBundlePath "$WORK/ios-tests.xcresult"
```

Do not use macOS `swift test` for the iOS package.

The sample regression runner exercises request ordering and credential persistence with synthetic network and Keychain boundaries. It never reads saved credentials.

When adding an implementation file, add it to `StashNative.xcodeproj` as well. Swift Package Manager finds it automatically; the Xcode project does not. Compile public-header consumers in both ARC and non-ARC modes when changing headers or lifecycle code.

## CI

| Workflow | Trigger | Does |
|---|---|---|
| `lint.yml` | Push and pull request to `main`, manual, called by `release.yml` | Checkstyle for library and sample; Android unit tests, sample builds, Android Lint, R8 consumers; iOS sample regressions and XCTest in the UIKit test host; Clang analyzer and a non-ARC build; SwiftLint |
| `main.yml` | Push and pull request to `main`, manual | Builds the AAR, sample APKs, iOS library, IPA, and simulator app; uploads artifacts and sample builds to BrowserStack and Appetize |
| `release.yml` | Push to `main` that changes `CHANGELOG.md`, manual | Parses the changelog, checks versions, runs `lint.yml`, builds and publishes the AAR and XCFramework |
| `ios-beta.yml` | Manual, with a runner label | Builds and tests on a runner with Xcode 27.1 |
| `ripley.yml`, `ripley-auto.yml` | Pull request events and comments | Automated review against [`RIPLEY.md`](https://github.com/stashgg/stash-native/blob/main/RIPLEY.md) |

Hosted macOS runners use Xcode 26.6, which exercises the compile guards. Release packaging requires Xcode 27.1 and SDK 27.1 on the runner named by the `STASH_IOS_RELEASE_RUNNER` repository variable. The setup action selects an installed Xcode; it does not download one.

## Releases

1. Align the version everywhere:

   | Location | Field |
   |---|---|
   | `iOS/StashNative/Sources/StashNative/StashNativeCard.m` | `+sdkVersion` |
   | `iOS/StashNative/StashNative.xcodeproj` | `MARKETING_VERSION` |
   | `Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCard.java` | `SDK_VERSION` |
   | `CHANGELOG.md` | Top `## [x.y.z] - YYYY-MM-DD` entry |

2. Date the changelog entry only when that exact revision has passed validation. An `Unreleased` entry disables packaging and publishing.
3. `release.yml` verifies that the iOS and Android versions match the changelog, that the tag does not exist, and that the framework plists carry the version. It publishes `StashNative-<version>.aar` and `StashNative-<version>.xcframework.zip` under a tag named after the version.

## Manual test surfaces

| Surface | Use |
|---|---|
| [`.github/test/index.html`](https://github.com/stashgg/stash-native/blob/main/.github/test/index.html) | Calls every `stash_sdk` method and shows callback results |
| [`.github/test/responsive.html`](https://github.com/stashgg/stash-native/blob/main/.github/test/responsive.html) | Short and long content, explicit and observed heights, input focus, expand and collapse, processing locks |
| [`.github/test/mockup.html`](https://github.com/stashgg/stash-native/blob/main/.github/test/mockup.html) | Static checkout mockup |
| [test.stashpreview.com](https://test.stashpreview.com/) | Hosted callback test page |
| `iOS/Sample`, `Android/sample` | Card, browser, CodeLink, test link generation |

The iOS sample's debug build accepts `-stash-url <url> -stash-mode card|browser` launch arguments; Android debug builds of `modern-host` accept `--es stash-url <url>`. To serve `.github/test` locally, run an HTTP server on the host. The iOS Simulator reaches it at `127.0.0.1`; the Android Emulator at `10.0.2.2`, or through `adb reverse`. Only the samples enable local cleartext exceptions. Keep test credentials and generated checkout URLs out of source and logs.

## Device checks

Automated tests cover geometry, config normalization, URL handling, and lifecycle seams. These need real WebViews:

- Short and long content, explicit and observed heights, invalid and stale hints.
- Keyboard entry from resting and expanded states; rotation and continuous resizing with a focused field.
- Fold, unfold, tabletop posture, split-screen divider changes, and desktop windows on Android; closed and open iPhone Duo.
- Drags in both directions at both stops, rapid reversals, two-finger touches, nested scrollers, and long documents. Record card and WebView bounds during the gesture, not only final positions.
- Processing locks against every dismissal path; external browser return; `autoClose` on and off.
- Light and dark appearance with existing checkout storage, Reduce Motion, Reduce Transparency, and slow responses. Dismiss during loading and during the reveal.
- First cold navigation and rounded corners on the oldest supported WebView provider.
- VoiceOver and TalkBack labels, escape, and adjustable actions.

Throughout, the page-load count, typed input, scroll position, and callback order must not change. A successful install or a boot screenshot is not a runtime pass.

## Documentation site

The site is built from `docs/` by GitHub Pages with Jekyll and the [Just the Docs](https://just-the-docs.com/) theme (`remote_theme`, pinned in `docs/_config.yml`). Mermaid diagrams render client-side from the version set under `mermaid:` in the same file.

Publishing: **Settings > Pages > Build and deployment > Deploy from a branch**, branch `main`, folder `/docs`.

Local preview needs Ruby and Bundler. The `github-pages` gem does not install on Ruby 4, so pin the same Jekyll and plugin versions that GitHub Pages uses:

```sh
mkdir -p "$WORK/docs-site" && cd "$WORK/docs-site"
cat > Gemfile <<'EOF'
source "https://rubygems.org"
gem "jekyll", "3.10.0"
gem "liquid", "4.0.4"
gem "kramdown", "2.4.0"
gem "kramdown-parser-gfm", "1.1.0"
gem "rouge", "3.30.0"
gem "rake"
gem "webrick"
gem "csv"
gem "base64"
gem "bigdecimal"
gem "logger"
gem "ostruct"
gem "faraday-retry"
group :jekyll_plugins do
  gem "jekyll-remote-theme", "0.4.3"
  gem "jekyll-include-cache", "0.2.1"
  gem "jekyll-seo-tag", "2.8.0"
  gem "jekyll-relative-links", "0.6.1"
  gem "jekyll-github-metadata", "2.16.1"
end
EOF
bundle config set --local path vendor/bundle
bundle install
bundle exec jekyll serve --source /path/to/stash-native/docs \
  --destination "$WORK/docs-site/_site" --baseurl ""
```

The site is then at `http://127.0.0.1:4000/`. Diagrams load Mermaid from jsDelivr, so the preview needs network access.

Conventions:

- Every page has front matter with `title`, `nav_order`, and `parent` for child pages.
- Link other pages with relative `.md` paths. Link source files with absolute `https://github.com/stashgg/stash-native/blob/main/...` URLs, because files outside `docs/` are not published.
- Jekyll processes Liquid in Markdown. Wrap any literal double curly braces in `raw` tags.
- Update the [bridge reference](stash-sdk-js.md) in the same change as any bridge behavior.
