import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createFakeAdapter } from "../src/fake.js";
import { startServer } from "../src/server.js";

test("HTTP session routes require token and same-origin writes", async () => {
  const cacheDir = await mkdtemp(join(tmpdir(), "stash-robot-server-"));
  const server = await startServer({
    repoRoot: process.cwd(),
    cacheDir,
    enableAgent: false,
    createAdapter: (platform, hooks) =>
      createFakeAdapter(
        { repoRoot: process.cwd(), cacheDir, ...hooks },
        platform,
      ),
  });
  const origin = new URL(server.url).origin;
  try {
    assert.equal((await fetch(`${server.url}api/bootstrap`)).status, 401);
    assert.equal(
      (
        await fetch(`${server.url}api/bootstrap`, {
          headers: { "x-stash-token": "wrong" },
        })
      ).status,
      401,
    );
    assert.equal(
      (
        await fetch(`${server.url}api/doctor`, {
          method: "POST",
          headers: {
            "x-stash-token": server.token,
            "content-type": "application/json",
          },
          body: "{}",
        })
      ).status,
      403,
    );
    let checked: any;
    for (let attempt = 0; attempt < 100; attempt++) {
      checked = await fetch(`${server.url}api/bootstrap`, {
        headers: { "x-stash-token": server.token },
      }).then((value) => value.json());
      if (checked.doctors.android) break;
      await new Promise((done) => setTimeout(done, 10));
    }
    const start = await fetch(`${server.url}api/start`, {
      method: "POST",
      headers: {
        "x-stash-token": server.token,
        origin,
        "content-type": "application/json",
      },
      body: JSON.stringify({ platform: "android" }),
    });
    assert.equal(start.status, 202);
    const duplicate = await fetch(`${server.url}api/start`, {
      method: "POST",
      headers: {
        "x-stash-token": server.token,
        origin,
        "content-type": "application/json",
      },
      body: JSON.stringify({ platform: "android" }),
    });
    assert.equal(duplicate.status, 409);
    let snapshot: any;
    for (let attempt = 0; attempt < 100; attempt++) {
      snapshot = await fetch(`${server.url}api/bootstrap`, {
        headers: { "x-stash-token": server.token },
      }).then((value) => value.json());
      if (snapshot.phase === "ready" && snapshot.observation) break;
      await new Promise((done) => setTimeout(done, 10));
    }
    assert.equal(snapshot.phase, "ready");
    assert(snapshot.observation.frameId);
    const frame = await fetch(`${origin}${snapshot.observation.imageUrl}`, {
      headers: { "x-stash-token": server.token },
    });
    assert.equal(frame.headers.get("content-type"), "image/png");
    assert((await frame.arrayBuffer()).byteLength > 100);
  } finally {
    await server.close();
  }
});

test("event reconnect replays only events newer than the supplied id", async () => {
  const cacheDir = await mkdtemp(join(tmpdir(), "stash-robot-events-"));
  const server = await startServer({
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
    const received: number[] = [];
    const disconnect = server.session.connect((event) =>
      received.push(event.id),
    );
    await server.session.doctor(["android"]);
    disconnect();
    const last = received.at(-2)!;
    const replay: number[] = [];
    const disconnect2 = server.session.connect(
      (event) => replay.push(event.id),
      last,
    );
    disconnect2();
    assert(replay.length > 0);
    assert(replay.every((id) => id > last));
  } finally {
    await server.close();
  }
});

test("start rejects a platform whose completed prerequisite report is not ready", async () => {
  const cacheDir = await mkdtemp(join(tmpdir(), "stash-robot-prereq-"));
  const server = await startServer({
    repoRoot: process.cwd(),
    cacheDir,
    enableAgent: false,
    prerequisiteChecks: async () => [
      { name: "Codex", ok: false, detail: "run codex login" },
    ],
    createAdapter: (platform, hooks) =>
      createFakeAdapter(
        { repoRoot: process.cwd(), cacheDir, ...hooks },
        platform,
      ),
  });
  const origin = new URL(server.url).origin,
    headers = {
      "x-stash-token": server.token,
      origin,
      "content-type": "application/json",
    };
  try {
    for (let attempt = 0; attempt < 100; attempt++) {
      const snapshot: any = await fetch(`${server.url}api/bootstrap`, {
        headers: { "x-stash-token": server.token },
      }).then((value) => value.json());
      if (snapshot.doctors.android) break;
      await new Promise((done) => setTimeout(done, 10));
    }
    const response = await fetch(`${server.url}api/start`, {
      method: "POST",
      headers,
      body: JSON.stringify({ platform: "android" }),
    });
    assert.equal(response.status, 409);
    assert.match(await response.text(), /prerequisites are not ready/);
    assert.equal(server.session.snapshot().phase, "selecting");
  } finally {
    await server.close();
  }
});
