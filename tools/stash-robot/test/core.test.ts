import test from "node:test";
import assert from "node:assert/strict";
import { access } from "node:fs/promises";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createFakeAdapter } from "../src/fake.js";
import { RobotSession } from "../src/session.js";
import type { DeviceAdapter } from "../src/contracts.js";
import { CodexBridge } from "../src/codex.js";

test("session preserves coordinate frames across previews and rejects frames after actions", async () => {
  const cacheDir = await mkdtemp(join(tmpdir(), "stash-robot-core-"));
  const session = new RobotSession({
    repoRoot: process.cwd(),
    cacheDir,
    enableAgent: false,
    createAdapter: (platform, hooks) =>
      createFakeAdapter(
        { repoRoot: process.cwd(), cacheDir, ...hooks },
        platform,
      ),
  });
  await session.doctor(["android"]);
  await session.start("android");
  await session.takeControl();
  const first = (await session.observe("manual")).observation;
  await session.observe("system");
  const after = await session.act(
    { type: "tap", x: 0.5, y: 0.4, frameId: first.frameId },
    "manual",
  );
  assert.notEqual(after.observation.frameId, first.frameId);
  await assert.rejects(
    session.act(
      { type: "tap", x: 0.5, y: 0.4, frameId: first.frameId },
      "manual",
    ),
    /stale/,
  );
  await session.end();
});

test("WebView tools include actual screenshots and temporary CSS before/after evidence", async () => {
  const cacheDir = await mkdtemp(join(tmpdir(), "stash-robot-tools-"));
  const session = new RobotSession({
    repoRoot: process.cwd(),
    cacheDir,
    enableAgent: false,
    createAdapter: (platform, hooks) =>
      createFakeAdapter(
        { repoRoot: process.cwd(), cacheDir, ...hooks },
        platform,
      ),
  });
  await session.start("android");
  await session.takeControl();
  const frame = (await session.observe("manual")).observation;
  await session.act(
    { type: "tap", x: 0.5, y: 0.5, frameId: frame.frameId },
    "manual",
  );
  const css = await session.webview(
    { operation: "setCss", css: "body{color:red}" },
    "manual",
  );
  assert(css.before);
  assert.equal(session.snapshot().activeCss, "body{color:red}");
  assert.notEqual(css.before?.frameId, css.after.observation.frameId);
  await session.webview({ operation: "resetCss" }, "manual");
  assert.equal(session.snapshot().activeCss, "");
  const imagePath = css.after.observation.imagePath;
  await access(imagePath);
  await session.end();
  await assert.rejects(access(imagePath));
});

test("robot tool observations return structured context plus real PNG image content", async () => {
  const cacheDir = await mkdtemp(join(tmpdir(), "stash-robot-image-"));
  const session = new RobotSession({
    repoRoot: process.cwd(),
    cacheDir,
    enableAgent: false,
    createAdapter: (platform, hooks) =>
      createFakeAdapter(
        { repoRoot: process.cwd(), cacheDir, ...hooks },
        platform,
      ),
  });
  await session.start("android");
  const result = await session.call(
    "robot_observe",
    {},
    new AbortController().signal,
  );
  assert.equal(result.success, true);
  assert.equal(result.contentItems[0]?.type, "inputText");
  assert.equal(result.contentItems[1]?.type, "inputImage");
  assert.match(
    (result.contentItems[1] as { imageUrl: string }).imageUrl,
    /^data:image\/png;base64,/,
  );
  await session.end();
});

test("takeover waits for a dispatched agent action and never replays it", async () => {
  const cacheDir = await mkdtemp(join(tmpdir(), "stash-robot-takeover-"));
  let release!: () => void,
    markStarted!: () => void,
    actionCount = 0;
  const started = new Promise<void>((resolve) => {
    markStarted = resolve;
  });
  const blocked = new Promise<void>((resolve) => {
    release = resolve;
  });
  const session = new RobotSession({
    repoRoot: process.cwd(),
    cacheDir,
    enableAgent: false,
    createAdapter: (platform, hooks) => {
      const base = createFakeAdapter(
        { repoRoot: process.cwd(), cacheDir, ...hooks },
        platform,
      );
      return {
        ...base,
        async act(action, signal) {
          actionCount++;
          markStarted();
          await blocked;
          await base.act(action, signal);
        },
      };
    },
  });
  await session.start("android");
  const frame = (await session.observe("agent")).observation;
  const action = session.call(
    "robot_act",
    { action: { type: "tap", x: 0.5, y: 0.5, frameId: frame.frameId } },
    new AbortController().signal,
  );
  const actionRejected = action.then((result) => {
    assert.equal(result.success, false);
    assert.match(JSON.stringify(result.contentItems), /control ended/);
  });
  await started;
  let takeoverDone = false;
  const takeover = session.takeControl().then(() => {
    takeoverDone = true;
  });
  await new Promise((done) => setTimeout(done, 20));
  assert.equal(takeoverDone, false);
  release();
  await takeover;
  await actionRejected;
  assert.equal(actionCount, 1);
  assert.equal(session.snapshot().control, "manual");
  await session.end();
});

test("end aborts inflight work and stops the adapter only after it settles", async () => {
  const cacheDir = await mkdtemp(join(tmpdir(), "stash-robot-stop-"));
  let release!: () => void,
    markStarted!: () => void,
    inFlight = false,
    stoppedWhileActive = false;
  const started = new Promise<void>((resolve) => {
    markStarted = resolve;
  });
  const blocked = new Promise<void>((resolve) => {
    release = resolve;
  });
  const session = new RobotSession({
    repoRoot: process.cwd(),
    cacheDir,
    enableAgent: false,
    createAdapter: (platform, hooks) => {
      const base = createFakeAdapter(
        { repoRoot: process.cwd(), cacheDir, ...hooks },
        platform,
      );
      return {
        ...base,
        async act(action) {
          inFlight = true;
          markStarted();
          await blocked;
          await base.act(action);
          inFlight = false;
        },
        async stop() {
          stoppedWhileActive ||= inFlight;
          await base.stop();
        },
      };
    },
  });
  await session.start("android");
  const frame = (await session.observe("agent")).observation;
  const action = session.call(
    "robot_act",
    { action: { type: "tap", x: 0.5, y: 0.5, frameId: frame.frameId } },
    new AbortController().signal,
  );
  const actionRejected = action.then((result) =>
    assert.equal(result.success, false),
  );
  await started;
  let ended = false;
  const ending = session.end().then(() => {
    ended = true;
  });
  await new Promise((done) => setTimeout(done, 20));
  assert.equal(ended, false);
  release();
  await ending;
  await actionRejected;
  assert.equal(stoppedWhileActive, false);
  assert.equal(session.snapshot().phase, "ended");
});

test("startup failure stops the partial adapter and permits a clean retry", async () => {
  const cacheDir = await mkdtemp(join(tmpdir(), "stash-robot-start-fail-"));
  let attempts = 0,
    stops = 0;
  const session = new RobotSession({
    repoRoot: process.cwd(),
    cacheDir,
    enableAgent: false,
    createAdapter: (platform, hooks): DeviceAdapter => {
      const base = createFakeAdapter(
        { repoRoot: process.cwd(), cacheDir, ...hooks },
        platform,
      );
      attempts++;
      return {
        ...base,
        async start(options, signal) {
          if (attempts === 1) throw new Error("build failed");
          return base.start(options, signal);
        },
        async stop() {
          stops++;
          await base.stop();
        },
      };
    },
  });
  await assert.rejects(session.start("android"), /build failed/);
  assert.equal(stops, 1);
  assert.equal(session.snapshot().phase, "error");
  await session.start("android");
  assert.equal(session.snapshot().phase, "ready");
  await session.end();
  assert.equal(stops, 2);
});

test("an internal subscriber does not prevent abandoned-session cleanup", async () => {
  const cacheDir = await mkdtemp(join(tmpdir(), "stash-robot-abandon-"));
  const session = new RobotSession({
    repoRoot: process.cwd(),
    cacheDir,
    enableAgent: false,
    abandonMs: 20,
    createAdapter: (platform, hooks) =>
      createFakeAdapter(
        { repoRoot: process.cwd(), cacheDir, ...hooks },
        platform,
      ),
  });
  const phases: string[] = [];
  const unsubscribe = session.subscribe((event) => {
    if (event.type === "state")
      phases.push((event.data as { phase: string }).phase);
  });
  await new Promise((done) => setTimeout(done, 60));
  unsubscribe();
  assert.equal(session.snapshot().phase, "ended");
  assert(phases.includes("ended"));
});

test("ending during startup wins the lifecycle race and stops the owned adapter once", async () => {
  const cacheDir = await mkdtemp(join(tmpdir(), "stash-robot-end-start-"));
  let release!: () => void,
    markStarted!: () => void,
    stops = 0;
  const started = new Promise<void>((resolve) => {
    markStarted = resolve;
  });
  const blocked = new Promise<void>((resolve) => {
    release = resolve;
  });
  const session = new RobotSession({
    repoRoot: process.cwd(),
    cacheDir,
    enableAgent: false,
    createAdapter: (platform, hooks) => {
      const base = createFakeAdapter(
        { repoRoot: process.cwd(), cacheDir, ...hooks },
        platform,
      );
      return {
        ...base,
        async start(options) {
          markStarted();
          await blocked;
          return base.start(options);
        },
        async stop() {
          stops++;
          await base.stop();
        },
      };
    },
  });
  const phases: string[] = [];
  session.subscribe((event) => {
    if (event.type === "state")
      phases.push((event.data as { phase: string }).phase);
  });
  const startup = session.start("android");
  const startupRejected = assert.rejects(startup, /cancel/i);
  await started;
  const ending = session.end();
  release();
  await Promise.all([startupRejected, ending]);
  assert.equal(session.snapshot().phase, "ended");
  assert.equal(stops, 1);
  assert(!phases.includes("error"));
});

test("initial scenario model failure is reported while the ready device remains usable", async () => {
  const cacheDir = await mkdtemp(join(tmpdir(), "stash-robot-scenario-fail-"));
  const errors: unknown[] = [];
  const session = new RobotSession({
    repoRoot: process.cwd(),
    cacheDir,
    scenario: "test it",
    createAdapter: (platform, hooks) =>
      createFakeAdapter(
        { repoRoot: process.cwd(), cacheDir, ...hooks },
        platform,
      ),
    createCodexBridge: (options) => {
      const bridge = new CodexBridge({
        ...options,
        command: process.execPath,
        args: [join(process.cwd(), "test/fixtures/mock-codex.mjs"), "nonimage"],
      });
      const open = bridge.open.bind(bridge);
      bridge.open = () => open(false);
      return bridge;
    },
  });
  session.subscribe((event) => {
    if (event.type === "error") errors.push(event.data);
  });
  await session.start("android");
  assert.equal(session.snapshot().phase, "ready");
  assert(errors.length > 0);
  await assert.rejects(
    session.queueScenario("try again"),
    /does not accept image input/,
  );
  assert.equal(session.snapshot().phase, "ready");
  await session.takeControl();
  const frame = (await session.observe("manual")).observation;
  await session.act(
    { type: "tap", x: 0.5, y: 0.5, frameId: frame.frameId },
    "manual",
  );
  await session.end();
});

test("robot_logs polls browser logs before taking its bounded snapshot", async () => {
  const cacheDir = await mkdtemp(join(tmpdir(), "stash-robot-logs-"));
  const session = new RobotSession({
    repoRoot: process.cwd(),
    cacheDir,
    enableAgent: false,
    createAdapter: (platform, hooks) => {
      const base = createFakeAdapter(
        { repoRoot: process.cwd(), cacheDir, ...hooks },
        platform,
      );
      base.webview.pollLogs = async () =>
        hooks.onLog({
          timestamp: new Date().toISOString(),
          source: "network",
          level: "info",
          message: "fresh request",
        });
      return base;
    },
  });
  await session.start("android");
  const output = await session.call(
    "robot_logs",
    { source: "network" },
    new AbortController().signal,
  );
  const text = output.contentItems[0] as { type: "inputText"; text: string };
  assert.match(text.text, /fresh request/);
  await session.end();
});

test("screenshot retention is bounded while preserving the latest CSS comparison", async () => {
  const cacheDir = await mkdtemp(join(tmpdir(), "stash-robot-retention-"));
  const session = new RobotSession({
    repoRoot: process.cwd(),
    cacheDir,
    enableAgent: false,
    createAdapter: (platform, hooks) =>
      createFakeAdapter(
        { repoRoot: process.cwd(), cacheDir, ...hooks },
        platform,
      ),
  });
  await session.start("android");
  await session.takeControl();
  let frame = (await session.observe("manual")).observation;
  await session.act(
    { type: "tap", x: 0.5, y: 0.5, frameId: frame.frameId },
    "manual",
  );
  const comparison = await session.webview(
    { operation: "setCss", css: "body{outline:3px solid red}" },
    "manual",
  );
  const oldest = (await session.observe("system")).observation;
  for (let index = 0; index < 35; index++)
    frame = (await session.observe("system")).observation;
  assert.equal(session.framePath(oldest.frameId), undefined);
  assert(session.framePath(comparison.before!.frameId));
  assert(session.framePath(comparison.after.observation.frameId));
  assert(session.framePath(frame.frameId));
  await session.end();
});

test("active CSS state clears when the same target URL reloads outside the harness", async () => {
  const cacheDir = await mkdtemp(join(tmpdir(), "stash-robot-css-reload-"));
  let device!: DeviceAdapter;
  const session = new RobotSession({
    repoRoot: process.cwd(),
    cacheDir,
    enableAgent: false,
    createAdapter: (platform, hooks) =>
      (device = createFakeAdapter(
        { repoRoot: process.cwd(), cacheDir, ...hooks },
        platform,
      )),
  });
  await session.start("android");
  await session.takeControl();
  const frame = (await session.observe("manual")).observation;
  await session.act(
    { type: "tap", x: 0.5, y: 0.5, frameId: frame.frameId },
    "manual",
  );
  await session.webview(
    { operation: "setCss", css: "body{color:red}" },
    "manual",
  );
  assert.equal(session.snapshot().activeCss, "body{color:red}");
  await device.webview.reload();
  await session.observe("system");
  assert.equal(session.snapshot().activeCss, "");
  await session.end();
});

test("uncertain dispatched actions return failure with a fresh actual screenshot and no replay", async () => {
  const cacheDir = await mkdtemp(join(tmpdir(), "stash-robot-uncertain-"));
  let actions = 0;
  const session = new RobotSession({
    repoRoot: process.cwd(),
    cacheDir,
    enableAgent: false,
    createAdapter: (platform, hooks) => {
      const base = createFakeAdapter(
        { repoRoot: process.cwd(), cacheDir, ...hooks },
        platform,
      );
      const act = base.act.bind(base);
      base.act = async (action, signal) => {
        actions++;
        await act(action, signal);
        throw new Error("Connection lost after dispatch");
      };
      base.webview.status = () => ({
        connected: true,
        coverageSince: "2026-01-01T00:00:00Z",
      });
      return base;
    },
  });
  try {
    await session.start("android");
    const before = session.snapshot().observation!;
    const output = await session.call(
      "robot_act",
      { action: { type: "tap", x: 0.5, y: 0.5, frameId: before.frameId } },
      new AbortController().signal,
    );
    assert.equal(output.success, false);
    assert.equal(actions, 1);
    assert(
      output.contentItems.some(
        (item) =>
          item.type === "inputImage" &&
          item.imageUrl.startsWith("data:image/png;base64,"),
      ),
    );
    assert.notEqual(session.snapshot().observation!.frameId, before.frameId);
    assert.equal(session.snapshot().observation!.debugger?.connected, true);
  } finally {
    await session.end();
  }
});

test("browser reconnect invalidates old coordinate frames and observes before continuing", async () => {
  const cacheDir = await mkdtemp(join(tmpdir(), "stash-robot-reconnect-"));
  const session = new RobotSession({
    repoRoot: process.cwd(),
    cacheDir,
    enableAgent: false,
    createAdapter: (platform, hooks) =>
      createFakeAdapter(
        { repoRoot: process.cwd(), cacheDir, ...hooks },
        platform,
      ),
  });
  try {
    await session.start("android");
    await session.takeControl();
    const before = session.snapshot().observation!;
    const disconnect = session.connect(() => {});
    await assert.rejects(
      session.act(
        { type: "tap", x: 0.5, y: 0.5, frameId: before.frameId },
        "manual",
      ),
      /stale/,
    );
    assert.notEqual(session.snapshot().observation!.frameId, before.frameId);
    disconnect();
  } finally {
    await session.end();
  }
});
