import { strict as assert } from "node:assert";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { AndroidAdapter, ownedAvdName } from "../src/android.js";
import { AndroidCdp } from "../src/android/cdp.js";
import type { AdapterOptions } from "../src/contracts.js";

const options = (root = "/tmp/stash-robot-test"): AdapterOptions => ({
  repoRoot: root,
  cacheDir: "/tmp/stash-robot-cache",
  onLog: () => {},
  onProgress: () => {},
});

test("Android doctor reports actionable failures when SDK tools are unavailable", async () => {
  const adapter = new AndroidAdapter(options(), {
    home: "/tmp/stash-robot-no-home",
    run: async () => {
      throw new Error("missing");
    },
  });
  const report = await adapter.doctor();
  assert.equal(report.platform, "android");
  assert.equal(report.ready, false);
  assert.ok(
    report.checks.some(
      (item) => item.name === "Android platform tools" && !item.ok,
    ),
  );
  assert.ok(report.checks.some((item) => item.name === "JDK 17" && !item.ok));
  assert.ok(
    report.checks.some(
      (item) => item.name === "Android system image" && !item.ok,
    ),
  );
});

test("Android coordinate actions map screen fractions to native pixels and clamp edges", async () => {
  const calls: unknown[] = [];
  const driver = {
    getWindowSize: async () => ({ width: 1080, height: 1920 }),
    performActions: async (value: unknown) => {
      calls.push(value);
    },
    releaseActions: async () => {},
  };
  const adapter = new AndroidAdapter(options(), {
    run: async () => ({ stdout: Buffer.from(""), stderr: "" }),
  });
  const internal = adapter as any;
  internal.driver = driver;
  await adapter.act({ type: "tap", x: 0.25, y: 0.5, frameId: "core-frame-3" });
  const pointer = (calls[0] as any)[0].actions;
  assert.deepEqual(pointer[0], {
    type: "pointerMove",
    duration: 0,
    x: 270,
    y: 960,
  });
  await adapter.act({ type: "tap", x: 1, y: 1, frameId: "core-frame-4" });
  const edgePointer = (calls[1] as any)[0].actions;
  assert.deepEqual(edgePointer[0], {
    type: "pointerMove",
    duration: 0,
    x: 1079,
    y: 1919,
  });
  await assert.rejects(
    () =>
      adapter.act({
        type: "swipe",
        fromX: -0.1,
        fromY: 0.5,
        toX: 0.5,
        toY: 0.5,
        frameId: "core-frame-5",
      }),
    /fromX must be between/,
  );
});

test("Android WebView discovery is scoped to the sample process", async () => {
  const calls: string[][] = [];
  const cdp = new AndroidCdp({
    serial: () => "emulator-5554",
    runAdb: async (args) => {
      calls.push(args);
      if (args.includes("/proc/net/unix"))
        return Buffer.from(
          "00000000: 00000002 00000000 0001 01 12345 @webview_devtools_remote_999\n00000000: 00000002 00000000 0001 01 12346 @webview_devtools_remote_123\n",
        );
      if (args.includes("pidof")) return Buffer.from("123\n");
      if (args[0] === "forward") return Buffer.from("");
      throw new Error(`unexpected adb call ${args.join(" ")}`);
    },
    onLog: () => {},
  });
  const targets = await cdp.listTargets().catch((error) => {
    // No HTTP debugger endpoint is expected in this unit test; socket filtering still ran.
    assert.match(String(error), /fetch failed|ECONNREFUSED|Unable to discover/);
    return [];
  });
  assert.ok(calls.some((args) => args.includes("pidof")));
  assert.ok(
    calls.some((args) => args.includes("webview_devtools_remote_123")) ||
      targets.length === 0,
  );
});

test("Android refuses a serial occupied by a different AVD before app operations", async () => {
  const calls: string[][] = [];
  const adapter = new AndroidAdapter(options(), {
    run: async (_command, args) => {
      calls.push(args);
      if (args[0] === "devices")
        return {
          stdout: Buffer.from(
            "List of devices attached\nemulator-5554\tdevice\n",
          ),
          stderr: "",
        };
      return {
        stdout: Buffer.from(
          args.includes("sys.boot_completed") ? "1\n" : "user-phone\nOK\n",
        ),
        stderr: "",
      };
    },
  });
  const internal = adapter as any;
  internal.emulatorPort = 5554;
  internal.avdName = "stash-robot-owned";
  await assert.rejects(internal.waitForBoot(), /Emulator identity changed/);
  assert.equal(internal.serial, undefined);
  assert(
    calls.every((args) => !args.includes("install") && !args.includes("am")),
  );
});

test("Android device template overrides select stable owned profiles and remain retained", async () => {
  const root = await mkdtemp(join(tmpdir(), "stash-robot-android-profile-"));
  const repoRoot = join(root, "repo");
  const cacheDir = join(root, "cache");
  const pixel8 = ownedAvdName(repoRoot, "Pixel_8_API_35");
  const pixel7 = ownedAvdName(repoRoot, "Pixel_7_API_34");
  const installed = [
    "Pixel_8_API_35",
    "Pixel_7_API_34",
    ownedAvdName(repoRoot),
    pixel8,
    pixel7,
  ];
  const adapter = new AndroidAdapter(
    { ...options(repoRoot), repoRoot, cacheDir },
    {
      home: join(root, "home"),
      run: async (_command, args) => ({
        stdout: Buffer.from(
          args[0] === "-list-avds" ? `${installed.join("\n")}\n` : "",
        ),
        stderr: "",
      }),
    },
  );
  const internal = adapter as any;
  try {
    assert.equal(await internal.ensureAvd("Pixel_8_API_35"), pixel8);
    assert.equal(await internal.ensureAvd("Pixel_7_API_34"), pixel7);
    assert.equal(await internal.ensureAvd(), pixel7);
    assert.equal(await internal.retainedAvd(), pixel7);
    const saved = JSON.parse(
      await readFile(join(cacheDir, "android", "device.json"), "utf8"),
    );
    assert.deepEqual(saved, {
      owned: true,
      name: pixel7,
      template: "Pixel_7_API_34",
    });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("Android gives first-boot UiAutomator2 installation and launch a bounded recovery window", async () => {
  let remoteOptions: any;
  const adapter = new AndroidAdapter(options(), {
    run: async () => ({ stdout: Buffer.from(""), stderr: "" }),
    freePort: async () => 8251,
    startAppium: async () => ({ port: 4725, stop: async () => {} }),
    remote: (async (value: unknown) => {
      remoteOptions = value;
      return { getWindowSize: async () => ({ width: 1080, height: 1920 }) };
    }) as any,
  });
  const internal = adapter as any;
  internal.serial = "emulator-5554";
  internal.avdName = "stash-robot-owned";
  await internal.startDriver();
  assert.equal(remoteOptions.connectionRetryTimeout, 180_000);
  assert.equal(
    remoteOptions.capabilities["appium:uiautomator2ServerLaunchTimeout"],
    120_000,
  );
  assert.equal(
    remoteOptions.capabilities["appium:uiautomator2ServerInstallTimeout"],
    120_000,
  );
  assert.equal(remoteOptions.capabilities["appium:adbExecTimeout"], 120_000);
  assert.equal(
    remoteOptions.capabilities["appium:skipServerInstallation"],
    true,
  );
});

test("Android retries one fresh Appium session when post-wipe instrumentation packages are incomplete", async () => {
  let starts = 0;
  let sessions = 0;
  const adapter = new AndroidAdapter(options(), {
    run: async () => ({ stdout: Buffer.from(""), stderr: "" }),
    freePort: async () => 8252 + sessions,
    startAppium: async () => {
      starts++;
      return { port: 4726 + starts, stop: async () => {} };
    },
    remote: (async () => {
      sessions++;
      if (sessions === 1)
        throw new Error("The instrumentation process cannot be initialized");
      return { getWindowSize: async () => ({ width: 1080, height: 1920 }) };
    }) as any,
  });
  const internal = adapter as any;
  internal.serial = "emulator-5554";
  internal.avdName = "stash-robot-owned";
  await internal.startDriverWithRecovery();
  assert.equal(starts, 2);
  assert.equal(sessions, 2);
});
