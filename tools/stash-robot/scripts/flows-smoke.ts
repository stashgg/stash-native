import assert from "node:assert/strict";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { createAndroidAdapter } from "../src/android.js";
import { createIosAdapter } from "../src/ios.js";
import { delay } from "../src/process.js";
import type {
  DeviceAdapter,
  DeviceInfo,
  LogEntry,
  WebViewTarget,
} from "../src/contracts.js";

const platform = process.argv[2];
if (platform !== "android" && platform !== "ios") {
  throw new Error(
    "Usage: node --import tsx scripts/flows-smoke.ts android|ios",
  );
}

const checkoutUrl = "https://test.stashpreview.com/";
const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const artifactDir = join(
  repoRoot,
  "build/stash-robot/acceptance",
  `flows-${platform}`,
);
const logs: LogEntry[] = [];
const adapter: DeviceAdapter = (
  platform === "android" ? createAndroidAdapter : createIosAdapter
)({
  repoRoot,
  cacheDir: join(repoRoot, "build/stash-robot/cache"),
  onLog(entry) {
    logs.push(entry);
    if (logs.length > 30_000) logs.shift();
  },
  onProgress(message) {
    if (/Starting|Building|Installing|Launching|action/.test(message)) {
      console.log(message.slice(0, 300));
    }
  },
});

async function saveFrame(name: string): Promise<void> {
  const frame = await adapter.capture();
  await writeFile(join(artifactDir, `${name}.png`), frame.png);
}

async function scrollUntil(
  selector: string,
  direction: "up" | "down",
): Promise<void> {
  for (let attempt = 0; attempt < 7; attempt++) {
    if ((await adapter.hierarchy()).includes(selector)) return;
    await adapter.act({
      type: "swipe",
      fromX: 0.5,
      fromY: direction === "up" ? 0.78 : 0.3,
      toX: 0.5,
      toY: direction === "up" ? 0.3 : 0.78,
      durationMs: 350,
      frameId: `find-${selector}-${attempt}`,
    });
    await delay(250);
  }
  throw new Error(`Native element did not become visible: ${selector}`);
}

async function setUrlField(prefix: "modal" | "browser"): Promise<void> {
  const field = `${prefix}-url-field`;
  await scrollUntil(field, prefix === "modal" ? "up" : "down");
  await adapter.act({ type: "type", selector: field, text: checkoutUrl });
  await adapter.act({ type: "hideKeyboard" });
  await adapter.act({ type: "tapElement", selector: `${prefix}-open-button` });
}

async function checkoutTarget(
  excludedId?: string,
): Promise<WebViewTarget | undefined> {
  for (let attempt = 0; attempt < 45; attempt++) {
    const target = (await adapter.webview.listTargets()).find(
      (item) =>
        item.id !== excludedId && item.url.startsWith(checkoutUrl.slice(0, -1)),
    );
    if (target) return target;
    await delay(1_000);
  }
  return undefined;
}

async function waitForTargetClose(targetId: string): Promise<void> {
  for (let attempt = 0; attempt < 20; attempt++) {
    if (
      !(await adapter.webview.listTargets()).some(
        (item) => item.id === targetId,
      )
    ) {
      return;
    }
    await delay(250);
  }
  throw new Error("Modal WebView remained attached after window.close()");
}

async function waitForSampleReturn(): Promise<string> {
  for (let attempt = 0; attempt < 20; attempt++) {
    const hierarchy = await adapter.hierarchy();
    if (
      [
        "browser-url-field",
        "modal-url-field",
        "card-url-field",
        "Instances",
      ].some((selector) => hierarchy.includes(selector))
    ) {
      return hierarchy;
    }
    await delay(500);
  }
  throw new Error("External browser control did not return to the sample app");
}

let device: DeviceInfo | undefined;
await mkdir(artifactDir, { recursive: true });
try {
  const doctor = await adapter.doctor();
  assert.equal(doctor.ready, true, JSON.stringify(doctor.checks));
  device = await adapter.start({});
  await saveFrame("startup");

  await setUrlField("modal");
  const modal = await checkoutTarget();
  assert.ok(modal, "Modal checkout WebView becomes inspectable");
  for (let attempt = 0; attempt < 60; attempt++) {
    const ready = await adapter.webview.evaluate(
      'location.href.startsWith("https://test.stashpreview.com") && document.readyState === "complete"',
      modal.id,
    );
    if (ready) break;
    if (attempt === 59)
      throw new Error("Modal checkout did not finish loading");
    await delay(500);
  }
  const body = await adapter.webview.inspect(modal.id, "body");
  assert.ok(
    body && typeof body === "object",
    "Modal DOM inspection returns metadata",
  );
  assert.equal(
    await adapter.webview.evaluate(
      'new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(() => resolve("flow-async-ok"), 250))))',
      modal.id,
    ),
    "flow-async-ok",
    "Delayed async WebView evaluation completes",
  );
  await adapter.webview.setCss(
    "body { outline: 12px solid rgb(255, 0, 255) !important; outline-offset: -12px !important; }",
    modal.id,
  );
  assert.ok(
    Math.abs(
      Number.parseFloat(
        String(
          await adapter.webview.evaluate(
            "getComputedStyle(document.body).outlineWidth",
            modal.id,
          ),
        ),
      ) - 12,
    ) < 1,
    "Outline is approximately 12 CSS pixels on the scaled device",
  );
  await saveFrame("modal-open");
  await adapter.webview
    .evaluate("window.close()", modal.id)
    .catch(() => undefined);
  await waitForTargetClose(modal.id);
  await saveFrame("modal-closed");

  await setUrlField("browser");
  await delay(1_500);
  await saveFrame("external-browser-open");
  if (platform === "ios") {
    // SFSafariViewController exposes Done to XCUITest, but its element click can
    // return success without actuating the remote-view button on iOS 18. Tap
    // the stable leading navigation-button position on the captured frame.
    await adapter.act({
      type: "tap",
      x: 0.085,
      y: 0.093,
      frameId: "external-browser-open",
    });
  } else {
    await adapter.act({ type: "back" });
  }
  const returnedHierarchy = await waitForSampleReturn();
  assert.ok(
    returnedHierarchy.includes("browser-url-field") ||
      returnedHierarchy.includes("Instances"),
    "External browser control returns to the sample app",
  );
  await saveFrame("external-browser-closed");

  const report = {
    platform,
    device,
    modal: {
      url: modal.url,
      domInspected: true,
      delayedAsyncEvaluation: true,
      temporaryCss: true,
      closedByWindowClose: true,
    },
    externalBrowser: { url: checkoutUrl, returnedToSample: true },
    completedAt: new Date().toISOString(),
  };
  await writeFile(
    join(artifactDir, "report.json"),
    `${JSON.stringify(report, null, 2)}\n`,
  );
  console.log("PASS", JSON.stringify(report));
} catch (error) {
  await saveFrame("failure").catch(() => undefined);
  await adapter
    .hierarchy()
    .then((hierarchy) => writeFile(join(artifactDir, "failure.xml"), hierarchy))
    .catch(() => undefined);
  throw error;
} finally {
  await adapter.stop();
  await writeFile(
    join(artifactDir, "logs.json"),
    `${JSON.stringify(logs, null, 2)}\n`,
  );
}
