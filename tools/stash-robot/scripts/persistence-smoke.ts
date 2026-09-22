import assert from "node:assert/strict";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createAndroidAdapter } from "../src/android.js";
import { createIosAdapter } from "../src/ios.js";
import { run } from "../src/process.js";
import type { DeviceAdapter, DeviceInfo, LogEntry } from "../src/contracts.js";

const platform = process.argv[2];
if (platform !== "android" && platform !== "ios")
  throw new Error(
    "Usage: node --import tsx scripts/persistence-smoke.ts android|ios",
  );
const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const artifactDir = join(
  repoRoot,
  "build/stash-robot/acceptance",
  `persistence-${platform}`,
);
const logs: LogEntry[] = [];
const options = {
  repoRoot,
  cacheDir: join(repoRoot, "build/stash-robot/cache"),
  onLog(entry: LogEntry) {
    logs.push(entry);
    if (logs.length > 30000) logs.shift();
  },
  onProgress(message: string) {
    if (/Starting|ready|Installing|Reset/.test(message)) console.log(message);
  },
};
const create = () =>
  (platform === "android" ? createAndroidAdapter : createIosAdapter)(options);
const adb = join(
  process.env.ANDROID_HOME ||
    process.env.ANDROID_SDK_ROOT ||
    join(homedir(), "Library/Android/sdk"),
  "platform-tools/adb",
);
const marker = "stash-robot-persistence-probe";
let active: DeviceAdapter | undefined;

async function dataPath(device: DeviceInfo): Promise<string> {
  const result = await run("xcrun", [
    "simctl",
    "get_app_container",
    device.id,
    device.appId,
    "data",
  ]);
  return join(result.stdout.toString().trim(), "Documents", marker);
}
async function writeMarker(device: DeviceInfo): Promise<void> {
  if (platform === "ios") {
    const path = await dataPath(device);
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, marker);
  } else {
    await run(adb, [
      "-s",
      device.id,
      "shell",
      "run-as",
      device.appId,
      "mkdir",
      "-p",
      "files",
    ]);
    await run(adb, [
      "-s",
      device.id,
      "shell",
      "run-as",
      device.appId,
      "sh",
      "-c",
      "'printf stash-robot-persistence-probe > files/stash-robot-persistence-probe'",
    ]);
  }
}
async function readMarker(device: DeviceInfo): Promise<string | undefined> {
  try {
    return platform === "ios"
      ? await readFile(await dataPath(device), "utf8")
      : (
          await run(adb, [
            "-s",
            device.id,
            "shell",
            "-T",
            "run-as",
            device.appId,
            "cat",
            `files/${marker}`,
          ])
        ).stdout.toString();
  } catch {
    return undefined;
  }
}

try {
  active = create();
  const original = await active.start({});
  await writeMarker(original);
  assert.equal(
    await readMarker(original),
    marker,
    "Probe was written before ending the first session",
  );
  await active.stop();
  active = create();
  const retained = await active.start({});
  assert.equal(
    platform === "ios" ? retained.id : retained.name,
    platform === "ios" ? original.id : original.name,
    "A new session reuses the dedicated device",
  );
  assert.equal(
    await readMarker(retained),
    marker,
    "App data survives shutdown, rebuild, and reinstall",
  );
  await active.stop();
  active = create();
  await active.reset();
  const reset = await active.start({});
  assert.equal(
    await readMarker(reset),
    undefined,
    "Explicit reset erases only the dedicated device data",
  );
  await mkdir(artifactDir, { recursive: true });
  const report = {
    platform,
    retainedAppData: true,
    explicitResetClearedData: true,
    completedAt: new Date().toISOString(),
  };
  await writeFile(
    join(artifactDir, "report.json"),
    JSON.stringify(report, null, 2),
  );
  console.log("PASS", report);
} finally {
  await active?.stop();
  await mkdir(artifactDir, { recursive: true });
  await writeFile(
    join(artifactDir, "logs.json"),
    JSON.stringify(logs, null, 2),
  );
}
