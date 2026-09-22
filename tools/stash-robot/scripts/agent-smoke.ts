import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createAndroidAdapter } from "../src/android.js";
import { createIosAdapter } from "../src/ios.js";
import type { Platform, RobotEvent } from "../src/contracts.js";
import type { DynamicToolCallResponse } from "../src/protocol.js";
import { RobotSession } from "../src/session.js";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const cacheDir = join(repoRoot, "build", "stash-robot", "cache");
const platform = (process.argv.find(
  (argument) => argument === "android" || argument === "ios",
) ?? "android") as Platform;
const artifactDir = join(
  repoRoot,
  "build",
  "stash-robot",
  "acceptance",
  `agent-${platform}`,
);
await mkdir(artifactDir, { recursive: true });

type ToolRecord = {
  sequence: number;
  name: string;
  args: unknown;
  startedAt: string;
  completedAt?: string;
  success?: boolean;
  error?: string;
  image?: {
    artifact: string;
    bytes: number;
    sha256: string;
    actualPng: boolean;
  };
  details?: unknown;
  beforeImage?: { artifact: string; bytes: number; sha256: string };
};

if (
  process.argv.includes("--verify-artifacts") ||
  process.argv.includes("--verify-existing")
) {
  const recordedTools = JSON.parse(
    await readFile(join(artifactDir, "tools.json"), "utf8"),
  ) as ToolRecord[];
  const recordedEvents = JSON.parse(
    await readFile(join(artifactDir, "events.json"), "utf8"),
  ) as RobotEvent[];
  const completedTurns = recordedEvents
    .filter(isCompletedTurn)
    .map(turnSummary);
  const ok = (name: string) =>
    recordedTools.filter((tool) => tool.name === name && tool.success);
  const webview = (operation: string) =>
    recordedTools.filter(
      (tool) =>
        tool.name === "robot_webview" &&
        (tool.args as any)?.operation === operation &&
        tool.success,
    );

  assert.ok(
    recordedTools.length > 0,
    "recorded live run contains dynamic tool calls",
  );
  assert.ok(
    recordedTools
      .filter((tool) => tool.success)
      .every((tool) => tool.image?.actualPng),
    "every successful tool result recorded an actual PNG",
  );
  for (const tool of recordedTools.filter((item) => item.success)) {
    const image = await readFile(join(artifactDir, tool.image!.artifact));
    assert.ok(
      image
        .subarray(0, 8)
        .equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])),
      `${tool.image!.artifact} is an actual PNG`,
    );
    assert.equal(
      sha256(image),
      tool.image!.sha256,
      `${tool.image!.artifact} matches its recorded digest`,
    );
  }
  assert.equal(
    completedTurns.length,
    2,
    "initial and same-thread follow-up turns completed",
  );
  assert.ok(
    completedTurns.every((turn) => turn.status === "completed"),
    "both recorded turns have completed status",
  );
  assert.ok(
    ok("robot_observe").length >= 2,
    "worker observed the device in both turns",
  );
  assert.ok(ok("robot_act").length >= 1, "worker used native actions");
  assert.ok(
    webview("targets").length >= 1 && webview("inspect").length >= 1,
    "worker discovered and inspected the WebView",
  );
  assert.ok(ok("robot_logs").length >= 1, "worker inspected logs");
  assert.ok(
    webview("setCss").length >= 1 && webview("resetCss").length >= 1,
    "worker applied and reset CSS",
  );

  const cssTool = webview("setCss")[0];
  const cssStart = recordedTools.indexOf(cssTool);
  const cssEnd = recordedTools.findIndex(
    (tool, index) =>
      index > cssStart &&
      tool.name === "robot_webview" &&
      (tool.args as any)?.operation === "resetCss",
  );
  const painted = recordedTools
    .slice(cssStart + 1, cssEnd)
    .filter((tool) => tool.success && tool.image?.actualPng);
  assert.ok(
    cssTool.beforeImage &&
      painted.some(
        (tool) => tool.image!.sha256 !== cssTool.beforeImage!.sha256,
      ),
    "delayed screenshot visibly differs after CSS",
  );
  const computed = recordedTools
    .slice(cssStart + 1, cssEnd)
    .find(hasLiveCssEvidence);
  assert.ok(computed, "computed state confirms live CSS");
  assert.match(
    computedOutlineColor(computed),
    /255\s*,\s*0\s*,\s*255/,
    "computed outline is magenta",
  );
  const resetIndex = recordedTools.indexOf(webview("resetCss")[0]);
  assert.ok(
    recordedTools.slice(resetIndex + 1).some((tool) => {
      const result = (tool.details as any)?.result;
      return (
        tool.name === "robot_webview" &&
        (tool.args as any)?.operation === "evaluate" &&
        (result === true || result?.liveStylesheetPresence === false)
      );
    }),
    "computed state confirms CSS reset",
  );
  assert.ok(
    recordedTools.some(
      (tool) =>
        tool.name === "robot_webview" &&
        (tool.args as any)?.operation === "evaluate" &&
        String((tool.args as any)?.script).includes("window.close"),
    ),
    "worker requested checkout close",
  );
  assert.ok(
    recordedTools.some(hasNoCheckoutTargets),
    "worker verified no checkout target remains",
  );
  assert.ok(
    recordedEvents.some(isAgentMessage),
    "worker produced agent responses",
  );

  const report = {
    passed: true,
    verifiedFromRecordedLiveRun: true,
    platform,
    model: "gpt-5.6-luna",
    effort: "medium",
    completedAt: new Date().toISOString(),
    completedTurns,
    toolCalls: recordedTools.length,
    successfulToolCalls: recordedTools.filter((tool) => tool.success).length,
    actualPngToolResults: recordedTools.filter(
      (tool) => tool.success && tool.image?.actualPng,
    ).length,
    failedToolCalls: recordedTools
      .filter((tool) => !tool.success)
      .map((tool) => ({
        sequence: tool.sequence,
        name: tool.name,
        operation: (tool.args as any)?.operation,
        error: tool.error || tool.details,
      })),
    toolCounts: Object.fromEntries(
      [...new Set(recordedTools.map((tool) => tool.name))].map((name) => [
        name,
        recordedTools.filter((tool) => tool.name === name).length,
      ]),
    ),
    operations: recordedTools
      .filter((tool) => tool.name === "robot_webview")
      .map((tool) => ({
        operation: (tool.args as any)?.operation,
        success: tool.success,
      })),
    cssScreenshotChanged: true,
    cssVisualEvidence: painted.map((tool) => tool.image?.artifact),
  };
  await writeFile(
    join(artifactDir, "report.json"),
    JSON.stringify(report, null, 2),
  );
  console.log(`PASS_RECORDED ${JSON.stringify(report)}`);
  process.exit(0);
}

const events: RobotEvent[] = [];
const tools: ToolRecord[] = [];
let sequence = 0;
const startedAt = new Date().toISOString();

const session = new RobotSession({
  repoRoot,
  cacheDir,
  model: "gpt-5.6-luna",
  effort: "medium",
  abandonMs: 30 * 60_000,
  createAdapter: (requestedPlatform, hooks) => {
    assert.equal(requestedPlatform, platform);
    const createAdapter =
      requestedPlatform === "android" ? createAndroidAdapter : createIosAdapter;
    return createAdapter({ repoRoot, cacheDir, ...hooks });
  },
});

const unsubscribe = session.subscribe((event) => {
  events.push(event);
  const data = event.data as any;
  if (event.type === "tool" && data?.method === "item/tool/call") {
    console.log(`AGENT_TOOL ${String(data.params?.tool || "unknown")}`);
  } else if (event.type === "agent" && data?.method === "turn/completed") {
    console.log(
      `AGENT_TURN ${String(data.params?.turn?.status || "unknown")} ${String(data.params?.turn?.id || "")}`,
    );
  } else if (event.type === "progress") {
    console.log(`PROGRESS ${String(data?.message || "")}`);
  } else if (event.type === "error") {
    console.error(`AGENT_ERROR ${JSON.stringify(data)}`);
  }
});

const originalCall = session.call.bind(session);
session.call = async (
  name: string,
  args: unknown,
  signal: AbortSignal,
): Promise<DynamicToolCallResponse> => {
  const record: ToolRecord = {
    sequence: ++sequence,
    name,
    args,
    startedAt: new Date().toISOString(),
  };
  tools.push(record);
  try {
    const result = await originalCall(name, args, signal);
    record.completedAt = new Date().toISOString();
    record.success = result.success;
    const textItem = result.contentItems.find(
      (item) => item.type === "inputText",
    );
    if (textItem?.type === "inputText") {
      try {
        record.details = JSON.parse(textItem.text);
      } catch {
        record.details = textItem.text;
      }
    }
    if (result.success) {
      const imageItem = result.contentItems.find(
        (item) => item.type === "inputImage",
      );
      assert.ok(
        imageItem && imageItem.type === "inputImage",
        `${name} successful result includes inputImage`,
      );
      const match = /^data:image\/png;base64,(.+)$/s.exec(imageItem.imageUrl);
      assert.ok(match, `${name} inputImage uses a PNG data URL`);
      const png = Buffer.from(match[1], "base64");
      const actualPng =
        png.length > 8 &&
        png
          .subarray(0, 8)
          .equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
      assert.ok(actualPng, `${name} inputImage contains actual PNG bytes`);
      const artifact = `${String(record.sequence).padStart(2, "0")}-${safeName(name)}.png`;
      await writeFile(join(artifactDir, artifact), png);
      record.image = {
        artifact,
        bytes: png.length,
        sha256: sha256(png),
        actualPng,
      };

      if (name === "robot_webview" && (args as any)?.operation === "setCss") {
        const beforePath = (record.details as any)?.before?.imagePath;
        if (typeof beforePath === "string") {
          const before = await readFile(beforePath);
          const beforeArtifact = `${String(record.sequence).padStart(2, "0")}-robot_webview-before.png`;
          await copyFile(beforePath, join(artifactDir, beforeArtifact));
          record.beforeImage = {
            artifact: beforeArtifact,
            bytes: before.length,
            sha256: sha256(before),
          };
        }
      }
    }
    return result;
  } catch (error) {
    record.completedAt = new Date().toISOString();
    record.success = false;
    record.error = error instanceof Error ? error.message : String(error);
    throw error;
  }
};

const scenario = `Run a real visual acceptance scenario on the ${platform} Stash Native sample. Use only robot_* tools and do not edit repository files.

1. Observe the native sample and use native actions to enter https://test.stashpreview.com/ in accessibility ID card-url-field, hide the keyboard, and tap accessibility ID card-open-button.
2. Wait for the checkout WebView target whose URL begins with https://test.stashpreview.com. Do not enter payment details and do not attempt a payment.
3. Inspect the WebView DOM (body is sufficient), inspect recent console/network/native logs with robot_logs, and report what you found.
4. Apply conspicuous temporary CSS through robot_webview setCss: a 12px solid magenta inset outline around body, a pale yellow page background, and a fixed top-center banner reading STASH ROBOT CSS ACTIVE with a magenta background and white text at the highest z-index. Keep the banner inside the viewport with a body::before pseudo-element. Then call robot_webview evaluate with an async IIFE that waits for two requestAnimationFrame callbacks plus about 250ms before returning the computed outline width/color and live stylesheet presence. Use that delayed tool screenshot, plus a robot_observe screenshot if useful, to verify the banner and visual change.
5. Reset the temporary CSS with robot_webview resetCss. Verify with robot_webview evaluate that the element with id stash-robot-live-css is absent and use the returned screenshot as visual evidence.
6. Close the checkout without submitting anything. Prefer evaluating window.close(); if the WebView detaches before replying, treat that expected detach as evidence and use a native Back action if necessary. Observe the native screen to verify the checkout is closed.

Complete every step, then give a concise evidence-based result. Do not merely claim success: use the tools and screenshots.`;

let failure: unknown;
try {
  console.log(`START ${startedAt}`);
  await session.start(platform);
  console.log(`DEVICE ${JSON.stringify(session.snapshot().device)}`);

  let marker = lastEventId();
  await session.sendPrompt(scenario);
  const firstTurn = await waitForCompletedTurn(marker, 15 * 60_000);
  assert.equal(
    firstTurn.status,
    "completed",
    `first agent turn completed (received ${firstTurn.status})`,
  );

  marker = lastEventId();
  await session.sendPrompt(
    "Follow-up in the same conversation: re-observe the device, confirm the checkout remains closed and the temporary CSS is reset, and briefly relate this confirmation to the acceptance scenario you just completed. Do not reopen the checkout.",
  );
  const followUpTurn = await waitForCompletedTurn(marker, 5 * 60_000);
  assert.equal(
    followUpTurn.status,
    "completed",
    `follow-up agent turn completed (received ${followUpTurn.status})`,
  );

  assert.ok(
    successful("robot_observe").length >= 2,
    "agent used real observation tools in both turns",
  );
  assert.ok(successful("robot_act").length >= 1, "agent used a native action");
  assert.ok(
    successfulWebview("targets").length >= 1,
    "agent discovered WebView targets",
  );
  assert.ok(
    successfulWebview("inspect").length >= 1,
    "agent inspected the WebView DOM",
  );
  assert.ok(successful("robot_logs").length >= 1, "agent inspected logs");
  assert.ok(
    successfulWebview("setCss").length >= 1,
    "agent applied temporary CSS",
  );
  assert.ok(
    successfulWebview("resetCss").length >= 1,
    "agent reset temporary CSS",
  );
  assert.ok(
    successfulWebview("evaluate").length >= 2,
    "agent verified WebView state with JavaScript",
  );

  const cssTool = successfulWebview("setCss")[0];
  assert.ok(
    cssTool.image?.actualPng && cssTool.beforeImage,
    "CSS tool recorded before/after actual PNG evidence",
  );
  const cssStart = tools.indexOf(cssTool);
  const cssEnd = tools.findIndex(
    (tool, index) =>
      index > cssStart &&
      tool.name === "robot_webview" &&
      (tool.args as any)?.operation === "resetCss",
  );
  const paintedCssFrames = tools
    .slice(cssStart + 1, cssEnd < 0 ? undefined : cssEnd)
    .filter((tool) => tool.success && tool.image?.actualPng);
  assert.ok(
    paintedCssFrames.some(
      (tool) => tool.image!.sha256 !== cssTool.beforeImage!.sha256,
    ),
    "a screenshot after the delayed render visibly differs from the pre-CSS screenshot",
  );
  const computedCss = tools
    .slice(cssStart + 1, cssEnd < 0 ? undefined : cssEnd)
    .find(hasLiveCssEvidence);
  assert.ok(
    computedCss,
    "agent verified the live CSS through computed browser state",
  );
  assert.match(
    computedOutlineColor(computedCss),
    /255\s*,\s*0\s*,\s*255/,
    "computed outline is magenta",
  );
  assert.ok(events.some(isAgentMessage), "worker produced an agent response");

  const report = {
    passed: true,
    platform,
    model: "gpt-5.6-luna",
    effort: "medium",
    device: session.snapshot().device,
    startedAt,
    completedAt: new Date().toISOString(),
    completedTurns: events.filter(isCompletedTurn).map(turnSummary),
    toolCalls: tools.length,
    successfulToolCalls: tools.filter((tool) => tool.success).length,
    actualPngToolResults: tools.filter(
      (tool) => tool.success && tool.image?.actualPng,
    ).length,
    toolCounts: Object.fromEntries(
      [...new Set(tools.map((tool) => tool.name))].map((name) => [
        name,
        tools.filter((tool) => tool.name === name).length,
      ]),
    ),
    operations: tools
      .filter((tool) => tool.name === "robot_webview")
      .map((tool) => ({
        operation: (tool.args as any)?.operation,
        success: tool.success,
      })),
    cssScreenshotChanged: paintedCssFrames.some(
      (tool) => tool.image!.sha256 !== cssTool.beforeImage!.sha256,
    ),
    cssVisualEvidence: paintedCssFrames.map((tool) => tool.image?.artifact),
  };
  await writeArtifacts(report);
  console.log(`PASS ${JSON.stringify(report)}`);
} catch (error) {
  failure = error;
  const report = {
    passed: false,
    platform,
    model: "gpt-5.6-luna",
    effort: "medium",
    device: session.snapshot().device,
    startedAt,
    completedAt: new Date().toISOString(),
    error:
      error instanceof Error ? error.stack || error.message : String(error),
    toolCalls: tools.length,
    actualPngToolResults: tools.filter(
      (tool) => tool.success && tool.image?.actualPng,
    ).length,
  };
  await writeArtifacts(report).catch(() => {});
  console.error(`FAIL ${JSON.stringify(report)}`);
} finally {
  unsubscribe();
  await session
    .end()
    .catch((error) => console.error(`CLEANUP_ERROR ${String(error)}`));
  await writeFile(
    join(artifactDir, "events.json"),
    JSON.stringify(events.map(sanitizeEvent), null, 2),
  ).catch(() => {});
  await writeFile(
    join(artifactDir, "tools.json"),
    JSON.stringify(tools, null, 2),
  ).catch(() => {});
}

if (failure) throw failure;

function successful(name: string): ToolRecord[] {
  return tools.filter((tool) => tool.name === name && tool.success);
}

function successfulWebview(operation: string): ToolRecord[] {
  return tools.filter(
    (tool) =>
      tool.name === "robot_webview" &&
      (tool.args as any)?.operation === operation &&
      tool.success,
  );
}

function hasLiveCssEvidence(tool: ToolRecord): boolean {
  if (!tool.success || tool.name !== "robot_webview") return false;
  const operation = (tool.args as any)?.operation;
  const result = (tool.details as any)?.result;
  if (operation === "evaluate")
    return (
      result?.liveCss === true ||
      result?.liveStylesheetPresence === true ||
      result?.liveStylesheetPresent === true
    );
  if (
    operation !== "inspect" ||
    typeof result?.css !== "string" ||
    !result.css.includes("STASH ROBOT CSS ACTIVE")
  )
    return false;
  return (
    Array.isArray(result.elements) &&
    result.elements.some((element: any) =>
      /255\s*,\s*0\s*,\s*255/.test(String(element?.styles?.["outline-color"])),
    )
  );
}

function computedOutlineColor(tool: ToolRecord): string {
  const result = (tool.details as any)?.result;
  if ((tool.args as any)?.operation === "evaluate")
    return String(result?.outlineColor || "");
  const element = Array.isArray(result?.elements)
    ? result.elements.find((item: any) => item?.styles?.["outline-color"])
    : undefined;
  return String(element?.styles?.["outline-color"] || "");
}

function hasNoCheckoutTargets(tool: ToolRecord): boolean {
  if (!tool.success) return false;
  if (tool.name === "robot_observe")
    return (
      Array.isArray((tool.details as any)?.targets) &&
      (tool.details as any).targets.length === 0
    );
  return (
    tool.name === "robot_webview" &&
    (tool.args as any)?.operation === "targets" &&
    Array.isArray((tool.details as any)?.result) &&
    (tool.details as any).result.length === 0
  );
}

function lastEventId(): number {
  return events.at(-1)?.id ?? 0;
}

async function waitForCompletedTurn(
  afterId: number,
  timeoutMs: number,
): Promise<{ id: string; status: string }> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const event = events.find(
      (item) => item.id > afterId && isCompletedTurn(item),
    );
    if (event) return turnSummary(event);
    const request = events.find(
      (item) => item.id > afterId && item.type === "request",
    );
    if (request)
      throw new Error(
        `Agent requested unsupported user input: ${JSON.stringify(request.data)}`,
      );
    const agentError = events.find(
      (item) => item.id > afterId && item.type === "error",
    );
    if (agentError)
      throw new Error(`Agent error: ${JSON.stringify(agentError.data)}`);
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(
    `Timed out after ${timeoutMs}ms waiting for agent turn completion`,
  );
}

function isCompletedTurn(event: RobotEvent): boolean {
  return (
    event.type === "agent" && (event.data as any)?.method === "turn/completed"
  );
}

function turnSummary(event: RobotEvent): { id: string; status: string } {
  const turn = (event.data as any)?.params?.turn;
  return {
    id: String(turn?.id || ""),
    status: String(turn?.status || "unknown"),
  };
}

function isAgentMessage(event: RobotEvent): boolean {
  const method = String((event.data as any)?.method || "");
  return (
    event.type === "agent" &&
    (method === "item/agentMessage/delta" ||
      (method === "item/completed" &&
        (event.data as any)?.params?.item?.type === "agentMessage"))
  );
}

function sha256(value: Buffer): string {
  return createHash("sha256").update(value).digest("hex");
}

function safeName(value: string): string {
  return value.replace(/[^a-zA-Z0-9_-]+/g, "-");
}

function sanitizeEvent(event: RobotEvent): RobotEvent {
  return { ...event, data: sanitizeValue(event.data) };
}

function sanitizeValue(value: unknown): any {
  if (typeof value === "string" && value.startsWith("data:image/"))
    return `<image-data-url length=${value.length}>`;
  if (Array.isArray(value)) return value.map(sanitizeValue);
  if (value && typeof value === "object")
    return Object.fromEntries(
      Object.entries(value).map(([key, child]) => [key, sanitizeValue(child)]),
    );
  return value;
}

async function writeArtifacts(report: unknown): Promise<void> {
  await Promise.all([
    writeFile(
      join(artifactDir, "report.json"),
      JSON.stringify(report, null, 2),
    ),
    writeFile(
      join(artifactDir, "events.json"),
      JSON.stringify(events.map(sanitizeEvent), null, 2),
    ),
    writeFile(join(artifactDir, "tools.json"), JSON.stringify(tools, null, 2)),
  ]);
}
