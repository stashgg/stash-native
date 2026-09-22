import test from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { CodexBridge } from "../src/codex.js";

test("Codex bridge initializes one image-capable thread and answers dynamic tools", async () => {
  const events: any[] = [];
  let calls = 0;
  const bridge = new CodexBridge({
    cwd: process.cwd(),
    command: process.execPath,
    args: [join(process.cwd(), "test/fixtures/mock-codex.mjs")],
    onEvent: (event) => events.push(event),
    toolHost: {
      tools: [
        {
          type: "function",
          name: "robot_observe",
          description: "observe",
          inputSchema: { type: "object" },
        },
      ],
      call: async () => {
        calls++;
        return {
          success: true,
          contentItems: [
            { type: "inputText", text: "frame" },
            { type: "inputImage", imageUrl: "data:image/png;base64,AA==" },
          ],
        };
      },
    },
  });
  try {
    await bridge.open(false);
    const first = await bridge.startThread();
    const second = await bridge.startThread();
    assert.equal(first, second);
    await bridge.prompt("Inspect it");
    for (
      let attempt = 0;
      attempt < 100 &&
      (calls === 0 ||
        !events.some(
          (event) => event.data?.method === "item/agentMessage/delta",
        ));
      attempt++
    )
      await new Promise((done) => setTimeout(done, 10));
    assert.equal(calls, 1);
    assert(
      events.some((event) => event.data?.method === "item/agentMessage/delta"),
    );
  } finally {
    await bridge.close();
  }
});

test("Codex bridge starts a new turn only after steering definitively loses a completion race", async () => {
  const events: any[] = [];
  const bridge = new CodexBridge({
    cwd: process.cwd(),
    command: process.execPath,
    args: [join(process.cwd(), "test/fixtures/mock-codex.mjs"), "steer-race"],
    onEvent: (event) => events.push(event),
    toolHost: {
      tools: [],
      call: async () => ({ success: false, contentItems: [] }),
    },
  });
  try {
    await bridge.open(false);
    await bridge.prompt("first");
    assert.equal(bridge.inTurn, true);
    await bridge.prompt("second");
    assert.equal(bridge.inTurn, true);
    for (
      let attempt = 0;
      attempt < 20 &&
      !events.some((event) => event.data?.params?.turn?.id === "turn-2");
      attempt++
    )
      await new Promise((done) => setTimeout(done, 5));
    assert(events.some((event) => event.data?.params?.turn?.id === "turn-2"));
  } finally {
    await bridge.close();
  }
});

test("Codex bridge rejects a configured model without image input", async () => {
  const bridge = new CodexBridge({
    cwd: process.cwd(),
    command: process.execPath,
    args: [join(process.cwd(), "test/fixtures/mock-codex.mjs"), "nonimage"],
    onEvent: () => {},
    toolHost: {
      tools: [],
      call: async () => ({ success: false, contentItems: [] }),
    },
  });
  try {
    await bridge.open(false);
    await assert.rejects(bridge.startThread(), /does not accept image input/);
    await assert.rejects(bridge.startThread(), /does not accept image input/);
    await assert.rejects(
      bridge.prompt("still invalid"),
      /does not accept image input/,
    );
  } finally {
    await bridge.close();
  }
});

test("browser approval responses cannot expand the worker read-only sandbox", () => {
  const bridge = new CodexBridge({
    cwd: process.cwd(),
    onEvent() {},
    toolHost: {
      tools: [],
      call: async () => ({ success: false, contentItems: [] }),
    },
  });
  const internal = bridge as any;
  const sent: unknown[] = [];
  internal.send = (value: unknown) => sent.push(value);
  for (const method of [
    "item/commandExecution/requestApproval",
    "item/fileChange/requestApproval",
  ]) {
    internal.pendingServer.set(1, { method, params: {} });
    assert.throws(() => bridge.respond(1, { decision: "accept" }), /read-only/);
    bridge.respond(1, { decision: "decline" });
  }
  internal.pendingServer.set(2, {
    method: "item/permissions/requestApproval",
    params: {},
  });
  assert.throws(
    () =>
      bridge.respond(2, {
        permissions: { fileSystem: { write: ["/tmp"] } },
        scope: "turn",
      }),
    /read-only/,
  );
  bridge.respond(2, { permissions: {}, scope: "turn" });
  assert.equal(sent.length, 3);
});
