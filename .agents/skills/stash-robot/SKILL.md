---
name: stash-robot
description: Run the Stash Native sample on a headless Android or iOS simulator through a local browser interface, follow visual testing scenarios, and diagnose checkout WebViews with temporary CSS or JavaScript changes.
---

# Stash Robot

Use the repository's maintained harness to launch an interactive testing session. The browser owns platform selection, device controls, diagnostics, and a dedicated Codex conversation.

## Launch

Locate the stash-native checkout containing `tools/stash-robot/package.json`. When this skill is installed through a symlink, resolve the skill directory to its real path; the checkout is three directories above the skill directory.

Run from the checkout:

```sh
node tools/stash-robot/scripts/launch.mjs start --daemon --repo "$PWD"
```

Pass a supplied scenario as one literal `--scenario` argument. Use proper argument quoting; do not interpolate a user's prompt into shell code. The launcher selects a compatible installed Node runtime and installs dependencies from the lockfile when needed. It does not install Xcode, Android SDKs, or simulator system images.

Report the local browser URL returned by the launcher. Let the user choose Android or iOS in that interface. Do not start a second agent or simulator yourself: the harness owns their lifecycle. Use `--model` and `--effort` only when the user requests overrides; otherwise the worker inherits Codex configuration.

## Testing and debugging

The worker sees real screenshot images after its actions and can inspect the native accessibility hierarchy. It can open the sample's card, modal, and browser flows through the existing URL fields and launch buttons. The sample already enables `setInspectableWebViewsEnabled(true)` before creating checkout views.

Use the browser chat for individual instructions or scenarios. The worker has tools for native interaction, observation, logs, app restart/rebuild, and WebView diagnostics. Runtime CSS is applied to a dedicated stylesheet; Reset CSS removes it. Reload clears other document edits. Page changes are not persisted to repository source or automatically reapplied after navigation.

The browser's Take control action pauses agent operations before manual input. Resume supplies the changed screen to the worker. A stopped agent leaves the device available; End session releases the owned runtime processes while retaining sample settings.

## Troubleshooting and cleanup

```sh
node tools/stash-robot/scripts/launch.mjs doctor --repo "$PWD"
node tools/stash-robot/scripts/launch.mjs stop --repo "$PWD"
```

Use the readiness report to resolve missing tools or runtimes. iOS headless startup requires Simulator.app to be closed because Appium's headless mode otherwise terminates its windows. Android selects JDK17 and uses the documented Apple Silicon WebView GPU setting.

Reset device data only when the user requests a fresh device; routine restarts preserve entered sample settings. The harness uses dedicated devices and must not shut down or erase unrelated simulators.

Read the harness [README](../../../tools/stash-robot/README.md) for CLI details, prerequisites, and validation commands.
