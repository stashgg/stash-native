import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:net";
import { run, pngDimensions, freeEmulatorPort } from "../src/process.js";
import { createFakeAdapter } from "../src/fake.js";

test("process runner preserves binary output and passes arguments literally", async () => {
  const result = await run(process.execPath, [
    "-e",
    "process.stdout.write(Buffer.from([0,255,13,10])); process.stderr.write(process.argv[1])",
    "`$(literal)`",
  ]);
  assert.deepEqual([...result.stdout], [0, 255, 13, 10]);
  assert.equal(result.stderr, "`$(literal)`");
});
test("process runner cancels a child without waiting for its natural exit", async () => {
  const controller = new AbortController();
  const pending = run(process.execPath, ["-e", "setTimeout(() => {}, 60000)"], {
    signal: controller.signal,
  });
  const rejected = assert.rejects(pending);
  controller.abort();
  await rejected;
});
test("fake capture emits a valid PNG with orientation metadata", async () => {
  const adapter = createFakeAdapter({
    repoRoot: ".",
    cacheDir: ".",
    onLog() {},
    onProgress() {},
  });
  await adapter.start({});
  const portrait = await adapter.capture();
  assert.deepEqual(pngDimensions(portrait.png), { width: 320, height: 640 });
  await adapter.act({ type: "rotate", orientation: "landscape" });
  const landscape = await adapter.capture();
  assert.deepEqual(pngDimensions(landscape.png), { width: 640, height: 320 });
  await adapter.stop();
});

test("emulator allocation skips a pair when its ADB port is occupied", async () => {
  const first = await freeEmulatorPort();
  const occupied = createServer();
  await new Promise<void>((resolve, reject) => {
    occupied.once("error", reject);
    occupied.listen(first + 1, "127.0.0.1", resolve);
  });
  try {
    const available = await freeEmulatorPort();
    assert.notEqual(available, first);
    assert.equal(available % 2, 0);
  } finally {
    await new Promise<void>((resolve) => occupied.close(() => resolve()));
  }
});
