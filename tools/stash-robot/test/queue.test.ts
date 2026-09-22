import test from "node:test";
import assert from "node:assert/strict";
import { PriorityActionQueue } from "../src/queue.js";

test("serializes operations and prioritizes actions over pending previews", async () => {
  const queue = new PriorityActionQueue();
  const order: string[] = [];
  let release!: () => void;
  const first = queue.run(async () => {
    order.push("first");
    await new Promise<void>((resolve) => {
      release = resolve;
    });
  });
  const preview = queue.run(
    async () => {
      order.push("preview");
    },
    { priority: -1 },
  );
  const action = queue.run(
    async () => {
      order.push("action");
    },
    { priority: 10 },
  );
  release();
  await Promise.all([first, preview, action]);
  await queue.idle();
  assert.deepEqual(order, ["first", "action", "preview"]);
  assert.equal(queue.busy, false);
});

test("cancellation rejects pending work and waits for dispatched work before idle", async () => {
  const queue = new PriorityActionQueue();
  let release!: () => void;
  let activeSignal!: AbortSignal;
  const active = queue.run(async (signal) => {
    activeSignal = signal;
    await new Promise<void>((resolve) => {
      release = resolve;
    });
  });
  const pending = queue.run(async () => {
    throw new Error("Must not execute");
  });
  const activeRejected = assert.rejects(active, /cancelled/);
  const pendingRejected = assert.rejects(pending, /cancelled/);
  queue.cancelAll();
  assert.equal(activeSignal.aborted, true);
  let idle = false;
  const waiting = queue.idle().then(() => {
    idle = true;
  });
  await Promise.resolve();
  assert.equal(idle, false);
  release();
  await Promise.all([activeRejected, pendingRejected, waiting]);
  assert.equal(idle, true);
});

test("external cancellation removes a queued action without cancelling the active one", async () => {
  const queue = new PriorityActionQueue();
  let release!: () => void;
  const active = queue.run(async (signal) => {
    await new Promise<void>((resolve) => {
      release = resolve;
    });
    assert.equal(signal.aborted, false);
  });
  const controller = new AbortController();
  const pending = queue.run(
    async () => assert.fail("Cancelled action executed"),
    { signal: controller.signal },
  );
  const rejected = assert.rejects(pending);
  controller.abort();
  release();
  await Promise.all([active, rejected]);
});
