import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { WebSocketServer } from "ws";
import { AndroidCdp } from "../src/android/cdp.js";
import type { LogEntry } from "../src/contracts.js";

test("CDP reconnects logging and removes only its allocated forwards after target replacement", async () => {
  let port = 0;
  let listed = true;
  let connections = 0;
  const calls: string[][] = [];
  const logs: LogEntry[] = [];
  const server = createServer((_request, response) => {
    response.setHeader("content-type", "application/json");
    response.end(
      JSON.stringify(
        listed
          ? [
              {
                type: "page",
                id: "checkout",
                url: "https://test.example/",
                title: "Checkout",
                webSocketDebuggerUrl: `ws://localhost:${port}/page`,
              },
            ]
          : [],
      ),
    );
  });
  const wss = new WebSocketServer({ server });
  wss.on("connection", (socket) => {
    connections++;
    socket.on("message", (data) => {
      const request = JSON.parse(data.toString());
      socket.send(
        JSON.stringify({
          id: request.id,
          result:
            request.method === "Runtime.evaluate"
              ? { result: { value: 42 } }
              : {},
        }),
      );
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  port = (server.address() as { port: number }).port;
  const cdp = new AndroidCdp({
    serial: () => "emulator-5554",
    onLog: (log) => logs.push(log),
    runAdb: async (args) => {
      calls.push(args);
      if (args.includes("/proc/net/unix"))
        return Buffer.from(
          listed
            ? "@webview_devtools_remote_123\n@webview_devtools_remote_999\n"
            : "",
        );
      if (args.includes("pidof")) return Buffer.from("123");
      if (args[0] === "forward") return Buffer.from(String(port));
      throw new Error(`Unexpected ADB ${args.join(" ")}`);
    },
  });
  try {
    const targets = await cdp.listTargets();
    assert.equal(targets.length, 1);
    assert(calls.some((args) => args[1] === "tcp:0"));
    assert(
      !calls.some((args) =>
        args.includes("localabstract:webview_devtools_remote_999"),
      ),
    );
    for (const socket of wss.clients) socket.terminate();
    await new Promise((resolve) => setTimeout(resolve, 30));
    await cdp.listTargets();
    assert.equal(connections, 2);
    assert(logs.some((log) => log.message.includes("disconnected")));
    assert.equal(await cdp.evaluate("40+2", targets[0]!.id), 42);
    listed = false;
    assert.deepEqual(await cdp.listTargets(), []);
    assert(
      calls.some((args) => args[1] === "--remove" && args[2] === `tcp:${port}`),
    );
    assert(!calls.some((args) => args.includes("--remove-all")));
  } finally {
    await cdp.stop();
    for (const socket of wss.clients) socket.terminate();
    await new Promise<void>((resolve) => wss.close(() => resolve()));
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});

test("CDP does not inspect another application when the sample has no PID", async () => {
  const calls: string[][] = [];
  const cdp = new AndroidCdp({
    serial: () => "emulator-5554",
    onLog() {},
    runAdb: async (args) => {
      calls.push(args);
      return Buffer.from(
        args.includes("/proc/net/unix") ? "@webview_devtools_remote_999\n" : "",
      );
    },
  });
  assert.deepEqual(await cdp.listTargets(), []);
  assert(!calls.some((args) => args[0] === "forward"));
  await cdp.stop();
});
