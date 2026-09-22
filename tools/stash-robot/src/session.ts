import { mkdir, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import type {
  Check,
  DebuggerStatus,
  DeviceAdapter,
  DeviceInfo,
  DoctorReport,
  LogEntry,
  Observation,
  Platform,
  RobotAction,
  RobotEvent,
  StartOptions,
} from "./contracts.js";
import { PriorityActionQueue } from "./queue.js";
import {
  CodexBridge,
  type CodexBridgeOptions,
  type CodexEvent,
  type CodexToolHost,
} from "./codex.js";
import type {
  DynamicToolCallResponse,
  DynamicToolFunctionSpec,
  JsonValue,
} from "./protocol.js";
import { record, robotAction, string } from "./validation.js";

export type SessionPhase =
  | "selecting"
  | "starting"
  | "ready"
  | "stopping"
  | "ended"
  | "error";
export type ControlMode = "agent" | "manual" | "stopped";
export interface AdapterHooks {
  onLog(entry: LogEntry): void;
  onProgress(message: string): void;
}
export interface SessionOptions {
  repoRoot: string;
  cacheDir: string;
  createAdapter(platform: Platform, hooks: AdapterHooks): DeviceAdapter;
  model?: string;
  effort?: string;
  scenario?: string;
  enableAgent?: boolean;
  abandonMs?: number;
  prerequisiteChecks?: () => Promise<Check[]>;
  createCodexBridge?: (options: CodexBridgeOptions) => CodexBridge;
}
export interface SessionSnapshot {
  id: string;
  phase: SessionPhase;
  control: ControlMode;
  platform?: Platform;
  device?: DeviceInfo;
  observation?: Observation;
  doctors: Partial<Record<Platform, DoctorReport>>;
  logs: LogEntry[];
  requests: Array<{ id: string | number; method: string; params: unknown }>;
  manualHistory: string[];
  error?: string;
  browserConnections: number;
  activeCss?: string;
  debugger?: DebuggerStatus;
}
interface FrameMeta {
  observation: Observation;
  revision: number;
  orientation: string;
  dataUrl: string;
}
type Listener = (event: RobotEvent) => void;
const MAX_RETAINED_FRAMES = 30;

const tool = (
  name: string,
  description: string,
  properties: Record<string, unknown>,
  required: string[] = [],
): DynamicToolFunctionSpec => ({
  type: "function",
  name,
  description,
  inputSchema: {
    type: "object",
    properties,
    required,
    additionalProperties: false,
  } as JsonValue,
});

export const ROBOT_TOOLS: DynamicToolFunctionSpec[] = [
  tool(
    "robot_observe",
    "Capture the current device screen and accessibility/WebView context. Returns an actual screenshot.",
    {},
  ),
  tool(
    "robot_act",
    "Perform one native device action. Coordinates are screen fractions and require the observed frameId. Returns the resulting actual screenshot.",
    {
      action: {
        oneOf: [
          {
            type: "object",
            properties: {
              type: { const: "tap" },
              x: { type: "number", minimum: 0, maximum: 1 },
              y: { type: "number", minimum: 0, maximum: 1 },
              frameId: { type: "string" },
            },
            required: ["type", "x", "y", "frameId"],
            additionalProperties: false,
          },
          {
            type: "object",
            properties: {
              type: { const: "swipe" },
              fromX: { type: "number", minimum: 0, maximum: 1 },
              fromY: { type: "number", minimum: 0, maximum: 1 },
              toX: { type: "number", minimum: 0, maximum: 1 },
              toY: { type: "number", minimum: 0, maximum: 1 },
              durationMs: { type: "number" },
              frameId: { type: "string" },
            },
            required: ["type", "fromX", "fromY", "toX", "toY", "frameId"],
            additionalProperties: false,
          },
          {
            type: "object",
            properties: {
              type: { const: "tapElement" },
              selector: { type: "string" },
            },
            required: ["type", "selector"],
            additionalProperties: false,
          },
          {
            type: "object",
            properties: {
              type: { const: "type" },
              text: { type: "string" },
              selector: { type: "string" },
            },
            required: ["type", "text"],
            additionalProperties: false,
          },
          {
            type: "object",
            properties: { type: { enum: ["back", "hideKeyboard", "home"] } },
            required: ["type"],
            additionalProperties: false,
          },
          {
            type: "object",
            properties: {
              type: { const: "rotate" },
              orientation: { enum: ["portrait", "landscape"] },
            },
            required: ["type", "orientation"],
            additionalProperties: false,
          },
        ],
      },
    },
    ["action"],
  ),
  tool(
    "robot_webview",
    "Inspect or temporarily modify the selected inspectable WebView, then return an actual screenshot.",
    {
      operation: {
        type: "string",
        enum: [
          "targets",
          "inspect",
          "evaluate",
          "setCss",
          "resetCss",
          "reload",
        ],
      },
      targetId: { type: "string" },
      selector: { type: "string" },
      script: { type: "string" },
      css: { type: "string" },
    },
    ["operation"],
  ),
  tool(
    "robot_logs",
    "Read recent native, browser, build, driver, network, and harness logs with a current actual screenshot.",
    {
      source: {
        type: "string",
        enum: ["native", "console", "network", "build", "driver", "harness"],
      },
      limit: { type: "number" },
    },
  ),
  tool(
    "robot_app",
    "Restart or rebuild the sample app and return its actual resulting screenshot.",
    { operation: { type: "string", enum: ["restart", "rebuild"] } },
    ["operation"],
  ),
];

export class RobotSession implements CodexToolHost {
  readonly id = randomUUID();
  readonly tools = ROBOT_TOOLS;
  private phase: SessionPhase = "selecting";
  private control: ControlMode = "agent";
  private adapter?: DeviceAdapter;
  private platform?: Platform;
  private device?: DeviceInfo;
  private queue = new PriorityActionQueue();
  private bridge?: CodexBridge;
  private eventId = 0;
  private events: RobotEvent[] = [];
  private listeners = new Set<Listener>();
  private doctors: Partial<Record<Platform, DoctorReport>> = {};
  private logs: LogEntry[] = [];
  private frames = new Map<string, FrameMeta>();
  private currentFrame?: FrameMeta;
  private revision = 0;
  private frameSequence = 0;
  private previewTimer?: NodeJS.Timeout;
  private previewInFlight = false;
  private browserConnections = 0;
  private abandonTimer?: NodeJS.Timeout;
  private manualHistory: string[] = [];
  private error?: string;
  private activeCss = "";
  private cssTarget?: { id: string; url: string };
  private ending?: Promise<void>;
  private lifecycleEpoch = 0;
  private stoppedAdapters = new WeakMap<DeviceAdapter, Promise<void>>();
  private pinnedFrames = new Set<string>();
  private pendingScenarios: string[] = [];

  constructor(private readonly options: SessionOptions) {
    if (options.scenario) this.pendingScenarios.push(options.scenario);
    this.abandonTimer = setTimeout(
      () => void this.end(),
      options.abandonMs ?? 300_000,
    );
  }

  snapshot(): SessionSnapshot {
    return {
      id: this.id,
      phase: this.phase,
      control: this.control,
      platform: this.platform,
      device: this.device,
      observation: this.currentFrame?.observation,
      doctors: this.doctors,
      logs: this.logs.slice(-300),
      requests: this.bridge?.requests ?? [],
      manualHistory: [...this.manualHistory],
      error: this.error,
      browserConnections: this.browserConnections,
      activeCss: this.activeCss,
      debugger: this.adapter?.webview.status?.(),
    };
  }

  async doctor(
    platforms: Platform[] = ["android", "ios"],
  ): Promise<Partial<Record<Platform, DoctorReport>>> {
    const sharedChecks =
      (await this.options
        .prerequisiteChecks?.()
        .catch((error) => [
          { name: "Harness", ok: false, detail: message(error) },
        ])) ?? [];
    await Promise.all(
      platforms.map(async (platform) => {
        const adapter = this.options.createAdapter(platform, this.hooks());
        try {
          const report = await adapter.doctor();
          report.checks = [...sharedChecks, ...report.checks];
          report.ready =
            report.ready && sharedChecks.every((check) => check.ok);
          this.doctors[platform] = report;
        } catch (error) {
          this.doctors[platform] = {
            platform,
            ready: false,
            checks: [{ name: "adapter", ok: false, detail: message(error) }],
            devices: [],
          };
        } finally {
          await adapter.stop().catch(() => {});
        }
      }),
    );
    this.emit("state", this.snapshot());
    return this.doctors;
  }

  async start(
    platform: Platform,
    startOptions: StartOptions = {},
  ): Promise<void> {
    this.assertCanStart(platform);
    const epoch = ++this.lifecycleEpoch;
    this.phase = "starting";
    this.platform = platform;
    this.error = undefined;
    this.emit("state", this.snapshot());
    const adapter = this.options.createAdapter(platform, this.hooks());
    this.adapter = adapter;
    try {
      const device = await this.queue.run(
        (signal) => adapter.start(startOptions, signal),
        { priority: 100, tag: "lifecycle" },
      );
      if (epoch !== this.lifecycleEpoch || this.phase !== "starting")
        throw new Error("Session startup was cancelled");
      this.device = device;
      this.phase = "ready";
      this.control = "agent";
      this.revision++;
      await this.observe("system");
      this.startPreviews();
      this.emit("state", this.snapshot());
    } catch (error) {
      if (epoch !== this.lifecycleEpoch || this.isEnding()) throw error;
      this.queue.cancelAll();
      await this.queue.idle().catch(() => {});
      await this.stopAdapter(adapter);
      if (this.adapter === adapter) this.adapter = undefined;
      this.device = undefined;
      this.phase = "error";
      this.error = message(error);
      this.emit("state", this.snapshot());
      this.emit("error", { message: this.error });
      throw error;
    }
    await this.dispatchPendingScenarios();
  }

  assertCanStart(platform: Platform, requireDoctor = false): void {
    if (this.phase !== "selecting" && this.phase !== "error")
      throw new Error(`Cannot start from ${this.phase}`);
    const report = this.doctors[platform];
    if (requireDoctor && !report)
      throw new Error(`${platform} prerequisite checks are still running`);
    if (report && !report.ready)
      throw new Error(`${platform} prerequisites are not ready`);
  }

  async queueScenario(text: string): Promise<void> {
    if (this.phase === "stopping" || this.phase === "ended")
      throw new Error("Session is ending");
    if (this.phase === "ready") {
      await this.sendPrompt(text);
      return;
    }
    this.pendingScenarios.push(text);
  }

  async observe(
    source: "agent" | "manual" | "system" = "agent",
    signal?: AbortSignal,
  ): Promise<FrameMeta> {
    const adapter = this.requireReady();
    const tag =
      source === "agent" ? "agent" : source === "manual" ? "manual" : "preview";
    return this.queue.run(
      async (queueSignal) => {
        const capture = await adapter.capture(queueSignal);
        const frameId = `${this.revision}-${++this.frameSequence}-${randomUUID().slice(0, 8)}`;
        const capturedAt = new Date().toISOString();
        const frameDir = this.frameDirectory();
        await mkdir(frameDir, { recursive: true, mode: 0o700 });
        const imagePath = join(frameDir, `${frameId}.png`);
        await writeFile(imagePath, capture.png, { mode: 0o600 });
        let hierarchy: string | undefined;
        let targets;
        await adapter.webview
          .pollLogs?.(queueSignal)
          .catch((error) =>
            this.log(
              "harness",
              "warn",
              `WebView logging failed: ${message(error)}`,
            ),
          );
        if (source !== "system" || this.activeCss) {
          if (source !== "system")
            hierarchy = await adapter
              .hierarchy(queueSignal)
              .catch((error) => `Hierarchy unavailable: ${message(error)}`);
          targets = await adapter.webview
            .listTargets(queueSignal)
            .catch((error) => {
              this.log(
                "harness",
                "warn",
                `WebView discovery failed: ${message(error)}`,
              );
              return [];
            });
          if (this.cssTarget) {
            const current = targets.find(
              (target) => target.id === this.cssTarget!.id,
            );
            if (!current || current.url !== this.cssTarget.url) {
              this.activeCss = "";
              this.cssTarget = undefined;
            } else if (this.activeCss) {
              const inspection = await adapter.webview
                .inspect(current.id, ":root", queueSignal)
                .catch(() => undefined);
              const installedCss =
                inspection && typeof inspection === "object"
                  ? (inspection as { css?: unknown }).css
                  : undefined;
              if (
                typeof installedCss === "string" &&
                installedCss !== this.activeCss
              ) {
                this.activeCss = "";
                this.cssTarget = undefined;
              }
            }
          }
        }
        const orientation =
          capture.width >= capture.height ? "landscape" : "portrait";
        const observation: Observation = {
          frameId,
          capturedAt,
          width: capture.width,
          height: capture.height,
          logicalWidth: capture.logicalWidth,
          logicalHeight: capture.logicalHeight,
          orientation,
          imagePath,
          imageUrl: `/api/frames/${encodeURIComponent(frameId)}.png`,
          hierarchy,
          targets,
          debugger: adapter.webview.status?.(),
          activeCss: this.activeCss,
        };
        const meta: FrameMeta = {
          observation,
          revision: this.revision,
          orientation,
          dataUrl: `data:image/png;base64,${capture.png.toString("base64")}`,
        };
        this.currentFrame = meta;
        this.frames.set(frameId, meta);
        await this.pruneFrames();
        this.emit("frame", observation);
        return meta;
      },
      { priority: source === "system" ? -10 : 20, signal, tag },
    );
  }

  async act(
    actionInput: unknown,
    source: "agent" | "manual",
    signal?: AbortSignal,
  ): Promise<FrameMeta> {
    const adapter = this.requireReady();
    if (this.control !== source)
      throw new Error(`${source} control is not active`);
    const action = robotAction(actionInput);
    await this.queue.run(
      async (queueSignal) => {
        if (this.control !== source)
          throw new Error(`${source} control is no longer active`);
        this.validateFrame(action);
        try {
          await adapter.act(action, queueSignal);
        } finally {
          this.revision++;
        }
      },
      { priority: 100, signal, tag: source },
    );
    if (this.control !== source)
      throw new Error(
        `${source} control ended after the dispatched action; observe before continuing`,
      );
    if (source === "manual") {
      this.manualHistory.push(
        `${new Date().toISOString()} ${describeAction(action)}`,
      );
      this.manualHistory = this.manualHistory.slice(-50);
      this.emit("state", this.snapshot());
    }
    return this.observe(source, signal);
  }

  async app(
    operation: "restart" | "rebuild",
    source: "agent" | "manual",
    signal?: AbortSignal,
  ): Promise<FrameMeta> {
    const adapter = this.requireReady();
    if (this.control !== source)
      throw new Error(`${source} control is not active`);
    await this.queue.run(
      async (queueSignal) => {
        if (this.control !== source)
          throw new Error(`${source} control is no longer active`);
        try {
          if (operation === "restart") await adapter.restart(queueSignal);
          else await adapter.rebuild(queueSignal);
        } finally {
          this.revision++;
          this.activeCss = "";
          this.cssTarget = undefined;
        }
      },
      { priority: 100, signal, tag: source },
    );
    if (this.control !== source)
      throw new Error(
        `${source} control ended after the dispatched operation; observe before continuing`,
      );
    if (source === "manual")
      this.manualHistory.push(`${new Date().toISOString()} app ${operation}`);
    return this.observe(source, signal);
  }

  async webview(
    argsValue: unknown,
    source: "agent" | "manual",
    signal?: AbortSignal,
  ): Promise<{ result: unknown; before?: Observation; after: FrameMeta }> {
    const adapter = this.requireReady();
    if (this.control !== source)
      throw new Error(`${source} control is not active`);
    const args = record(argsValue, "webview arguments");
    const operation = string(args.operation, "operation")!;
    const targetId = string(args.targetId, "targetId", { optional: true });
    const before =
      operation === "setCss" || operation === "resetCss"
        ? (await this.observe(source, signal)).observation
        : undefined;
    const mutates =
      operation === "evaluate" ||
      operation === "setCss" ||
      operation === "resetCss" ||
      operation === "reload";
    const result = await this.queue.run(
      async (queueSignal) => {
        if (this.control !== source)
          throw new Error(`${source} control is no longer active`);
        try {
          switch (operation) {
            case "targets":
              return adapter.webview.listTargets(queueSignal);
            case "inspect":
              return adapter.webview.inspect(
                targetId,
                string(args.selector, "selector", { optional: true }),
                queueSignal,
              );
            case "evaluate":
              return adapter.webview.evaluate(
                string(args.script, "script", { max: 200_000 })!,
                targetId,
                queueSignal,
              );
            case "setCss": {
              const css = string(args.css, "css", { max: 200_000 })!;
              const targets = await adapter.webview.listTargets(queueSignal);
              const selected = targetId
                ? targets.find((target) => target.id === targetId)
                : targets[0];
              const value = await adapter.webview.setCss(
                css,
                targetId,
                queueSignal,
              );
              this.activeCss = css;
              this.cssTarget = selected
                ? { id: selected.id, url: selected.url }
                : undefined;
              return value;
            }
            case "resetCss": {
              const value = await adapter.webview.resetCss(
                targetId,
                queueSignal,
              );
              this.activeCss = "";
              this.cssTarget = undefined;
              return value;
            }
            case "reload":
              await adapter.webview.reload(targetId, queueSignal);
              this.activeCss = "";
              this.cssTarget = undefined;
              return { reloaded: true };
            default:
              throw new Error(`Unknown WebView operation: ${operation}`);
          }
        } finally {
          if (mutates) this.revision++;
        }
      },
      { priority: 80, signal, tag: source },
    );
    if (this.control !== source)
      throw new Error(
        `${source} control ended after the dispatched operation; observe before continuing`,
      );
    if (source === "manual")
      this.manualHistory.push(
        `${new Date().toISOString()} webview ${operation}`,
      );
    const after = await this.observe(source, signal);
    if (before) {
      this.pinnedFrames = new Set([before.frameId, after.observation.frameId]);
      await this.pruneFrames();
    }
    this.emit("tool", {
      kind: "webview",
      operation,
      targetId,
      result,
      before,
      after: after.observation,
    });
    return { result, before, after };
  }

  async takeControl(): Promise<FrameMeta> {
    if (this.control === "manual") return this.observe("manual");
    this.control = "stopped";
    this.emit("state", this.snapshot());
    await this.bridge
      ?.interrupt(false)
      .catch((error) =>
        this.log(
          "harness",
          "warn",
          `Agent interrupt failed: ${message(error)}`,
        ),
      );
    this.queue.cancelPending("agent");
    await this.queue.idle();
    this.control = "manual";
    this.emit("state", this.snapshot());
    return this.observe("manual");
  }

  async resumeAgent(): Promise<void> {
    const frame = await this.observe("manual");
    this.control = "agent";
    this.emit("state", this.snapshot());
    const history =
      this.manualHistory.slice(-20).join("\n") ||
      "No manual actions were recorded.";
    await this.sendPrompt(
      `Manual control is finished. Re-observe the current state and continue. Recent manual actions:\n${history}`,
      frame.dataUrl,
    );
  }

  async stopAgent(): Promise<void> {
    this.control = "stopped";
    this.emit("state", this.snapshot());
    this.queue.cancelPending("agent");
    await this.bridge?.interrupt().catch(() => {});
  }

  async sendPrompt(text: string, imageDataUrl?: string): Promise<void> {
    if (this.phase !== "ready") throw new Error("Device is not ready");
    if (this.control === "manual")
      throw new Error("Resume the agent before prompting");
    if (!this.bridge) {
      if (this.options.enableAgent === false)
        throw new Error("Agent is disabled for this session");
      const bridgeOptions: CodexBridgeOptions = {
        cwd: this.options.repoRoot,
        toolHost: this,
        model: this.options.model,
        effort: this.options.effort,
        onEvent: (event) => this.onCodexEvent(event),
      };
      this.bridge =
        this.options.createCodexBridge?.(bridgeOptions) ??
        new CodexBridge(bridgeOptions);
    }
    this.control = "agent";
    const image = imageDataUrl ?? (await this.observe("agent")).dataUrl;
    this.emit("agent", { kind: "user", text });
    await this.bridge.prompt(text, image);
  }

  respondToAgent(id: string | number, result: unknown): void {
    if (!this.bridge) throw new Error("Agent is not running");
    this.bridge.respond(id, result);
  }

  async call(
    name: string,
    args: unknown,
    signal: AbortSignal,
  ): Promise<DynamicToolCallResponse> {
    try {
      return await this.executeTool(name, args, signal);
    } catch (error) {
      const contentItems: DynamicToolCallResponse["contentItems"] = [
        {
          type: "inputText",
          text: `Operation failed; completion may be uncertain. Do not replay it without inspecting the current state. ${message(error)}`,
        },
      ];
      if (
        !signal.aborted &&
        this.phase === "ready" &&
        this.control === "agent"
      ) {
        try {
          const frame = await this.observe("agent");
          contentItems.push(
            {
              type: "inputText",
              text: JSON.stringify({ observation: frame.observation }),
            },
            { type: "inputImage", imageUrl: frame.dataUrl },
          );
        } catch (captureError) {
          contentItems.push({
            type: "inputText",
            text: `Fresh observation unavailable: ${message(captureError)}. Observe before continuing.`,
          });
        }
      }
      return { success: false, contentItems };
    }
  }

  private async executeTool(
    name: string,
    args: unknown,
    signal: AbortSignal,
  ): Promise<DynamicToolCallResponse> {
    let frame: FrameMeta;
    let details: unknown;
    switch (name) {
      case "robot_observe":
        frame = await this.observe("agent", signal);
        details = frame.observation;
        break;
      case "robot_act": {
        const body = record(args);
        frame = await this.act(body.action, "agent", signal);
        details = frame.observation;
        break;
      }
      case "robot_webview": {
        const value = await this.webview(args, "agent", signal);
        frame = value.after;
        details = {
          result: value.result,
          before: value.before,
          after: frame.observation,
        };
        break;
      }
      case "robot_logs": {
        const body = record(args);
        const source =
          typeof body.source === "string" ? body.source : undefined;
        const limit = Math.max(1, Math.min(1000, Number(body.limit) || 200));
        frame = await this.observe("agent", signal);
        const logs = this.logs
          .filter((entry) => !source || entry.source === source)
          .slice(-limit);
        details = { logs, observation: frame.observation };
        break;
      }
      case "robot_app": {
        const body = record(args);
        const operation = body.operation;
        if (operation !== "restart" && operation !== "rebuild")
          throw new Error("operation must be restart or rebuild");
        frame = await this.app(operation, "agent", signal);
        details = frame.observation;
        break;
      }
      default:
        throw new Error(`Unknown robot tool: ${name}`);
    }
    return {
      success: true,
      contentItems: [
        { type: "inputText", text: JSON.stringify(details) },
        { type: "inputImage", imageUrl: frame.dataUrl },
      ],
    };
  }

  connect(listener: Listener, lastEventId = 0): () => void {
    if (this.abandonTimer) clearTimeout(this.abandonTimer);
    this.browserConnections++;
    this.listeners.add(listener);
    for (const event of this.events)
      if (
        event.id > lastEventId &&
        (event.type !== "frame" ||
          this.frames.has((event.data as Observation).frameId))
      )
        listener(event);
    this.emit("state", this.snapshot());
    if (this.browserConnections === 1 && this.phase === "ready") {
      this.revision++;
      void this.observe("system").catch((error) =>
        this.log(
          "harness",
          "warn",
          `Reconnect observation failed: ${message(error)}`,
        ),
      );
    }
    return () => {
      if (!this.listeners.delete(listener)) return;
      this.browserConnections = Math.max(0, this.browserConnections - 1);
      if (!this.browserConnections && this.phase !== "ended")
        this.abandonTimer = setTimeout(
          () => void this.end(),
          this.options.abandonMs ?? 300_000,
        );
    };
  }

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  framePath(frameId: string): string | undefined {
    return /^[a-zA-Z0-9-]+$/.test(frameId) && this.frames.has(frameId)
      ? join(this.frameDirectory(), `${frameId}.png`)
      : undefined;
  }

  async end(): Promise<void> {
    return (this.ending ??= (async () => {
      this.lifecycleEpoch++;
      this.phase = "stopping";
      this.emit("state", this.snapshot());
      if (this.previewTimer) clearInterval(this.previewTimer);
      if (this.abandonTimer) clearTimeout(this.abandonTimer);
      const adapter = this.adapter;
      this.queue.cancelAll();
      await this.queue.idle().catch(() => {});
      await this.bridge?.close().catch(() => {});
      if (adapter) await this.stopAdapter(adapter);
      if (this.adapter === adapter) this.adapter = undefined;
      this.device = undefined;
      await rm(this.frameDirectory(), { recursive: true, force: true });
      this.frames.clear();
      this.pinnedFrames.clear();
      this.currentFrame = undefined;
      this.phase = "ended";
      this.control = "stopped";
      this.emit("state", this.snapshot());
    })());
  }

  private startPreviews(): void {
    if (this.previewTimer) clearInterval(this.previewTimer);
    this.previewTimer = setInterval(() => {
      if (
        !this.browserConnections ||
        this.previewInFlight ||
        this.queue.busy ||
        this.phase !== "ready"
      )
        return;
      this.previewInFlight = true;
      void this.observe("system")
        .catch((error) =>
          this.log(
            "harness",
            "warn",
            `Screenshot refresh failed: ${message(error)}`,
          ),
        )
        .finally(() => {
          this.previewInFlight = false;
        });
    }, 1000);
  }
  private validateFrame(action: RobotAction): void {
    if (action.type !== "tap" && action.type !== "swipe") return;
    const frame = this.frames.get(action.frameId);
    if (!frame) throw new Error("Frame is unknown or expired; observe again");
    if (
      frame.revision !== this.revision ||
      Date.now() - Date.parse(frame.observation.capturedAt) > 30_000 ||
      frame.orientation !== this.currentFrame?.orientation
    )
      throw new Error("Frame is stale; observe again before using coordinates");
  }
  private requireReady(): DeviceAdapter {
    if (this.phase !== "ready" || !this.adapter)
      throw new Error("Device is not ready");
    return this.adapter;
  }
  private isEnding(): boolean {
    return (
      this.phase === "stopping" ||
      this.phase === "ended" ||
      Boolean(this.ending)
    );
  }
  private frameDirectory(): string {
    return join(this.options.cacheDir, "frames", this.id);
  }
  private async pruneFrames(): Promise<void> {
    const protectedFrames = new Set(this.pinnedFrames);
    if (this.currentFrame)
      protectedFrames.add(this.currentFrame.observation.frameId);
    while (this.frames.size > MAX_RETAINED_FRAMES) {
      const frameId = [...this.frames.keys()].find(
        (candidate) => !protectedFrames.has(candidate),
      );
      if (!frameId) return;
      const frame = this.frames.get(frameId)!;
      this.frames.delete(frameId);
      await rm(frame.observation.imagePath, { force: true }).catch(() => {});
    }
  }
  private stopAdapter(adapter: DeviceAdapter): Promise<void> {
    const existing = this.stoppedAdapters.get(adapter);
    if (existing) return existing;
    const stopping = (async () => {
      await adapter.webview
        .stop()
        .catch((error) =>
          this.log(
            "harness",
            "warn",
            `WebView cleanup failed: ${message(error)}`,
          ),
        );
      await adapter
        .stop()
        .catch((error) =>
          this.log(
            "harness",
            "warn",
            `Device cleanup failed: ${message(error)}`,
          ),
        );
    })();
    this.stoppedAdapters.set(adapter, stopping);
    return stopping;
  }
  private async dispatchPendingScenarios(): Promise<void> {
    if (this.options.enableAgent === false) return;
    const scenarios = this.pendingScenarios.splice(0);
    for (const scenario of scenarios) {
      if (this.phase !== "ready") return;
      try {
        await this.sendPrompt(scenario);
      } catch (error) {
        if (this.phase !== "ready") return;
        const detail = message(error);
        this.log("harness", "error", `Initial scenario failed: ${detail}`);
        this.emit("error", { message: detail, source: "agent" });
      }
    }
  }
  private hooks(): AdapterHooks {
    return {
      onLog: (entry) => {
        this.logs.push(entry);
        this.logs = this.logs.slice(-5000);
        this.emit("log", entry);
      },
      onProgress: (message) => {
        this.log("build", "info", message);
        this.emit("progress", { message });
      },
    };
  }
  private log(source: LogEntry["source"], level: string, text: string): void {
    this.hooks().onLog({
      timestamp: new Date().toISOString(),
      source,
      level,
      message: text,
    });
  }
  private onCodexEvent(event: CodexEvent): void {
    this.emit(event.type === "state" ? "agent" : event.type, event.data);
  }
  private emit(type: RobotEvent["type"], data: unknown): void {
    const event: RobotEvent = {
      id: ++this.eventId,
      timestamp: new Date().toISOString(),
      type,
      data,
    };
    this.events.push(event);
    this.events = this.events.slice(-2000);
    for (const listener of this.listeners) listener(event);
  }
}

function message(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
function describeAction(action: RobotAction): string {
  switch (action.type) {
    case "tap":
      return `tap ${action.x.toFixed(3)},${action.y.toFixed(3)}`;
    case "swipe":
      return `swipe ${action.fromX.toFixed(3)},${action.fromY.toFixed(3)} to ${action.toX.toFixed(3)},${action.toY.toFixed(3)}`;
    case "type":
      return `type ${JSON.stringify(action.text)}`;
    default:
      return action.type;
  }
}
