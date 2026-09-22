import assert from "node:assert/strict";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createAndroidAdapter } from "../src/android.js";
import { createIosAdapter } from "../src/ios.js";
import { delay } from "../src/process.js";
import type { LogEntry } from "../src/contracts.js";

const platform = process.argv[2];
if (platform !== "android" && platform !== "ios")
  throw new Error("Usage: node --import tsx scripts/smoke.ts android|ios");
const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const artifactDir = join(
  repoRoot,
  "build",
  "stash-robot",
  "acceptance",
  platform,
);
await mkdir(artifactDir, { recursive: true });
const logs: LogEntry[] = [];
const adapter = (
  platform === "android" ? createAndroidAdapter : createIosAdapter
)({
  repoRoot,
  cacheDir: join(repoRoot, "build", "stash-robot", "cache"),
  onLog: (entry) => {
    logs.push(entry);
    if (entry.level === "error") console.error(entry.message.slice(0, 500));
  },
  onProgress: (message) => {
    if (
      !/^\s|^\/|Compile|Swift|clang|Ld |Copy|Touch|Write|Validate|Process|CodeSign|Register/.test(
        message,
      )
    )
      console.log(message.slice(0, 250));
  },
});
const saveFrame = async (name: string) => {
  const frame = await adapter.capture();
  await writeFile(join(artifactDir, `${name}.png`), frame.png);
  return frame;
};
try {
  console.log(JSON.stringify(await adapter.doctor()));
  const device = await adapter.start({});
  console.log("DEVICE", JSON.stringify(device));
  await saveFrame("startup");
  await adapter.act({
    type: "type",
    selector: "card-url-field",
    text: "https://test.stashpreview.com/",
  });
  await adapter.act({ type: "hideKeyboard" });
  await adapter.act({ type: "tapElement", selector: "card-open-button" });
  let target: string | undefined;
  for (let attempt = 0; attempt < 45; attempt++) {
    const targets = await adapter.webview.listTargets();
    target = targets.find((item) =>
      item.url.startsWith("https://test.stashpreview.com"),
    )?.id;
    if (target) break;
    await delay(1000);
  }
  assert.ok(target, "Checkout WebView target becomes available");
  console.log("TARGET", target);
  for (let attempt = 0; attempt < 90; attempt++) {
    if (
      await adapter.webview.evaluate(
        'location.href.startsWith("https://test.stashpreview.com") && document.readyState === "complete" && !!document.querySelector("input:not([type=hidden])")',
        target,
      )
    )
      break;
    await delay(500);
  }
  await saveFrame("checkout-loaded");
  const dom = await adapter.webview.inspect(target, "body");
  assert.ok(dom && typeof dom === "object", "DOM inspection returns metadata");
  const input = await adapter.webview.evaluate(
    '(() => { const el=document.querySelector("#sample-input") || document.querySelector("input:not([type=hidden])"); if (!el) return null; el.value="stash-robot smoke"; el.dispatchEvent(new Event("input",{bubbles:true})); return el.value; })()',
    target,
  );
  assert.equal(input, "stash-robot smoke");
  await adapter.act({
    type: "swipe",
    fromX: 0.5,
    fromY: 0.75,
    toX: 0.5,
    toY: 0.45,
    durationMs: 300,
    frameId: "smoke",
  });
  await saveFrame("before-css");
  await adapter.webview.setCss(
    "body { outline: 12px solid rgb(255, 0, 255) !important; outline-offset: -12px !important; }",
    target,
  );
  const outlineWidth = Number.parseFloat(
    String(
      await adapter.webview.evaluate(
        "getComputedStyle(document.body).outlineWidth",
        target,
      ),
    ),
  );
  assert.ok(
    Math.abs(outlineWidth - 12) < 1,
    `Visible outline is approximately 12px (received ${outlineWidth})`,
  );
  await saveFrame("after-css");
  await adapter.webview.evaluate(
    '(() => { console.error("stash-robot smoke console marker"); fetch(location.href).catch(console.error); return true; })()',
    target,
  );
  await delay(1500);
  await adapter.webview.pollLogs?.();
  await adapter.webview.resetCss(target);
  assert.equal(
    await adapter.webview.evaluate(
      'document.getElementById("stash-robot-live-css") === null',
      target,
    ),
    true,
  );
  await saveFrame("reset-css");
  // The SDK owns window.close and can destroy the target before its reply arrives.
  await adapter.webview
    .evaluate("window.close()", target)
    .catch((error) =>
      console.log("Close detached target:", String(error).slice(0, 200)),
    );
  await delay(500);
  await saveFrame("closed");
  assert.ok(
    logs.some((item) => item.source === "native"),
    "Native logs captured",
  );
  assert.ok(
    logs.some(
      (item) =>
        item.source === "console" &&
        item.message.includes("stash-robot smoke console marker"),
    ),
    "Console marker captured",
  );
  assert.ok(
    logs.some((item) => item.source === "network"),
    "WebView network events captured",
  );
  await adapter.restart();
  await saveFrame("restarted");
  const report = {
    platform,
    device,
    passed: true,
    nativeLogs: logs.filter((l) => l.source === "native").length,
    consoleLogs: logs.filter((l) => l.source === "console").length,
    networkLogs: logs.filter((l) => l.source === "network").length,
    completedAt: new Date().toISOString(),
  };
  await writeFile(
    join(artifactDir, "report.json"),
    JSON.stringify(report, null, 2),
  );
  console.log("PASS", JSON.stringify(report));
} finally {
  await adapter.stop();
  await writeFile(
    join(artifactDir, "logs.json"),
    JSON.stringify(logs, null, 2),
  );
}
