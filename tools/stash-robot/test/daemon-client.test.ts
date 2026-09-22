import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createFakeAdapter } from "../src/fake.js";
import { startServer } from "../src/server.js";
import {
  isServerRecord,
  transferScenario,
  verifyDaemon,
} from "../src/daemon-client.js";

test("daemon reuse verifies authentication and transfers scenarios before platform selection", async () => {
  const cacheDir = await mkdtemp(join(tmpdir(), "stash-robot-daemon-"));
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
  const record = {
    pid: process.pid,
    port: server.port,
    token: server.token,
    url: server.url,
    startedAt: new Date().toISOString(),
  };
  try {
    assert.equal(isServerRecord(record), true);
    assert.equal((await verifyDaemon(record))?.phase, "selecting");
    assert.equal(
      await verifyDaemon({
        ...record,
        token: "incorrect-token-with-valid-length",
      }),
      undefined,
    );
    assert.equal(
      await verifyDaemon({ ...record, url: "https://example.com/" }),
      undefined,
    );
    await transferScenario(record, "Inspect the existing checkout");
    assert.equal(server.session.snapshot().phase, "selecting");
  } finally {
    await server.close();
    await rm(cacheDir, { recursive: true, force: true });
  }
});
