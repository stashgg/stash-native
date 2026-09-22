import assert from "node:assert/strict";
import test from "node:test";

import {
  MIN_RUNTIME,
  chooseRuntime,
  coordinate,
  evaluationValue,
  inspectorProcessBundleId,
  isTransientSimulatorInstallError,
  isOwnedDeviceName,
  ownedDeviceName,
  parseDevices,
  parseRuntimes,
  versionNumber,
} from "../src/ios/helpers.js";

test("iOS runtime and device parsers retain runtime relationships", () => {
  const runtimes = parseRuntimes(
    `== Runtimes ==\n iOS 16.0 (16.0 - 20A360) - com.apple.CoreSimulator.SimRuntime.iOS-16-0\n iOS 18.6 (18.6 - 22G86) - com.apple.CoreSimulator.SimRuntime.iOS-18-6`,
  );
  assert.deepEqual(
    runtimes.map((item) => item.version),
    ["16.0", "18.6"],
  );
  const devices = parseDevices(
    `-- com.apple.CoreSimulator.SimRuntime.iOS-18-6 --\n    iPhone 17 (ABCDEFAB-1234-5678-9ABC-DEF012345678) (Shutdown)\n-- com.apple.CoreSimulator.SimRuntime.iOS-16-0 --\n    iPhone 14 (12345678-1234-1234-1234-123456789012) (Unavailable, runtime profile not found)`,
    runtimes,
  );
  assert.equal(devices[0]?.runtime, "18.6");
  assert.equal(devices[0]?.state, "Shutdown");
  assert.equal(devices[1]?.runtime, "16.0");
});

test("runtime selection rejects old runtimes and prefers latest compatible one", () => {
  const runtimes = parseRuntimes(
    "iOS 16.0 (16.0) - com.apple.CoreSimulator.SimRuntime.iOS-16-0\niOS 18.6 (18.6) - com.apple.CoreSimulator.SimRuntime.iOS-18-6\niOS 26.5 (26.5) - com.apple.CoreSimulator.SimRuntime.iOS-26-5",
  );
  assert.equal(chooseRuntime(runtimes)?.version, "26.5");
  assert.equal(chooseRuntime(runtimes, "16.0"), undefined);
  assert.ok(versionNumber("18.6") >= MIN_RUNTIME);
});

test("normalized coordinates are clamped to logical screen bounds", () => {
  assert.equal(coordinate(0, 390), 0);
  assert.equal(coordinate(0.5, 390), 195);
  assert.equal(coordinate(2, 390), 389);
  assert.throws(() => coordinate(Number.NaN, 390), /Invalid device coordinate/);
});

test("owned simulator name is stable per repository and scoped by hash", () => {
  assert.equal(ownedDeviceName("/repo/a"), ownedDeviceName("/repo/a"));
  assert.notEqual(ownedDeviceName("/repo/a"), ownedDeviceName("/repo/b"));
  assert.match(ownedDeviceName("/repo/a"), /^Stash Robot iPhone [0-9a-f]{8}$/);
  assert.equal(
    ownedDeviceName("/repo/a", " iPhone   16e "),
    `${ownedDeviceName("/repo/a")} (iPhone 16e)`,
  );
  assert.equal(isOwnedDeviceName("/repo/a", ownedDeviceName("/repo/a")), true);
  assert.equal(
    isOwnedDeviceName("/repo/a", ownedDeviceName("/repo/a", "iPhone 16e")),
    true,
  );
  assert.equal(isOwnedDeviceName("/repo/a", ownedDeviceName("/repo/b")), false);
});

test("iOS Web Inspector matches the simulator host process alias", () => {
  assert.equal(
    inspectorProcessBundleId("StashNativeSample"),
    "process-StashNativeSample",
  );
  assert.throws(() => inspectorProcessBundleId(""), /executable name/);
});

test("WebView evaluation preserves the application value envelope", () => {
  assert.equal(
    evaluationValue({ ok: true, value: "stash-robot smoke" }),
    "stash-robot smoke",
  );
  assert.deepEqual(evaluationValue({ ok: true, value: { value: 42 } }), {
    value: 42,
  });
  assert.throws(
    () => evaluationValue({ ok: false, error: "broken expression" }),
    /broken expression/,
  );
});

test("simulator install retry only recognizes the IX metadata readiness race", () => {
  assert.equal(
    isTransientSimulatorInstallError(
      "IXErrorDomain Code=2: Failed to set metadata: Failed to create promise",
    ),
    true,
  );
  assert.equal(
    isTransientSimulatorInstallError("IXErrorDomain Code=2: disk is full"),
    false,
  );
  assert.equal(
    isTransientSimulatorInstallError(
      "Connection refused: Failed to set metadata",
    ),
    false,
  );
});
