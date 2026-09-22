import fs from "node:fs/promises";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

import { remote } from "webdriverio";

import type {
  AdapterOptions,
  Check,
  DeviceAdapter,
  DeviceChoice,
  DeviceInfo,
  DoctorReport,
  RawFrame,
  RobotAction,
  StartOptions,
  WebViewAdapter,
  WebViewTarget,
} from "./contracts.js";
import { cssScript, inspectScript, resetCssScript } from "./web-scripts.js";
import {
  delay,
  freePort,
  pngDimensions,
  run,
  spawnManaged,
  startAppium,
  type ManagedProcess,
} from "./process.js";
import {
  IOS_APP_ID,
  MIN_RUNTIME,
  MIN_RUNTIME_LABEL,
  SimDevice,
  SimRuntime,
  chooseRuntime,
  coordinate,
  evaluationValue,
  inspectorProcessBundleId,
  isTransientSimulatorInstallError,
  isOwnedDeviceName,
  ownedDeviceName,
  parseDevices,
  parseRuntimes,
  toDeviceChoices,
  versionNumber,
} from "./ios/helpers.js";

const execFileAsync = promisify(execFile);
const APP_PROJECT = "iOS/Sample/StashNativeSample/StashNativeSample.xcodeproj";
const APP_SCHEME = "StashNativeSample";
const IOS_LOG_PREDICATE = 'process == "StashNativeSample"';

type AnyDriver = any;
type AppiumServer = { port: number; stop: () => Promise<void> };

interface SavedDevice {
  owned: true;
  id: string;
  name: string;
  runtimeId: string;
  runtime: string;
  deviceType?: string;
}

function text(buffer: Buffer): string {
  return buffer.toString("utf8");
}
function now() {
  return new Date().toISOString();
}

async function commandText(
  command: string,
  args: string[],
  signal?: AbortSignal,
  options: { onLine?: (line: string) => void; cwd?: string } = {},
): Promise<string> {
  const result = await run(command, args, {
    signal,
    cwd: options.cwd,
    onLine: options.onLine,
  });
  return text(result.stdout);
}

async function commandOk(
  command: string,
  args: string[],
): Promise<{ ok: boolean; output: string }> {
  try {
    return { ok: true, output: await commandText(command, args) };
  } catch (error) {
    return {
      ok: false,
      output: error instanceof Error ? error.message : String(error),
    };
  }
}

async function isSimulatorOpen(): Promise<boolean> {
  try {
    const result = await execFileAsync("pgrep", ["-x", "Simulator"]);
    return Boolean(result.stdout.trim());
  } catch {
    return false;
  }
}

function unwrap(result: any): unknown {
  return result && Object.prototype.hasOwnProperty.call(result, "value")
    ? result.value
    : result;
}
function returnedScript(script: string): string {
  return `return (${script});`;
}

export function createIosAdapter(options: AdapterOptions): DeviceAdapter {
  const { repoRoot, cacheDir, onLog, onProgress } = options;
  const statePath = path.join(cacheDir, "ios", "device.json");
  let device: DeviceInfo | undefined;
  let savedDevice: SavedDevice | undefined;
  let driver: AnyDriver | undefined;
  let appium: AppiumServer | undefined;
  let logProcess: ManagedProcess | undefined;
  let activeSimId: string | undefined;
  let currentContext = "NATIVE_APP";
  let lastBrowserLogWarning = false;
  let contextRequest: Promise<any[]> | undefined;
  let captureSequence = 0;
  let logicalDeviceSize: { width: number; height: number } | undefined;
  const seenPerformanceEntries = new Set<string>();
  let webviewCoverageSince: string | undefined;
  let webviewStatusDetail = "iOS driver is not connected";

  const iosCache = path.join(cacheDir, "ios");
  const derivedData = path.join(cacheDir, "ios", "derived-data");

  async function readSaved(): Promise<SavedDevice | undefined> {
    if (savedDevice) return savedDevice;
    try {
      const parsed = JSON.parse(
        await fs.readFile(statePath, "utf8"),
      ) as SavedDevice;
      if (parsed.owned === true && parsed.id && parsed.runtimeId)
        savedDevice = parsed;
    } catch {
      /* no harness device yet */
    }
    return savedDevice;
  }

  async function saveSaved(value: SavedDevice): Promise<void> {
    savedDevice = value;
    await fs.mkdir(iosCache, { recursive: true });
    await fs.writeFile(
      statePath,
      `${JSON.stringify(value, null, 2)}\n`,
      "utf8",
    );
  }

  async function runtimes(): Promise<SimRuntime[]> {
    try {
      const parsed = JSON.parse(
        await commandText("xcrun", ["simctl", "list", "runtimes", "-j"]),
      ) as {
        runtimes?: Array<{
          identifier?: string;
          version?: string;
          name?: string;
          isAvailable?: boolean;
        }>;
      };
      const values = (parsed.runtimes || []).filter(
        (item) =>
          item.isAvailable !== false &&
          item.identifier?.includes(".SimRuntime.iOS-") &&
          item.version,
      );
      if (values.length) {
        const unique = new Map<
          string,
          { id: string; version: string; name: string }
        >();
        for (const item of values) {
          const candidate = {
            id: item.identifier!,
            version: item.version!,
            name: item.name || `iOS ${item.version}`,
          };
          const current = unique.get(candidate.id);
          if (
            !current ||
            versionNumber(candidate.version) > versionNumber(current.version)
          )
            unique.set(candidate.id, candidate);
        }
        return [...unique.values()];
      }
    } catch {
      /* fall back for older Xcode */
    }
    return parseRuntimes(
      await commandText("xcrun", ["simctl", "list", "runtimes"]),
    );
  }

  async function devices(allRuntimes?: SimRuntime[]): Promise<SimDevice[]> {
    const knownRuntimes = allRuntimes || (await runtimes());
    try {
      const parsed = JSON.parse(
        await commandText("xcrun", [
          "simctl",
          "list",
          "devices",
          "available",
          "-j",
        ]),
      ) as {
        devices?: Record<
          string,
          Array<{
            udid?: string;
            name?: string;
            state?: string;
            isAvailable?: boolean;
            deviceTypeIdentifier?: string;
          }>
        >;
      };
      const result: SimDevice[] = [];
      for (const [runtimeId, entries] of Object.entries(parsed.devices || {})) {
        const runtime = knownRuntimes.find((item) => item.id === runtimeId);
        for (const item of entries || [])
          if (item.udid && item.name && item.state)
            result.push({
              id: item.udid,
              name: item.name,
              state: item.state,
              runtimeId,
              runtime: runtime?.version,
              deviceType: item.deviceTypeIdentifier,
            });
      }
      if (result.length) return result;
    } catch {
      /* fall back for older Xcode */
    }
    return parseDevices(
      await commandText("xcrun", ["simctl", "list", "devices", "available"]),
      knownRuntimes,
    );
  }

  async function deviceType(
    preferred?: string,
    runtimeVersion?: string,
  ): Promise<string> {
    try {
      const parsed = JSON.parse(
        await commandText("xcrun", ["simctl", "list", "devicetypes", "-j"]),
      ) as { devicetypes?: Array<{ identifier?: string; name?: string }> };
      const types = (parsed.devicetypes || []).filter(
        (item) => item.identifier && item.name?.startsWith("iPhone"),
      );
      const exact = types.find((item) => item.identifier === preferred);
      if (
        exact &&
        !(
          versionNumber(runtimeVersion || "0") < 26_000_000 &&
          /iPhone\s+(17|Air)/.test(exact.name || "")
        )
      )
        return exact.identifier!;
      const candidates =
        versionNumber(runtimeVersion || "0") < 26_000_000
          ? types.filter((item) => !/iPhone\s+(17|Air)/.test(item.name || ""))
          : types;
      const latest = [...(candidates.length ? candidates : types)].sort(
        (a, b) => {
          const av = Number(a.name?.match(/iPhone\s+(\d+)/)?.[1] || 0);
          const bv = Number(b.name?.match(/iPhone\s+(\d+)/)?.[1] || 0);
          return (
            bv - av ||
            Number(b.name?.includes("Pro")) - Number(a.name?.includes("Pro"))
          );
        },
      )[0];
      if (latest?.identifier) return latest.identifier;
    } catch {
      /* fall back to a device type available since iOS 16 */
    }
    return "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro";
  }

  function selectRuntime(
    available: SimRuntime[],
    requested?: string,
    retained?: string,
  ): SimRuntime | undefined {
    if (requested || retained)
      return chooseRuntime(available, requested || retained);
    // Prefer the latest conventional iOS runtime by default. Newer installed
    // runtimes remain available as explicit advanced overrides.
    const tested = available.filter(
      (item) => versionNumber(item.version) < 19_000_000,
    );
    return chooseRuntime(tested.length ? tested : available);
  }

  async function resolveDevice(
    start: StartOptions,
  ): Promise<{ runtime: SimRuntime; sim: SimDevice }> {
    const availableRuntimes = await runtimes();
    const existing = await readSaved();
    let runtime = selectRuntime(
      availableRuntimes,
      start.runtime,
      existing?.runtimeId,
    );
    if (!runtime)
      throw new Error(
        start.runtime
          ? `Requested iOS runtime is unavailable: ${start.runtime}`
          : `No iOS runtime >= ${MIN_RUNTIME_LABEL} is installed`,
      );
    const availableDevices = await devices(availableRuntimes);
    if (start.device) {
      const explicit = availableDevices.find(
        (item) => item.id === start.device || item.name === start.device,
      );
      if (!explicit)
        throw new Error(`iOS simulator not found: ${start.device}`);
      if (existing?.id === explicit.id && existing.runtimeId === runtime.id)
        return { runtime, sim: explicit };
      if (!start.runtime && explicit.runtimeId)
        runtime =
          chooseRuntime(availableRuntimes, explicit.runtimeId) || runtime;
      const selectedRuntime = runtime;
      const selectedType = await deviceType(
        explicit.deviceType,
        selectedRuntime.version,
      );
      const ownedName = ownedDeviceName(repoRoot, explicit.name);
      const owned = availableDevices.find(
        (item) =>
          item.name === ownedName &&
          item.runtimeId === selectedRuntime.id &&
          item.deviceType === selectedType,
      );
      if (owned) {
        await saveSaved({
          owned: true,
          id: owned.id,
          name: owned.name,
          runtimeId: selectedRuntime.id,
          runtime: selectedRuntime.version,
          deviceType: selectedType,
        });
        return { runtime: selectedRuntime, sim: owned };
      }
      onProgress(
        `Creating dedicated iOS simulator (${ownedName}) from ${explicit.name}`,
      );
      const createdId = (
        await commandText("xcrun", [
          "simctl",
          "create",
          ownedName,
          selectedType,
          selectedRuntime.id,
        ])
      ).trim();
      if (!/^[0-9A-Fa-f-]{20,}$/.test(createdId))
        throw new Error(
          `simctl create returned an invalid device id: ${createdId}`,
        );
      const created = {
        id: createdId,
        name: ownedName,
        state: "Shutdown",
        runtimeId: selectedRuntime.id,
        runtime: selectedRuntime.version,
        deviceType: selectedType,
      };
      await saveSaved({
        owned: true,
        id: createdId,
        name: ownedName,
        runtimeId: selectedRuntime.id,
        runtime: selectedRuntime.version,
        deviceType: selectedType,
      });
      return { runtime: selectedRuntime, sim: created };
    }
    const defaultOwnedName = ownedDeviceName(repoRoot);
    if (
      existing &&
      existing.runtimeId === runtime.id &&
      isOwnedDeviceName(repoRoot, existing.name)
    ) {
      const match = availableDevices.find((item) => item.id === existing.id);
      if (match) return { runtime, sim: match };
    }
    const preferred = availableDevices.find(
      (item) => item.name === defaultOwnedName && item.runtimeId === runtime.id,
    );
    if (preferred) {
      await saveSaved({
        owned: true,
        id: preferred.id,
        name: preferred.name,
        runtimeId: runtime.id,
        runtime: runtime.version,
        deviceType: preferred.deviceType,
      });
      return { runtime, sim: preferred };
    }
    const name = defaultOwnedName;
    const selectedType = await deviceType(undefined, runtime.version);
    onProgress(`Creating dedicated iOS simulator (${name})`);
    const output = await commandText("xcrun", [
      "simctl",
      "create",
      name,
      selectedType,
      runtime.id,
    ]);
    const id = output.trim();
    if (!/^[0-9A-Fa-f-]{20,}$/.test(id))
      throw new Error(`simctl create returned an invalid device id: ${id}`);
    const sim = {
      id,
      name,
      state: "Shutdown",
      runtimeId: runtime.id,
      runtime: runtime.version,
      deviceType: selectedType,
    };
    await saveSaved({
      owned: true,
      id,
      name,
      runtimeId: runtime.id,
      runtime: runtime.version,
      deviceType: selectedType,
    });
    return { runtime, sim };
  }

  async function build(simId: string, signal?: AbortSignal): Promise<string> {
    await fs.mkdir(derivedData, { recursive: true });
    const project = path.join(repoRoot, APP_PROJECT);
    onProgress("Building StashNativeSample for iOS Simulator");
    await commandText(
      "xcodebuild",
      [
        "-project",
        project,
        "-scheme",
        APP_SCHEME,
        "-configuration",
        "Debug",
        "-sdk",
        "iphonesimulator",
        `-destination`,
        `id=${simId}`,
        "-derivedDataPath",
        derivedData,
        "CODE_SIGNING_ALLOWED=NO",
        "build",
      ],
      signal,
      { onLine: (line) => onProgress(line) },
    );
    const app = path.join(
      derivedData,
      "Build",
      "Products",
      "Debug-iphonesimulator",
      "StashNativeSample.app",
    );
    try {
      await fs.access(app);
    } catch {
      throw new Error(`xcodebuild completed but app was not found at ${app}`);
    }
    return app;
  }

  async function ensureBooted(
    simId: string,
    signal?: AbortSignal,
  ): Promise<void> {
    let state = "";
    try {
      const listed = parseDevices(
        await commandText(
          "xcrun",
          ["simctl", "list", "devices", "available"],
          signal,
        ),
      );
      state = listed.find((item) => item.id === simId)?.state || "";
    } catch {
      /* boot below reports the actual error */
    }
    if (state !== "Booted")
      await commandText("xcrun", ["simctl", "boot", simId], signal).catch(
        (error) => {
          if (!String(error).includes("already booted")) throw error;
        },
      );
    await commandText("xcrun", ["simctl", "bootstatus", simId, "-b"], signal);
  }

  async function launchNativeLogs(simId: string): Promise<void> {
    if (logProcess) return;
    logProcess = spawnManaged(
      "xcrun",
      [
        "simctl",
        "spawn",
        simId,
        "log",
        "stream",
        "--style",
        "compact",
        "--level",
        "debug",
        "--predicate",
        IOS_LOG_PREDICATE,
      ],
      {
        onLine: (line: string) =>
          onLog({
            timestamp: now(),
            source: "native",
            level: "info",
            message: line,
          }),
      },
    );
  }

  async function installApp(
    simId: string,
    appPath: string,
    signal?: AbortSignal,
  ): Promise<void> {
    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        await commandText(
          "xcrun",
          ["simctl", "install", simId, appPath],
          signal,
        );
        return;
      } catch (error) {
        if (attempt === 3 || !isTransientSimulatorInstallError(error)) {
          throw error;
        }
        onProgress(
          `CoreSimulator install metadata was not ready (attempt ${attempt}/3); waiting for boot readiness before retry`,
        );
        await commandText(
          "xcrun",
          ["simctl", "bootstatus", simId, "-b"],
          signal,
        );
        await delay(1_500, signal);
      }
    }
  }

  async function cleanupWda(simId: string): Promise<void> {
    const marker = "appium-webdriveragent";
    const derivedMarker = path.join(cacheDir, "ios", "wda-derived-data");
    try {
      const result = await execFileAsync("pgrep", [
        "-f",
        `${marker}.*${derivedMarker}.*destination id=${simId}`,
      ]);
      const pids = String(result.stdout)
        .trim()
        .split(/\s+/)
        .map(Number)
        .filter(
          (pid) => Number.isInteger(pid) && pid > 1 && pid !== process.pid,
        );
      for (const pid of pids) {
        try {
          process.kill(pid, "SIGTERM");
        } catch {
          /* exited */
        }
      }
      if (pids.length) await new Promise((resolve) => setTimeout(resolve, 500));
      for (const pid of pids) {
        try {
          process.kill(pid, "SIGKILL");
        } catch {
          /* exited */
        }
      }
    } catch {
      /* pgrep returns 1 when no WDA process remains */
    }
  }

  async function connectAppium(
    runtime: SimRuntime,
    sim: SimDevice,
    signal?: AbortSignal,
  ): Promise<void> {
    if (await isSimulatorOpen()) {
      throw new Error(
        "Simulator.app was opened while the iOS app was building. Quit it before starting a headless stash-robot session.",
      );
    }
    onProgress("Starting Appium XCUITest");
    // process.ts owns the Appium lifecycle and installs the pinned driver.
    const server = await startAppium(options, "xcuitest", signal);
    appium = server;
    const wdaLocalPort = await freePort();
    const mjpegServerPort = await freePort();
    try {
      driver = await remote({
        hostname: "127.0.0.1",
        port: server.port,
        path: "/",
        logLevel: "silent",
        connectionRetryCount: 0,
        connectionRetryTimeout: 180_000,
        capabilities: {
          platformName: "iOS",
          "appium:automationName": "XCUITest",
          "appium:udid": sim.id,
          "appium:deviceName": sim.name,
          "appium:platformVersion": runtime.version,
          "appium:bundleId": IOS_APP_ID,
          "appium:noReset": true,
          "appium:fullReset": false,
          "appium:isHeadless": true,
          "appium:wdaLocalPort": wdaLocalPort,
          "appium:mjpegServerPort": mjpegServerPort,
          "appium:derivedDataPath": path.join(
            cacheDir,
            "ios",
            "wda-derived-data",
          ),
          "appium:webviewConnectTimeout": 5_000,
          "appium:webviewConnectRetries": 3,
          // iOS 18 simulators report the app hosting an inspectable WKWebView by its
          // executable process name. Without this alias Appium only tries the
          // WebContent helper process, whose page dictionary is empty.
          "appium:additionalWebviewBundleIds": [
            inspectorProcessBundleId(APP_SCHEME),
          ],
          "appium:showSafariConsoleLog": true,
          "appium:showSafariNetworkLog": true,
          "appium:newCommandTimeout": 300,
        },
      });
      // XCUITest otherwise exposes a near-zero async-script timeout on this
      // stack, which rejects valid async IIFEs before their first timer or rAF.
      await driver.setTimeout({ script: 30_000 });
    } catch (error) {
      await server.stop().catch(() => undefined);
      await cleanupWda(sim.id);
      appium = undefined;
      throw error;
    }
    currentContext = "NATIVE_APP";
  }

  async function cacheNativeWindowSize(): Promise<{
    width: number;
    height: number;
  }> {
    if (!driver || currentContext !== "NATIVE_APP") {
      if (!logicalDeviceSize)
        throw new Error("Native iOS window size is unavailable");
      return logicalDeviceSize;
    }
    const bounds = await driver.getWindowSize();
    const width = Number(bounds.width);
    const height = Number(bounds.height);
    if (!(width > 0 && height > 0))
      throw new Error("XCUITest returned an invalid native window size");
    logicalDeviceSize = { width, height };
    return logicalDeviceSize;
  }

  async function withWebView<T>(
    targetId: string | undefined,
    callback: () => Promise<T>,
  ): Promise<T> {
    if (!driver) throw new Error("iOS driver is not connected");
    const target =
      targetId ||
      normalizeContexts(await listContexts()).find(
        (item) => item !== "NATIVE_APP",
      );
    if (!target) throw new Error("No inspectable WKWebView is attached");
    if (currentContext !== target) {
      await driver.switchContext(target);
      currentContext = target;
    }
    webviewCoverageSince ||= now();
    webviewStatusDetail =
      "Safari Inspector console/network events enabled; Resource Timing supplements cached and service-worker requests";
    // Keep the debugger attached across consecutive WebView operations. Apart
    // from avoiding needless protocol work, this prevents XCUITest from adding
    // duplicate Safari console/network listeners on every context switch.
    return callback();
  }

  async function listContexts(): Promise<any[]> {
    if (!driver) return [];
    // A WebDriver command cannot be cancelled after it reaches Appium. Reuse the
    // in-flight request so repeated preview polling cannot queue orphaned context
    // commands behind a client-side timeout.
    if (!contextRequest) {
      contextRequest = Promise.resolve(driver.getContexts())
        .then((value: unknown) => {
          const contexts = Array.isArray(value) ? value : [];
          if (
            normalizeContexts(contexts).some((item) => item !== "NATIVE_APP")
          ) {
            webviewCoverageSince ||= now();
            webviewStatusDetail =
              "Safari Inspector console/network events enabled; Resource Timing supplements cached and service-worker requests";
          } else {
            webviewCoverageSince = undefined;
            webviewStatusDetail =
              "No inspectable WKWebView is currently attached";
          }
          return contexts;
        })
        .catch((error) => {
          webviewCoverageSince = undefined;
          webviewStatusDetail = `Web Inspector context discovery failed: ${String(error)}`;
          throw error;
        })
        .finally(() => {
          contextRequest = undefined;
        });
    }
    return contextRequest;
  }

  function contextId(context: any): string {
    return String(
      typeof context === "string"
        ? context
        : context?.id || context?.webviewPageId || "",
    );
  }

  function normalizeContexts(contexts: any[]): string[] {
    return contexts.map(contextId).filter(Boolean);
  }

  const webview: WebViewAdapter = {
    status() {
      return webviewCoverageSince
        ? {
            connected: true,
            coverageSince: webviewCoverageSince,
            detail: webviewStatusDetail,
          }
        : { connected: false, detail: webviewStatusDetail };
    },
    async listTargets(signal) {
      if (!driver) return [];
      if (signal?.aborted)
        throw new DOMException("The operation was aborted", "AbortError");
      const contexts = await listContexts();
      const targets: WebViewTarget[] = [];
      for (const context of contexts as any[]) {
        const id = contextId(context);
        if (id === "NATIVE_APP") continue;
        try {
          const meta = await withWebView(
            id,
            async () =>
              unwrap(
                await driver.execute(
                  returnedScript(
                    `({url: location.href, title: document.title})`,
                  ),
                ),
              ) as any,
          );
          targets.push({
            id,
            appId: IOS_APP_ID,
            url: String(meta?.url || ""),
            title: String(meta?.title || ""),
          });
        } catch (error) {
          onLog({
            timestamp: now(),
            source: "driver",
            level: "warn",
            message: `WebView target ${id} is unavailable`,
            details: String(error),
          });
        }
      }
      if (!targets.length && contexts.length > 1)
        onLog({
          timestamp: now(),
          source: "driver",
          level: "warn",
          message: "No WebView target is currently attached",
        });
      return targets;
    },
    async inspect(targetId, selector, signal) {
      if (signal?.aborted)
        throw new DOMException("The operation was aborted", "AbortError");
      return withWebView(targetId, async () =>
        unwrap(await driver.execute(returnedScript(inspectScript(selector)))),
      );
    },
    async evaluate(script, targetId, signal) {
      if (signal?.aborted)
        throw new DOMException("The operation was aborted", "AbortError");
      return withWebView(targetId, async () => {
        // WebdriverIO already unwraps the WebDriver protocol envelope. Keep this
        // result object intact because its own `value` member is application data.
        const response = (await driver.executeAsync(function (
          expression: string,
          done: (value: unknown) => void,
        ) {
          try {
            Promise.resolve(eval(expression)).then(
              (value) => done({ ok: true, value }),
              (error) => done({ ok: false, error: String(error) }),
            );
          } catch (error) {
            done({ ok: false, error: String(error) });
          }
        }, script)) as { ok?: boolean; value?: unknown; error?: string };
        return evaluationValue(response);
      });
    },
    async setCss(css, targetId, signal) {
      if (signal?.aborted)
        throw new DOMException("The operation was aborted", "AbortError");
      return withWebView(targetId, async () =>
        unwrap(await driver.execute(returnedScript(cssScript(css)))),
      );
    },
    async resetCss(targetId, signal) {
      if (signal?.aborted)
        throw new DOMException("The operation was aborted", "AbortError");
      return withWebView(targetId, async () =>
        unwrap(await driver.execute(returnedScript(resetCssScript))),
      );
    },
    async reload(targetId, signal) {
      if (signal?.aborted)
        throw new DOMException("The operation was aborted", "AbortError");
      await withWebView(targetId, async () => {
        await driver.refresh();
      });
    },
    async pollLogs() {
      if (!driver || typeof driver.getLogs !== "function") return;
      let safariNetworkEntries = 0;
      for (const type of ["safariConsole", "safariNetwork"]) {
        try {
          const entries = await driver.getLogs(type);
          if (type === "safariNetwork")
            safariNetworkEntries += entries?.length || 0;
          for (const entry of entries || [])
            onLog({
              timestamp: now(),
              source: type === "safariConsole" ? "console" : "network",
              level: String(entry.level || "info"),
              message: String(entry.message || entry),
              details: entry,
            });
        } catch (error) {
          if (!lastBrowserLogWarning) {
            lastBrowserLogWarning = true;
            onLog({
              timestamp: now(),
              source: "driver",
              level: "warn",
              message: "iOS WebView console/network log polling is unavailable",
              details: String(error),
            });
          }
        }
      }
      // WebKit occasionally omits Inspector Network events for requests served
      // from its cache or a service worker. Resource Timing is exposed by the
      // inspected page itself and preserves useful URL/type/timing/size metadata.
      if (!safariNetworkEntries && currentContext !== "NATIVE_APP") {
        try {
          const entries = unwrap(
            await driver.execute(
              returnedScript(
                `performance.getEntriesByType('resource').map(entry => ({name: entry.name, initiatorType: entry.initiatorType, startTime: entry.startTime, duration: entry.duration, transferSize: entry.transferSize, encodedBodySize: entry.encodedBodySize, decodedBodySize: entry.decodedBodySize}))`,
              ),
            ),
          ) as any[];
          for (const entry of Array.isArray(entries) ? entries : []) {
            const key = JSON.stringify([
              entry.name,
              entry.initiatorType,
              entry.startTime,
              entry.duration,
            ]);
            if (seenPerformanceEntries.has(key)) continue;
            seenPerformanceEntries.add(key);
            onLog({
              timestamp: now(),
              source: "network",
              level: "info",
              message: `${entry.initiatorType || "resource"} ${entry.name}`,
              details: { source: "performance-resource-timing", ...entry },
            });
          }
        } catch {
          /* the target may have closed between polling and evaluation */
        }
      }
    },
    async stop() {
      /* lifecycle is owned by the device adapter */
    },
  };

  const adapter: DeviceAdapter = {
    platform: "ios",
    webview,
    async doctor(): Promise<DoctorReport> {
      const checks: Check[] = [];
      const xcode = await commandOk("xcodebuild", ["-version"]);
      checks.push({
        name: "Xcode",
        ok: xcode.ok,
        detail: xcode.ok
          ? xcode.output.split(/\r?\n/)[0] || "available"
          : xcode.output,
      });
      const simctl = await commandOk("xcrun", ["simctl", "list", "runtimes"]);
      const availableRuntimes = simctl.ok
        ? await runtimes().catch(() => parseRuntimes(simctl.output))
        : [];
      const compatible = availableRuntimes.filter(
        (item) => versionNumber(item.version) >= MIN_RUNTIME,
      );
      checks.push({
        name: "iOS Simulator runtime",
        ok: compatible.length > 0,
        detail: compatible.length
          ? compatible.map((item) => item.name).join(", ")
          : `Install an iOS runtime >= ${MIN_RUNTIME_LABEL}`,
      });
      const listedDevices = simctl.ok
        ? await devices(availableRuntimes).catch(() => [])
        : [];
      const iphoneDevices = listedDevices.filter(
        (item) =>
          item.deviceType?.includes(".SimDeviceType.iPhone-") ||
          item.name.startsWith("iPhone") ||
          isOwnedDeviceName(repoRoot, item.name),
      );
      checks.push({
        name: "iPhone simulator",
        ok: iphoneDevices.some((item) => item.state !== "Unavailable"),
        detail: iphoneDevices.length
          ? `${iphoneDevices.length} available iPhone simulator(s)`
          : "Install an iPhone simulator runtime/device",
      });
      const simulatorOpen = await isSimulatorOpen();
      checks.push({
        name: "Simulator app conflict",
        ok: !simulatorOpen,
        detail: simulatorOpen
          ? "Quit Simulator.app before starting a headless session"
          : "Simulator.app is closed",
      });
      return {
        platform: "ios",
        ready: checks.every((check) => check.ok),
        checks,
        devices: toDeviceChoices(
          iphoneDevices.filter(
            (item) =>
              !item.runtime || versionNumber(item.runtime) >= MIN_RUNTIME,
          ),
        ),
        runtimes: compatible.map((item) => ({
          id: item.id,
          name: item.name,
          runtime: item.version,
        })),
      };
    },
    async start(startOptions, signal) {
      if (await isSimulatorOpen())
        throw new Error(
          "Simulator.app is open. Quit it before starting a headless stash-robot iOS session.",
        );
      const resolved = await resolveDevice(startOptions);
      activeSimId = resolved.sim.id;
      try {
        const app = await build(resolved.sim.id, signal);
        await ensureBooted(resolved.sim.id, signal);
        onProgress("Installing sample app");
        await installApp(resolved.sim.id, app, signal);
        await launchNativeLogs(resolved.sim.id);
        await connectAppium(resolved.runtime, resolved.sim, signal);
        webviewCoverageSince = undefined;
        webviewStatusDetail = "No inspectable WKWebView is currently attached";
        onProgress("Launching sample app");
        await driver.activateApp(IOS_APP_ID);
        await cacheNativeWindowSize();
        device = {
          platform: "ios",
          id: resolved.sim.id,
          name: resolved.sim.name,
          runtime: resolved.runtime.version,
          appId: IOS_APP_ID,
        };
        return device;
      } catch (error) {
        await adapter.stop();
        throw error;
      }
    },
    async capture(signal): Promise<RawFrame> {
      if (!device) throw new Error("iOS session has not started");
      const outputPath = path.join(
        iosCache,
        `capture-${process.pid}-${captureSequence++}.png`,
      );
      await fs.mkdir(iosCache, { recursive: true });
      let png: Buffer;
      try {
        await run(
          "xcrun",
          ["simctl", "io", device.id, "screenshot", "--type=png", outputPath],
          { signal },
        );
        png = await fs.readFile(outputPath);
      } finally {
        await fs.rm(outputPath, { force: true }).catch(() => undefined);
      }
      const size = pngDimensions(png);
      let logicalWidth = logicalDeviceSize?.width || size.width;
      let logicalHeight = logicalDeviceSize?.height || size.height;
      // In a WebView context XCUITest forwards this command to WebKit, where it
      // can wait for a response indefinitely. Native captures establish and
      // refresh the logical point size used for coordinate actions.
      if (driver && currentContext === "NATIVE_APP") {
        try {
          const windowSize = await cacheNativeWindowSize();
          logicalWidth = windowSize.width;
          logicalHeight = windowSize.height;
        } catch {
          /* screenshot dimensions are a safe fallback */
        }
      }
      return {
        png,
        width: size.width,
        height: size.height,
        logicalWidth,
        logicalHeight,
      };
    },
    async hierarchy(signal) {
      if (!driver) throw new Error("iOS driver is not connected");
      if (currentContext !== "NATIVE_APP") {
        await driver.switchContext("NATIVE_APP");
        currentContext = "NATIVE_APP";
      }
      return String(await driver.getPageSource());
    },
    async act(action: RobotAction, signal) {
      if (!driver) throw new Error("iOS driver is not connected");
      if (signal?.aborted)
        throw new DOMException("The operation was aborted", "AbortError");
      if (currentContext !== "NATIVE_APP") {
        await driver.switchContext("NATIVE_APP");
        currentContext = "NATIVE_APP";
      }
      onProgress(`iOS action: ${action.type}`);
      const bounds = await cacheNativeWindowSize();
      const { width, height } = bounds;
      switch (action.type) {
        case "tap":
          await driver.performActions([
            {
              type: "pointer",
              id: "stash-robot-touch",
              parameters: { pointerType: "touch" },
              actions: [
                {
                  type: "pointerMove",
                  duration: 0,
                  x: coordinate(action.x, width),
                  y: coordinate(action.y, height),
                },
                { type: "pointerDown", button: 0 },
                { type: "pointerUp", button: 0 },
              ],
            },
          ]);
          await driver.releaseActions();
          break;
        case "swipe":
          await driver.performActions([
            {
              type: "pointer",
              id: "stash-robot-touch",
              parameters: { pointerType: "touch" },
              actions: [
                {
                  type: "pointerMove",
                  duration: 0,
                  x: coordinate(action.fromX, width),
                  y: coordinate(action.fromY, height),
                },
                { type: "pointerDown", button: 0 },
                {
                  type: "pointerMove",
                  duration: action.durationMs ?? 500,
                  x: coordinate(action.toX, width),
                  y: coordinate(action.toY, height),
                },
                { type: "pointerUp", button: 0 },
              ],
            },
          ]);
          await driver.releaseActions();
          break;
        case "tapElement":
          await (await driver.$(`~${action.selector}`)).click();
          break;
        case "type": {
          const element = action.selector
            ? await driver.$(`~${action.selector}`)
            : undefined;
          if (element) {
            await element.click();
            await element.setValue(action.text);
          } else await driver.keys(action.text);
          break;
        }
        case "hideKeyboard":
          // XCUITest's hideKeyboard endpoint can wait indefinitely when UIKit has already
          // dismissed the keyboard. Escape is immediate and is harmless in that state.
          await driver.keys(["\uE00C"]).catch(() => undefined);
          break;
        case "back":
          await driver.back();
          break;
        case "home":
          await driver.execute("mobile: pressButton", { name: "home" });
          break;
        case "rotate":
          await driver.setOrientation(
            action.orientation === "portrait" ? "PORTRAIT" : "LANDSCAPE",
          );
          await cacheNativeWindowSize();
          break;
      }
    },
    async restart(signal) {
      if (!device || !driver) throw new Error("iOS session has not started");
      if (currentContext !== "NATIVE_APP") {
        await driver.switchContext("NATIVE_APP");
        currentContext = "NATIVE_APP";
      }
      await driver.terminateApp(IOS_APP_ID);
      webviewCoverageSince = undefined;
      webviewStatusDetail = "No inspectable WKWebView is currently attached";
      await driver.activateApp(IOS_APP_ID);
      seenPerformanceEntries.clear();
      await new Promise((resolve) => setTimeout(resolve, 500));
      if (signal?.aborted)
        throw new DOMException("The operation was aborted", "AbortError");
    },
    async rebuild(signal) {
      if (!device) throw new Error("iOS session has not started");
      await driver?.deleteSession().catch(() => undefined);
      driver = undefined;
      if (appium) {
        await appium.stop().catch(() => undefined);
        appium = undefined;
      }
      const app = await build(device.id, signal);
      await installApp(device.id, app, signal);
      const selectedRuntime = chooseRuntime(await runtimes(), device.runtime);
      const sim = {
        id: device.id,
        name: device.name,
        state: "Booted",
        runtimeId: selectedRuntime?.id || "",
        runtime: device.runtime,
      };
      await connectAppium(
        selectedRuntime || {
          id: "",
          name: `iOS ${device.runtime}`,
          version: device.runtime,
        },
        sim,
        signal,
      );
      await driver.activateApp(IOS_APP_ID);
    },
    async stop() {
      const simId = activeSimId;
      await driver?.deleteSession().catch(() => undefined);
      driver = undefined;
      await appium?.stop().catch(() => undefined);
      appium = undefined;
      if (simId) await cleanupWda(simId);
      await logProcess?.stop().catch(() => undefined);
      logProcess = undefined;
      if (simId)
        await commandText("xcrun", ["simctl", "shutdown", simId]).catch(
          () => undefined,
        );
      activeSimId = undefined;
      device = undefined;
      currentContext = "NATIVE_APP";
      contextRequest = undefined;
      logicalDeviceSize = undefined;
      seenPerformanceEntries.clear();
      webviewCoverageSince = undefined;
      webviewStatusDetail = "iOS driver is not connected";
    },
    async reset(startOptions = {}) {
      if (device)
        throw new Error("Stop the iOS session before resetting its device");
      const existing = await readSaved();
      if (!existing) return;
      if (!isOwnedDeviceName(repoRoot, existing.name))
        throw new Error(
          "Saved iOS device is not owned by this stash-robot repository",
        );
      if (startOptions.device && startOptions.device !== existing.id) {
        const requested = (await devices()).find(
          (item) =>
            item.id === startOptions.device ||
            item.name === startOptions.device,
        );
        const expectedName =
          requested && isOwnedDeviceName(repoRoot, requested.name)
            ? requested.name
            : requested
              ? ownedDeviceName(repoRoot, requested.name)
              : undefined;
        if (!requested || existing.name !== expectedName)
          throw new Error(
            "reset-device only accepts the currently selected harness-owned simulator profile",
          );
      }
      await commandText("xcrun", ["simctl", "shutdown", existing.id]).catch(
        () => undefined,
      );
      await commandText("xcrun", ["simctl", "erase", existing.id]);
    },
  };
  return adapter;
}

export {
  IOS_APP_ID,
  MIN_RUNTIME,
  MIN_RUNTIME_LABEL,
  parseDevices,
  parseRuntimes,
  chooseRuntime,
  coordinate,
  evaluationValue,
  inspectorProcessBundleId,
  isTransientSimulatorInstallError,
  isOwnedDeviceName,
  ownedDeviceName,
} from "./ios/helpers.js";
