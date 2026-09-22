import { access, mkdir, readFile, writeFile } from "node:fs/promises";
import { constants as fsConstants } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { execPath } from "node:process";
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
} from "./contracts.js";
import { AndroidCdp } from "./android/cdp.js";
import {
  freeEmulatorPort,
  freePort,
  delay,
  pngDimensions,
  run,
  spawnManaged,
  startAppium,
  type ManagedProcess,
} from "./process.js";

export const ANDROID_APP_ID = "com.stash.stashnative.sample";
export const ANDROID_ACTIVITY = `${ANDROID_APP_ID}/.MainActivity`;

type Driver = any;
type CommandRunner = typeof run;

export interface AndroidAdapterDeps {
  run?: CommandRunner;
  spawnManaged?: typeof spawnManaged;
  freePort?: typeof freePort;
  freeEmulatorPort?: typeof freeEmulatorPort;
  remote?: typeof remote;
  startAppium?: typeof startAppium;
  now?: () => Date;
  home?: string;
}

type Managed = ManagedProcess & { child?: any };
type SavedAndroidDevice = {
  owned: true;
  name: string;
  template?: string;
};

function check(ok: boolean, name: string, detail: string): Check {
  return { ok, name, detail };
}

function stableHash(value: string): string {
  return [...value]
    .reduce((hash, char) => ((hash * 33) ^ char.charCodeAt(0)) >>> 0, 5381)
    .toString(16);
}

/** Stable owned AVD profile name. The no-template form preserves the v1 legacy name. */
export function ownedAvdName(repoRoot: string, template?: string): string {
  const base = `stash-robot-${stableHash(repoRoot)}`;
  return template ? `${base}-${stableHash(template)}` : base;
}

/** Android simulator/build adapter used by stash-robot. */
export class AndroidAdapter implements DeviceAdapter {
  readonly platform = "android" as const;
  readonly webview: AndroidCdp;
  private readonly options: AdapterOptions;
  private readonly deps: Required<
    Pick<
      AndroidAdapterDeps,
      | "run"
      | "spawnManaged"
      | "freePort"
      | "freeEmulatorPort"
      | "remote"
      | "startAppium"
      | "now"
    >
  > & { home: string };
  private readonly sdkRoot: string;
  private readonly deviceStatePath: string;
  private adbPath: string;
  private emulatorPath: string;
  private avdManagerPath: string;
  private gradlePath: string;
  private javaHome?: string;
  private avdName?: string;
  private emulatorPort?: number;
  private serial?: string;
  private device?: DeviceInfo;
  private emulator?: Managed;
  private logcat?: Managed;
  private appium?: { stop(): Promise<void> };
  private appiumPort?: number;
  private driver?: Driver;
  private stopped = false;

  constructor(options: AdapterOptions, deps: AndroidAdapterDeps = {}) {
    this.options = options;
    this.deps = {
      run: deps.run || run,
      spawnManaged: deps.spawnManaged || spawnManaged,
      freePort: deps.freePort || freePort,
      freeEmulatorPort: deps.freeEmulatorPort || freeEmulatorPort,
      remote: deps.remote || remote,
      startAppium: deps.startAppium || startAppium,
      now: deps.now || (() => new Date()),
      home: deps.home || homedir(),
    };
    const sdk =
      process.env.ANDROID_HOME ||
      process.env.ANDROID_SDK_ROOT ||
      join(this.deps.home, "Library", "Android", "sdk");
    this.sdkRoot = sdk;
    this.deviceStatePath = join(options.cacheDir, "android", "device.json");
    this.adbPath = join(sdk, "platform-tools", "adb");
    this.emulatorPath = join(sdk, "emulator", "emulator");
    this.avdManagerPath = join(
      sdk,
      "cmdline-tools",
      "latest",
      "bin",
      "avdmanager",
    );
    this.gradlePath = join(options.repoRoot, "Android", "gradlew");
    this.webview = new AndroidCdp({
      serial: () => this.serial,
      runAdb: (args, signal, timeoutMs) => this.adb(args, signal, timeoutMs),
      onLog: (entry) => this.options.onLog(entry),
    });
  }

  async doctor(): Promise<DoctorReport> {
    const checks: Check[] = [];
    const exists = async (path: string) =>
      access(path, fsConstants.X_OK)
        .then(() => true)
        .catch(() => false);
    if (
      !(await exists(this.adbPath)) &&
      (await this.commandWorks("adb", ["version"]))
    )
      this.adbPath = "adb";
    const adbOk =
      (await exists(this.adbPath)) ||
      (await this.commandWorks(this.adbPath, ["version"]));
    checks.push(
      check(
        adbOk,
        "Android platform tools",
        adbOk
          ? this.adbPath
          : `adb not found; install Android SDK platform-tools under ${this.sdkRoot}`,
      ),
    );
    if (
      !(await exists(this.emulatorPath)) &&
      (await this.commandWorks("emulator", ["-version"]))
    )
      this.emulatorPath = "emulator";
    const emulatorOk =
      (await exists(this.emulatorPath)) ||
      (await this.commandWorks(this.emulatorPath, ["-version"]));
    checks.push(
      check(
        emulatorOk,
        "Android emulator",
        emulatorOk
          ? this.emulatorPath
          : "Android emulator binary not found in the configured SDK",
      ),
    );
    const java = await this.findJava17();
    checks.push(
      check(
        Boolean(java),
        "JDK 17",
        java
          ? java
          : "JDK 17 is required; set JAVA_HOME to a JDK 17 installation",
      ),
    );
    this.javaHome = java || this.javaHome;
    const avds = await this.listAvds();
    const ownedPrefix = `${ownedAvdName(this.options.repoRoot)}-`;
    checks.push(
      check(
        avds.length > 0,
        "Android system image",
        avds.length
          ? `${avds.length} installed AVD(s): ${avds.join(", ")}`
          : "No Android AVD is installed. Create a phone AVD from an installed compatible system image in Android Studio",
      ),
    );
    const avdManagerOk = await access(this.avdManagerPath, fsConstants.X_OK)
      .then(() => true)
      .catch(() => false);
    const templateOk = await this.hasUsableTemplate(avds);
    checks.push(
      check(
        avdManagerOk || templateOk,
        "Android AVD provisioning",
        avdManagerOk
          ? this.avdManagerPath
          : templateOk
            ? "avdmanager unavailable; dedicated AVDs will be cloned from the installed template"
            : "avdmanager not found and no usable AVD template was found",
      ),
    );
    const gradleOk = await access(this.gradlePath, fsConstants.X_OK)
      .then(() => true)
      .catch(() => false);
    checks.push(
      check(
        gradleOk,
        "Sample Gradle wrapper",
        gradleOk ? this.gradlePath : `Missing ${this.gradlePath}`,
      ),
    );
    const appiumOk = await this.commandWorks(execPath, [
      "-e",
      "import('appium')",
    ]);
    checks.push(
      check(
        appiumOk,
        "Appium 3.7.0",
        appiumOk
          ? "Installed in tools/stash-robot"
          : "Run npm install in tools/stash-robot",
      ),
    );
    const driverOk = await this.commandWorks(execPath, [
      "-e",
      "import('appium-uiautomator2-driver')",
    ]);
    checks.push(
      check(
        driverOk,
        "UiAutomator2 8.6.1",
        driverOk
          ? "Installed in tools/stash-robot"
          : "Install the pinned UiAutomator2 driver",
      ),
    );
    const ready = checks.every((item) => item.ok);
    const devices: DeviceChoice[] = avds
      .filter(
        (name) =>
          name !== ownedAvdName(this.options.repoRoot) &&
          !name.startsWith(ownedPrefix),
      )
      .map((name) => ({
        id: name,
        name,
        runtime: this.avdRuntime(name),
      }));
    return { platform: "android", ready, checks, devices };
  }

  async start(
    startOptions: StartOptions = {},
    signal?: AbortSignal,
  ): Promise<DeviceInfo> {
    this.stopped = false;
    try {
      if (startOptions.runtime)
        throw new Error(
          "Android runtime overrides are not supported directly; choose an installed AVD under Device template",
        );
      this.options.onProgress("Checking Android prerequisites");
      const report = await this.doctor();
      const failed = report.checks.filter((item) => !item.ok);
      if (failed.length)
        throw new Error(
          `Android is not ready: ${failed.map((item) => `${item.name}: ${item.detail}`).join("; ")}`,
        );
      this.assertNotAborted(signal);
      this.avdName = await this.ensureAvd(startOptions.device);
      this.options.onProgress(`Starting Android emulator ${this.avdName}`);
      await this.launchEmulator(this.avdName, signal);
      await this.waitForBoot(signal);
      this.serial = await this.findEmulatorSerial(signal);
      this.options.onProgress("Building Android sample");
      await this.build(signal);
      await this.installAndLaunch(signal);
      await this.startLogcat(signal);
      this.options.onProgress("Starting Android automation driver");
      await this.ensureAutomationServerPackages(signal);
      await this.startDriverWithRecovery(signal);
      const size = await this.windowSize();
      this.device = {
        platform: "android",
        id: this.serial,
        name: this.avdName,
        runtime: this.avdRuntime(this.avdName),
        appId: ANDROID_APP_ID,
      };
      this.options.onProgress(`Android ready at ${size.width}x${size.height}`);
      return this.device;
    } catch (error) {
      await this.stop().catch(() => {});
      throw error;
    }
  }

  async capture(signal?: AbortSignal): Promise<RawFrame> {
    this.assertNotAborted(signal);
    const png = await this.adb(["exec-out", "screencap", "-p"], signal, 10000);
    const dimensions = pngDimensions(png);
    const logical = await this.windowSize().catch(() => dimensions);
    return {
      png,
      width: dimensions.width,
      height: dimensions.height,
      logicalWidth: logical.width,
      logicalHeight: logical.height,
    };
  }

  async hierarchy(signal?: AbortSignal): Promise<string> {
    this.assertNotAborted(signal);
    if (this.driver) return String(await this.driver.getPageSource());
    return (
      await this.adb(
        ["exec-out", "uiautomator", "dump", "/dev/tty"],
        signal,
        10000,
      )
    ).toString();
  }

  async act(action: RobotAction, signal?: AbortSignal): Promise<void> {
    this.assertNotAborted(signal);
    const driver = this.requireDriver();
    if (action.type === "tap" || action.type === "swipe") {
      const size = await this.windowSize();
      if (action.type === "tap") {
        this.assertFraction(action.x, "x");
        this.assertFraction(action.y, "y");
        const x = this.pixel(action.x, size.width);
        const y = this.pixel(action.y, size.height);
        await this.pointer(driver, x, y, x, y, 0, signal);
      } else {
        this.assertFraction(action.fromX, "fromX");
        this.assertFraction(action.fromY, "fromY");
        this.assertFraction(action.toX, "toX");
        this.assertFraction(action.toY, "toY");
        await this.pointer(
          driver,
          this.pixel(action.fromX, size.width),
          this.pixel(action.fromY, size.height),
          this.pixel(action.toX, size.width),
          this.pixel(action.toY, size.height),
          action.durationMs ?? 350,
          signal,
        );
      }
      return;
    }
    if (action.type === "tapElement") {
      await (await this.findElement(driver, action.selector)).click();
      return;
    }
    if (action.type === "type") {
      const element = action.selector
        ? await this.findElement(driver, action.selector)
        : await driver.$("android=new UiSelector().focused(true)");
      await element.click();
      await element.setValue(action.text);
      return;
    }
    if (action.type === "back") {
      await driver.back();
      return;
    }
    if (action.type === "hideKeyboard") {
      await driver.hideKeyboard().catch(() => {});
      return;
    }
    if (action.type === "home") {
      await driver.pressKeyCode(3);
      return;
    }
    if (action.type === "rotate") {
      await driver.setOrientation(
        action.orientation === "portrait" ? "PORTRAIT" : "LANDSCAPE",
      );
      return;
    }
  }

  async restart(signal?: AbortSignal): Promise<void> {
    this.assertNotAborted(signal);
    const driver = this.requireDriver();
    await driver.terminateApp(ANDROID_APP_ID).catch(() => {});
    this.assertNotAborted(signal);
    await driver.activateApp(ANDROID_APP_ID);
    await this.startLogcat(signal);
    await this.webview.listTargets(signal).catch(() => []);
  }

  async rebuild(signal?: AbortSignal): Promise<void> {
    this.assertNotAborted(signal);
    if (!this.serial) throw new Error("Android device is not running");
    this.options.onProgress("Rebuilding Android sample");
    await this.build(signal);
    await this.installAndLaunch(signal);
    await this.startLogcat(signal);
    await this.webview.listTargets(signal).catch(() => []);
  }

  async stop(): Promise<void> {
    await this.webview.stop();
    if (this.logcat) {
      await this.logcat.stop().catch(() => {});
      this.logcat = undefined;
    }
    if (this.driver) {
      await this.driver.deleteSession().catch(() => {});
      this.driver = undefined;
    }
    if (this.appium) {
      await this.appium.stop().catch(() => {});
      this.appium = undefined;
    }
    this.appiumPort = undefined;
    const emulator: Managed | undefined = this.emulator as Managed | undefined;
    if (emulator) {
      await emulator.stop().catch(() => {});
      this.emulator = undefined;
    }
    this.serial = undefined;
    this.device = undefined;
    this.stopped = true;
  }

  async reset(startOptions: StartOptions = {}): Promise<void> {
    if (this.driver || this.emulator)
      throw new Error(
        "Stop the Android session before resetting its dedicated device",
      );
    if (startOptions.runtime)
      throw new Error(
        "Android runtime overrides are not supported directly; reset the retained harness device",
      );
    const avd = await this.retainedAvd();
    if (!avd) {
      this.options.onProgress("No retained Android harness device to reset");
      return;
    }
    if (startOptions.device && startOptions.device !== avd)
      throw new Error(
        "reset-device only accepts the retained harness-owned AVD",
      );
    const signal = undefined;
    await this.launchEmulator(avd, signal, true);
    await this.waitForBoot(signal);
    const serial = await this.findEmulatorSerial(signal);
    await this.adb(["-s", serial, "emu", "kill"], signal, 10000).catch(
      () => {},
    );
    const emulator: Managed | undefined = this.emulator as Managed | undefined;
    if (emulator) {
      await emulator.stop().catch(() => {});
      this.emulator = undefined;
    }
    this.serial = undefined;
    this.options.onProgress(`Reset Android device ${avd}`);
  }

  private async build(signal?: AbortSignal): Promise<void> {
    const env = this.javaHome
      ? { ...process.env, JAVA_HOME: this.javaHome }
      : process.env;
    await this.deps.run(this.gradlePath, [":sample:assembleDebug"], {
      cwd: join(this.options.repoRoot, "Android"),
      env,
      signal,
      timeoutMs: 15 * 60_000,
      onLine: (line) =>
        this.options.onLog(this.logEntry("build", "info", line)),
    });
  }

  private async installAndLaunch(signal?: AbortSignal): Promise<void> {
    const apk = join(
      this.options.repoRoot,
      "Android",
      "sample",
      "build",
      "outputs",
      "apk",
      "debug",
      "sample-debug.apk",
    );
    await access(apk).catch(() => {
      throw new Error(`Android build did not produce ${apk}`);
    });
    await this.adb(
      ["-s", this.requireSerial(), "install", "-r", apk],
      signal,
      120_000,
    );
    await this.adb(
      ["-s", this.requireSerial(), "shell", "am", "force-stop", ANDROID_APP_ID],
      signal,
      10_000,
    );
    await this.adb(
      [
        "-s",
        this.requireSerial(),
        "shell",
        "am",
        "start",
        "-n",
        ANDROID_ACTIVITY,
      ],
      signal,
      20_000,
    );
  }

  private async startDriver(signal?: AbortSignal): Promise<void> {
    if (this.driver) {
      await this.driver.deleteSession().catch(() => {});
      this.driver = undefined;
    }
    this.appium = await this.deps.startAppium(
      this.options,
      "uiautomator2",
      signal,
      {
        ANDROID_HOME: this.sdkRoot,
        ANDROID_SDK_ROOT: this.sdkRoot,
        JAVA_HOME: this.javaHome || process.env.JAVA_HOME || "",
      },
    );
    const port = (this.appium as { port?: number }).port;
    this.appiumPort = port;
    try {
      if (!port) throw new Error("Appium did not return a listening port");
      const systemPort = await this.deps.freePort();
      this.driver = await this.deps.remote({
        hostname: "127.0.0.1",
        port,
        path: "/",
        logLevel: "silent",
        capabilities: {
          platformName: "Android",
          "appium:automationName": "UiAutomator2",
          "appium:udid": this.requireSerial(),
          "appium:deviceName": this.avdName,
          "appium:appPackage": ANDROID_APP_ID,
          "appium:appActivity": ".MainActivity",
          "appium:noReset": true,
          "appium:fullReset": false,
          "appium:newCommandTimeout": 300,
          // A freshly erased emulator may still be optimizing packages after
          // boot-complete. The driver's 30s launch/install defaults are too
          // short for that first UiAutomator2 instrumentation startup.
          "appium:uiautomator2ServerLaunchTimeout": 120_000,
          "appium:uiautomator2ServerInstallTimeout": 120_000,
          "appium:adbExecTimeout": 120_000,
          "appium:skipServerInstallation": true,
          "appium:systemPort": systemPort,
          "appium:autoWebview": false,
        },
        connectionRetryCount: 0,
        connectionRetryTimeout: 180_000,
      });
      await this.driver.getWindowSize();
    } catch (error) {
      await this.captureAutomationFailureLogs();
      await this.appium.stop().catch(() => {});
      this.appium = undefined;
      throw error;
    }
  }

  private async ensureAutomationServerPackages(
    signal?: AbortSignal,
  ): Promise<void> {
    const packages = [
      {
        id: "io.appium.uiautomator2.server",
        apk: join(
          this.options.repoRoot,
          "tools",
          "stash-robot",
          "node_modules",
          "appium-uiautomator2-driver",
          "node_modules",
          "appium-uiautomator2-server",
          "apks",
          "appium-uiautomator2-server-v10.6.4.apk",
        ),
      },
      {
        id: "io.appium.uiautomator2.server.test",
        apk: join(
          this.options.repoRoot,
          "tools",
          "stash-robot",
          "node_modules",
          "appium-uiautomator2-driver",
          "node_modules",
          "appium-uiautomator2-server",
          "apks",
          "appium-uiautomator2-server-debug-androidTest.apk",
        ),
      },
    ];
    const installed = await Promise.all(
      packages.map(async ({ id }) => {
        const output = await this.adb(
          ["shell", "pm", "path", id],
          signal,
          10_000,
        ).catch(() => Buffer.from(""));
        return output.toString().includes(`package:`);
      }),
    );
    if (installed.every(Boolean)) return;
    this.options.onProgress(
      "Installing UiAutomator2 server packages sequentially",
    );
    for (const { id } of packages)
      await this.adb(["uninstall", id], signal, 20_000).catch(() => {});
    for (const { id, apk } of packages) {
      await access(apk).catch(() => {
        throw new Error(`Pinned UiAutomator2 server APK is missing: ${apk}`);
      });
      await this.adb(
        ["install", "-r", "--no-incremental", apk],
        signal,
        120_000,
      );
      const output = await this.adb(
        ["shell", "pm", "path", id],
        signal,
        15_000,
      );
      if (!output.toString().includes("package:"))
        throw new Error(`Android did not register ${id} after installation`);
    }
  }

  private async startDriverWithRecovery(signal?: AbortSignal): Promise<void> {
    try {
      await this.startDriver(signal);
    } catch (error) {
      if (
        signal?.aborted ||
        !/instrumentation process cannot be initialized/i.test(
          error instanceof Error ? error.message : String(error),
        )
      )
        throw error;
      // Directly after an AVD erase Android's package manager can expose the
      // UiAutomator2 test APK before its target server APK. The pinned driver
      // notices the missing target but continues to instrumentation, whose own
      // retry cannot repair that package pair. A fresh Appium session performs
      // its package consistency check again and reinstalls both components.
      this.options.onProgress(
        "UiAutomator2 server packages were incomplete; retrying automation setup once",
      );
      await delay(1_500, signal);
      await this.startDriver(signal);
    }
  }

  private async captureAutomationFailureLogs(): Promise<void> {
    if (!this.serial) return;
    const output = await this.adb(
      ["logcat", "-d", "-t", "800"],
      undefined,
      15_000,
    ).catch((error) => {
      this.options.onLog(
        this.logEntry(
          "driver",
          "warn",
          `Unable to collect UiAutomator2 failure logcat: ${error instanceof Error ? error.message : String(error)}`,
        ),
      );
      return undefined;
    });
    if (!output) return;
    for (const line of output.toString().split(/\r?\n/).filter(Boolean))
      this.options.onLog(
        this.logEntry("native", this.logLevel(line), line, {
          serial: this.serial,
          reason: "UiAutomator2 startup failure",
        }),
      );
  }

  private async launchEmulator(
    avd: string,
    signal?: AbortSignal,
    wipe = false,
  ): Promise<void> {
    this.emulatorPort = await this.deps.freeEmulatorPort();
    this.avdName = avd;
    const args = [
      "-avd",
      avd,
      "-port",
      String(this.emulatorPort),
      "-no-window",
      "-no-audio",
      "-no-snapshot",
      "-gpu",
      "swangle",
      "-no-boot-anim",
      "-no-metrics",
    ];
    if (wipe) args.push("-wipe-data");
    this.emulator = this.deps.spawnManaged(this.emulatorPath, args, {
      cwd: this.sdkRoot,
      env: process.env,
      onLine: (line) =>
        this.options.onLog(this.logEntry("native", "info", line)),
    }) as Managed;
    if (signal?.aborted) {
      await this.emulator.stop();
      throw new Error("Operation aborted");
    }
  }

  private async waitForBoot(signal?: AbortSignal): Promise<void> {
    const deadline = Date.now() + 180_000;
    let serial: string | undefined;
    while (Date.now() < deadline) {
      this.assertNotAborted(signal);
      if (
        this.emulator?.child.exitCode !== null &&
        this.emulator?.child.exitCode !== undefined
      )
        throw new Error(
          "Owned Android emulator exited during boot; inspect native logs",
        );
      serial ||= await this.findEmulatorSerial(signal).catch(() => undefined);
      if (serial) {
        const boot = await this.adb(
          ["-s", serial, "shell", "getprop", "sys.boot_completed"],
          signal,
          5000,
        ).catch(() => Buffer.from(""));
        if (boot.toString().trim() === "1") {
          const name = (
            await this.adb(["-s", serial, "emu", "avd", "name"], signal, 5000)
          )
            .toString()
            .split(/\r?\n/)[0]
            ?.trim();
          if (name !== this.avdName)
            throw new Error(
              `Emulator identity changed: expected ${this.avdName}, found ${name}. No app operation was dispatched.`,
            );
          this.serial = serial;
          return;
        }
      }
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
    throw new Error(
      "Android emulator did not finish booting within 180 seconds",
    );
  }

  private async findEmulatorSerial(signal?: AbortSignal): Promise<string> {
    const output = await this.deps.run(this.adbPath, ["devices"], {
      signal,
      timeoutMs: 5000,
    });
    const expected = this.emulatorPort
      ? `emulator-${this.emulatorPort}`
      : undefined;
    const serial = output.stdout
      .toString()
      .split(/\r?\n/)
      .slice(1)
      .map((line) => line.trim().split(/\s+/))
      .find((parts) => parts[0] === expected && parts[1] === "device")?.[0];
    if (!serial) throw new Error("No booted Android emulator was found");
    return serial;
  }

  private async startLogcat(signal?: AbortSignal): Promise<void> {
    if (!this.serial) return;
    if (this.logcat) {
      await this.logcat.stop().catch(() => {});
      this.logcat = undefined;
    }
    const serial = this.serial;
    const pid = (
      await this.adb(["shell", "pidof", ANDROID_APP_ID], signal, 5000).catch(
        () => Buffer.from(""),
      )
    )
      .toString()
      .trim()
      .split(/\s+/)[0];
    const pidArgs = pid ? [`--pid=${pid}`] : [];
    const filters = pid
      ? ["*:V"]
      : ["StashNativeDemo:V", "StashNativeCard:V", "AndroidRuntime:E", "*:S"];
    this.logcat = this.deps.spawnManaged(
      this.adbPath,
      ["-s", serial, "logcat", "-v", "threadtime", ...pidArgs, ...filters],
      {
        cwd: this.options.repoRoot,
        env: process.env,
        onLine: (line) =>
          this.options.onLog(
            this.logEntry("native", this.logLevel(line), line, { serial }),
          ),
      },
    ) as Managed;
  }

  private async ensureAvd(requested?: string): Promise<string> {
    const avds = await this.listAvds();
    const legacy = ownedAvdName(this.options.repoRoot);
    const retained = await this.readDeviceState();
    if (!requested && retained && avds.includes(retained.name))
      return retained.name;
    const dedicated = requested
      ? ownedAvdName(this.options.repoRoot, requested)
      : legacy;
    if (avds.includes(dedicated)) {
      await this.saveDeviceState({
        owned: true,
        name: dedicated,
        ...(requested ? { template: requested } : {}),
      });
      return dedicated;
    }
    const source =
      requested ||
      avds.find(
        (name) => !this.isOwnedAvd(name) && /phone|medium|pixel/i.test(name),
      ) ||
      avds.find((name) => !this.isOwnedAvd(name));
    if (!source)
      throw new Error(
        "No Android AVD is available; install a compatible phone image first",
      );
    if (!avds.includes(source))
      throw new Error(
        `Requested Android AVD template ${source} is not installed`,
      );
    const configPath = join(
      this.deps.home,
      ".android",
      "avd",
      `${source}.avd`,
      "config.ini",
    );
    const config = await readFile(configPath, "utf8").catch(() => "");
    const image = config.match(/^image.sysdir.1=(.+)$/m)?.[1]?.trim();
    if (!image)
      throw new Error(
        `Cannot determine the system image for AVD ${source}; recreate it with Android Studio`,
      );
    const dedicatedDir = join(
      this.deps.home,
      ".android",
      "avd",
      `${dedicated}.avd`,
    );
    const sourceConfig = config;
    const env = this.javaHome
      ? { ...process.env, JAVA_HOME: this.javaHome }
      : process.env;
    const avdManagerOk = await access(this.avdManagerPath, fsConstants.X_OK)
      .then(() => true)
      .catch(() => false);
    if (avdManagerOk) {
      const sdkImage = image.replace(/\/$/, "").replaceAll("/", ";");
      const deviceProfile = config
        .match(/^hw\.device\.name=(.+)$/m)?.[1]
        ?.trim();
      const createArgs = [
        "create",
        "avd",
        "-n",
        dedicated,
        "-k",
        sdkImage,
        "--force",
        ...(deviceProfile ? ["--device", deviceProfile] : []),
      ];
      await this.deps
        .run(this.avdManagerPath, createArgs, {
          env,
          input: "no\n",
          timeoutMs: 60_000,
        })
        .catch((error) => {
          throw new Error(
            `Unable to create dedicated AVD ${dedicated}: ${error instanceof Error ? error.message : String(error)}`,
          );
        });
    } else {
      await this.cloneAvdTemplate(
        source,
        dedicated,
        sourceConfig,
        dedicatedDir,
      );
    }
    await this.saveDeviceState({
      owned: true,
      name: dedicated,
      template: source,
    });
    return dedicated;
  }

  private isOwnedAvd(name: string): boolean {
    const base = ownedAvdName(this.options.repoRoot);
    return name === base || name.startsWith(`${base}-`);
  }

  private async readDeviceState(): Promise<SavedAndroidDevice | undefined> {
    try {
      const value = JSON.parse(
        await readFile(this.deviceStatePath, "utf8"),
      ) as Partial<SavedAndroidDevice>;
      if (
        value.owned === true &&
        typeof value.name === "string" &&
        this.isOwnedAvd(value.name)
      )
        return value as SavedAndroidDevice;
    } catch {
      /* The legacy default remains discoverable without a state record. */
    }
    return undefined;
  }

  private async saveDeviceState(value: SavedAndroidDevice): Promise<void> {
    await mkdir(dirname(this.deviceStatePath), { recursive: true });
    await writeFile(
      this.deviceStatePath,
      `${JSON.stringify(value, null, 2)}\n`,
      { mode: 0o600 },
    );
  }

  private async retainedAvd(): Promise<string | undefined> {
    const avds = await this.listAvds();
    const retained = await this.readDeviceState();
    if (retained && avds.includes(retained.name)) return retained.name;
    const legacy = ownedAvdName(this.options.repoRoot);
    return avds.includes(legacy) ? legacy : undefined;
  }

  private async hasUsableTemplate(avds: string[]): Promise<boolean> {
    for (const avd of avds) {
      const config = await readFile(
        join(this.deps.home, ".android", "avd", `${avd}.avd`, "config.ini"),
        "utf8",
      ).catch(() => "");
      if (/^image\.sysdir\.1=.+$/m.test(config)) return true;
    }
    return false;
  }

  private async cloneAvdTemplate(
    source: string,
    dedicated: string,
    sourceConfig: string,
    dedicatedDir: string,
  ): Promise<void> {
    await mkdir(dedicatedDir, { recursive: true });
    const lines = sourceConfig
      .split(/\r?\n/)
      .filter(
        (line) =>
          !/^(AvdId|avd\.ini\.displayname|path|path\.rel|snapshot\.|userdata\.|sdcard\.path)/.test(
            line,
          ),
      );
    lines.push(`AvdId=${dedicated}`, `avd.ini.displayname=${dedicated}`);
    await writeFile(
      join(dedicatedDir, "config.ini"),
      `${lines.filter(Boolean).join("\n")}\n`,
    );
    const sourceIni = await readFile(
      join(this.deps.home, ".android", "avd", `${source}.ini`),
      "utf8",
    ).catch(() => "");
    const target =
      sourceIni.match(/^target=(.+)$/m)?.[1] ||
      sourceConfig.match(/^target=(.+)$/m)?.[1] ||
      "android-35";
    await writeFile(
      join(this.deps.home, ".android", "avd", `${dedicated}.ini`),
      `avd.ini.encoding=UTF-8\npath=${dedicatedDir}\npath.rel=avd/${dedicated}.avd\ntarget=${target}\n`,
    );
  }

  private async listAvds(): Promise<string[]> {
    const output = await this.deps
      .run(this.emulatorPath, ["-list-avds"], { timeoutMs: 5000 })
      .catch(() => undefined);
    return (
      output?.stdout
        .toString()
        .split(/\r?\n/)
        .map((item) => item.trim())
        .filter(Boolean) || []
    );
  }

  private avdRuntime(name?: string): string {
    return name ? `Android (${name})` : "Android";
  }

  private async findJava17(): Promise<string | undefined> {
    const candidates = [
      process.env.JAVA_HOME,
      "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home",
      "/usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home",
    ];
    for (const candidate of candidates) {
      if (!candidate) continue;
      const version = await this.deps
        .run(join(candidate, "bin", "java"), ["-version"], { timeoutMs: 5000 })
        .catch(() => undefined);
      if (
        version &&
        /version\s+"17(?:\.|\")/.test(`${version.stdout}\n${version.stderr}`)
      )
        return candidate;
    }
    return undefined;
  }

  private async commandWorks(
    command: string,
    args: string[],
  ): Promise<boolean> {
    return this.deps
      .run(command, args, { timeoutMs: 5000 })
      .then(() => true)
      .catch(() => false);
  }

  private async adb(
    args: string[],
    signal?: AbortSignal,
    timeoutMs = 30_000,
  ): Promise<Buffer> {
    const scoped =
      args[0] === "devices" ||
      args[0] === "version" ||
      args[0] === "start-server" ||
      args[0] === "kill-server"
        ? args
        : args[0] === "-s"
          ? args
          : ["-s", this.requireSerial(), ...args];
    const result = await this.deps.run(this.adbPath, scoped, {
      cwd: this.options.repoRoot,
      env: process.env,
      signal,
      timeoutMs,
    });
    return result.stdout;
  }

  private requireSerial(): string {
    if (!this.serial) throw new Error("Android emulator is not running");
    return this.serial;
  }
  private requireDriver(): Driver {
    if (!this.driver)
      throw new Error("Android automation driver is not connected");
    return this.driver;
  }
  private assertNotAborted(signal?: AbortSignal): void {
    if (signal?.aborted) throw new Error("Operation aborted");
  }
  private assertFraction(value: number, name: string): void {
    if (!Number.isFinite(value) || value < 0 || value > 1)
      throw new Error(`${name} must be between 0 and 1`);
  }
  private pixel(fraction: number, dimension: number): number {
    return Math.min(
      dimension - 1,
      Math.max(0, Math.round(fraction * dimension)),
    );
  }
  private async windowSize(): Promise<{ width: number; height: number }> {
    return (
      this.driver?.getWindowSize() ||
      Promise.resolve({ width: 1080, height: 1920 })
    );
  }
  private async findElement(driver: Driver, selector: string): Promise<any> {
    if (selector.startsWith("//") || selector.startsWith("(//"))
      return driver.$(`xpath=${selector}`);
    if (selector.startsWith("~") || selector.startsWith("android="))
      return driver.$(selector);
    return driver.$(`~${selector}`);
  }
  private async pointer(
    driver: Driver,
    fromX: number,
    fromY: number,
    toX: number,
    toY: number,
    duration: number,
    signal?: AbortSignal,
  ): Promise<void> {
    this.assertNotAborted(signal);
    await driver.performActions([
      {
        type: "pointer",
        id: "stash-robot-finger",
        parameters: { pointerType: "touch" },
        actions: [
          { type: "pointerMove", duration: 0, x: fromX, y: fromY },
          { type: "pointerDown", button: 0 },
          { type: "pointerMove", duration, x: toX, y: toY },
          { type: "pointerUp", button: 0 },
        ],
      },
    ]);
    await driver.releaseActions().catch(() => {});
  }
  private async waitForHttp(
    url: string,
    signal?: AbortSignal,
    timeoutMs = 30_000,
  ): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      this.assertNotAborted(signal);
      try {
        if ((await fetch(url, { signal })).ok) return;
      } catch {
        /* appium is still starting */
      }
      await new Promise((resolve) => setTimeout(resolve, 200));
    }
    throw new Error(`Timed out waiting for ${url}`);
  }
  private logEntry(
    source: any,
    level: string,
    message: string,
    details?: unknown,
  ) {
    return {
      timestamp: this.deps.now().toISOString(),
      source,
      level,
      message,
      details,
    };
  }
  private logLevel(line: string): string {
    return /\sE\//.test(line) || /\berror\b/i.test(line)
      ? "error"
      : /\sW\//.test(line)
        ? "warn"
        : "info";
  }
}

export function createAndroidAdapter(
  options: AdapterOptions,
  deps?: AndroidAdapterDeps,
): DeviceAdapter {
  return new AndroidAdapter(options, deps);
}
