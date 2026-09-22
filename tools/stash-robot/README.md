# Stash Robot

Local, visual testing for the Stash Native Android and iOS sample apps. A browser window shows simulator screenshots, a persistent Codex conversation, manual device controls, and checkout WebView diagnostics.

## Start

From the stash-native checkout:

```sh
node tools/stash-robot/scripts/install-skill.mjs
node tools/stash-robot/scripts/launch.mjs start --daemon --repo "$PWD"
```

Invoke the installed `stash-robot` skill through the Codex skill picker or `$stash-robot`. It launches the same maintained entrypoint. Select Android or iOS in the browser; the harness checks prerequisites, creates or reuses its dedicated device, builds the local sample, and starts automation.

The launcher finds a compatible installed Node runtime and runs `npm ci` when its lockfile changes. It checks the current Node, PATH, and installed nvm runtimes. It does not download native SDKs or system images.

To supply an initial scenario:

```sh
node tools/stash-robot/scripts/launch.mjs start --daemon --repo "$PWD" \
  --scenario 'Open the test card, inspect the input, and temporarily outline it in magenta.'
```

Use `--model MODEL` and `--effort EFFORT` for an explicit worker override. Otherwise it uses Codex configuration. `--no-open` leaves browser opening to the caller; omitting `--daemon` runs the server in the foreground.

Launching again reconnects to the existing session and forwards a supplied scenario. Before platform selection, the scenario waits for startup; during a running agent turn, it steers that turn. Model overrides take effect when creating a new session.

## Requirements

- macOS, Node 22.12+ on the 22.x line or Node 24+, and npm 10+.
- Authenticated Codex CLI 0.153.4. The integration uses that version's experimental app-server dynamic-tool protocol; a different version requires compatibility validation.
- Android: JDK17, Android SDK platform/build tools required by the repository, emulator, and a compatible installed phone AVD. Create an AVD in Android Studio if only its system image is installed. The harness uses its configuration as a template without copying its app data. Choose an AVD with the desired Android version under advanced device settings.
- iOS: selected Xcode with an installed iPhone simulator runtime, iOS 16.4 or newer. Simulator.app must be closed before headless startup; other simulators are never deliberately shut down.

Appium 3.7.0, XCUITest 12.11.0, UiAutomator2 8.6.1, and WebdriverIO 9.31.7 are local pinned dependencies. No global Appium installation or BrowserStack account is used. Android selects JDK17 and uses `swangle` to avoid the documented Apple Silicon WebView GPU failure.

iOS 18.6 is the validated default on this machine; newer installed runtimes remain available as advanced overrides. The adapter includes the simulator host-process alias required by Appium's Web Inspector matching.

Native validation used an ARM64 Android 36.1 Google Play phone image and an iOS 18.6 iPhone simulator. The harness installs the pinned Android automation APK pair sequentially to handle fresh-device setup reliably.

```sh
node tools/stash-robot/scripts/launch.mjs doctor --repo "$PWD"
node tools/stash-robot/scripts/launch.mjs stop --repo "$PWD"
```

## Interaction

The preview refreshes once per second when the device queue is free. Every agent interaction returns actual screenshot content, frame metadata, and relevant UI context. Preview-only frames are not continuously sent to the model.

Prompt the worker with an individual action or a scenario. Take control pauses the worker and waits for dispatched operations before allowing taps, swipes, text entry, rotation, or app controls. Resume sends the changed screen and manual-action history back to the worker. Android Back is platform-specific.

Stop agent leaves the device available. End session stops owned automation processes and the dedicated running device while preserving sample settings. Browser refresh reconnects to the same session; five minutes without connected browsers ends an abandoned session.

Persistence follows the sample app's own storage: saved settings survive, while unsaved URL field values can return to sample defaults after an app restart.

The worker reads repository source for diagnosis and operates the app through a fixed tool catalog. Source edits and sandbox permission escalation are outside this testing workflow. Rebuild compiles the current checkout, including changes made separately by a developer.

## WebView diagnostics

Both sample apps already enable `setInspectableWebViewsEnabled(true)`. Choose the relevant SDK-owned WebView by its URL/title, then inspect DOM, element bounds, computed styles, console/errors, or network activity. Evaluate accepts a JavaScript expression, including an async IIFE, and returns its JSON result.

CSS overrides use one harness-owned stylesheet. Replacing CSS updates that stylesheet; Reset CSS removes it without removing the page's original styles. Reload clears other document changes. Overrides do not persist to source files or reapply automatically after navigation.

Native logs are collected while the sample runs. WebView logs begin when inspection attaches; initial requests before attachment may be absent. Network diagnostics expose metadata, not a complete packet capture. External-browser surfaces remain accessible through native controls but are not SDK-owned WebView inspection targets.

Debugger status and log coverage time appear separately from device availability. iOS supplements Safari Inspector network events with labeled browser Resource Timing entries when Inspector omits cached or service-worker requests; these buffered entries can include resources loaded before attachment.

The HTTP server listens on loopback with a per-session token and origin checks. Session images/logs are temporary; device records and build caches live under the repository's ignored `build/stash-robot` directory. Reset is an explicit operation because entered sample settings survive normal sessions.

## Development and validation

```sh
cd tools/stash-robot
npm ci
npm run typecheck
npm run build
npx playwright install chromium
npm test
```

The test suite uses fake adapters for lifecycle and browser behavior, protocol fixtures for agent events, and a real headless browser to verify CSS replacement/reset. Use a compatible Node runtime for development commands.

Run native acceptance explicitly:

```sh
node --import tsx scripts/smoke.ts android
node --import tsx scripts/smoke.ts ios
node --import tsx scripts/flows-smoke.ts android
node --import tsx scripts/flows-smoke.ts ios
```

These commands build the sample, boot the dedicated device, open the existing HTTPS test checkout, inspect and edit it temporarily, verify console/network/native logging, and stop the device in a `finally` block. Screenshots and a result report are written to ignored `build/stash-robot/acceptance/<platform>` for review. They require connectivity to the existing test checkout.

The flow checks additionally exercise the modal, delayed asynchronous JavaScript evaluation, and external-browser dismissal through native controls. Their evidence is under `acceptance/flows-<platform>`.

`node --import tsx scripts/agent-smoke.ts android` (or `ios`) exercises the actual Codex conversation and verifies image-bearing tool results, visible runtime CSS, and a follow-up turn in the same thread. It uses the cheaper `gpt-5.6-luna` worker for acceptance; normal sessions retain the configured model. `--verify-artifacts` rechecks evidence from the recorded live run without starting a device or another model turn.

`node --import tsx scripts/persistence-smoke.ts android` (or `ios`) verifies app-data retention across sessions and explicit device reset. This acceptance command erases the dedicated harness device's data. For an intentional fresh device outside acceptance, stop the session and run:

```sh
node tools/stash-robot/scripts/launch.mjs reset-device --platform android --repo "$PWD"
```

Shared adapter contracts are in `src/contracts.ts`. Native operations use a serialized queue; coordinates are fractions of the complete screen. The session broker checks frame freshness and translates images into Codex dynamic-tool results. Native app and SDK public APIs are unchanged.
