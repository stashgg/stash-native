import { spawn, execFile } from "node:child_process";
import { createInterface } from "node:readline";
import { promisify } from "node:util";
import type { ChildProcessWithoutNullStreams } from "node:child_process";
import {
  CODEX_PROTOCOL_VERSION,
  isResponse,
  isServerRequest,
  type DynamicToolCallParams,
  type DynamicToolCallResponse,
  type DynamicToolFunctionSpec,
  type JsonRpcMessage,
  type JsonRpcResponse,
  type ThreadStartParams,
  type ToolRequestUserInputParams,
  type TurnStartParams,
  type TurnSteerParams,
  type UserInput,
} from "./protocol.js";

const execFileAsync = promisify(execFile);

export interface CodexEvent {
  type: "agent" | "tool" | "request" | "error" | "state";
  data: unknown;
}
export interface CodexToolHost {
  tools: DynamicToolFunctionSpec[];
  call(
    name: string,
    args: unknown,
    signal: AbortSignal,
  ): Promise<DynamicToolCallResponse>;
}
export interface CodexBridgeOptions {
  cwd: string;
  toolHost: CodexToolHost;
  onEvent: (event: CodexEvent) => void;
  model?: string;
  effort?: string;
  command?: string;
  args?: string[];
}

type Pending = {
  resolve: (value: unknown) => void;
  reject: (error: Error) => void;
};

export async function checkCodex(
  command = "codex",
): Promise<{ ok: boolean; detail: string }> {
  let bridge: CodexBridge | undefined;
  try {
    const { stdout } = await execFileAsync(command, ["--version"], {
      timeout: 5000,
    });
    const version = stdout.trim().match(/(\d+\.\d+\.\d+)/)?.[1];
    if (version !== CODEX_PROTOCOL_VERSION)
      return {
        ok: false,
        detail: `Codex ${CODEX_PROTOCOL_VERSION} required; found ${version || stdout.trim()}`,
      };
    bridge = new CodexBridge({
      cwd: process.cwd(),
      toolHost: {
        tools: [],
        call: async () => ({ contentItems: [], success: false }),
      },
      onEvent: () => {},
      command,
    });
    await bridge.open(false);
    const account = await bridge.request("account/read", {
      refreshToken: false,
    });
    const loggedIn = Boolean(
      (account as { account?: unknown } | null)?.account,
    );
    return {
      ok: loggedIn,
      detail: loggedIn
        ? `Codex ${version}; authenticated`
        : `Codex ${version}; run codex login`,
    };
  } catch (error) {
    return {
      ok: false,
      detail: error instanceof Error ? error.message : String(error),
    };
  } finally {
    await bridge?.close().catch(() => {});
  }
}

export class CodexBridge {
  private process?: ChildProcessWithoutNullStreams;
  private requestId = 0;
  private pending = new Map<string | number, Pending>();
  private pendingServer = new Map<
    string | number,
    { method: string; params: unknown }
  >();
  private threadId?: string;
  private threadFailure?: Error;
  private activeTurnId?: string;
  private completedTurns = new Set<string>();
  private activeToolControllers = new Map<string, AbortController>();
  private initialized = false;
  private closed = false;
  private closing = false;
  private openPromise?: Promise<void>;
  private threadPromise?: Promise<string>;
  private promptChain: Promise<void> = Promise.resolve();

  constructor(private readonly options: CodexBridgeOptions) {}

  get running(): boolean {
    return Boolean(this.process) && !this.closed;
  }
  get inTurn(): boolean {
    return Boolean(this.activeTurnId);
  }
  get currentThreadId(): string | undefined {
    return this.threadId;
  }
  get requests(): Array<{
    id: string | number;
    method: string;
    params: unknown;
  }> {
    return [...this.pendingServer].map(([id, value]) => ({ id, ...value }));
  }

  async open(validateVersion = true): Promise<void> {
    if (this.process) return;
    if (this.openPromise) return this.openPromise;
    this.openPromise = this.openInternal(validateVersion);
    try {
      await this.openPromise;
    } finally {
      this.openPromise = undefined;
    }
  }

  private async openInternal(validateVersion: boolean): Promise<void> {
    if (validateVersion) {
      const { stdout } = await execFileAsync(
        this.options.command ?? "codex",
        ["--version"],
        { timeout: 5000 },
      );
      const version = stdout.trim().match(/(\d+\.\d+\.\d+)/)?.[1];
      if (version !== CODEX_PROTOCOL_VERSION)
        throw new Error(
          `Codex ${CODEX_PROTOCOL_VERSION} required; found ${version || stdout.trim()}`,
        );
    }
    const child = spawn(
      this.options.command ?? "codex",
      this.options.args ?? ["app-server", "--stdio"],
      {
        cwd: this.options.cwd,
        stdio: ["pipe", "pipe", "pipe"],
        env: process.env,
      },
    );
    this.process = child;
    this.closed = false;
    this.closing = false;
    child.stdin.on("error", (error) => {
      if (!this.closing) this.failAll(error);
    });
    child.stderr.on("data", (chunk: Buffer) =>
      this.options.onEvent({
        type: "state",
        data: { source: "codex", message: chunk.toString().trim() },
      }),
    );
    createInterface({ input: child.stdout }).on("line", (line) => {
      try {
        void this.receive(JSON.parse(line) as JsonRpcMessage).catch((error) =>
          this.options.onEvent({
            type: "error",
            data: {
              message: error instanceof Error ? error.message : String(error),
            },
          }),
        );
      } catch (error) {
        this.options.onEvent({
          type: "error",
          data: {
            message: `Invalid app-server message: ${error instanceof Error ? error.message : error}`,
          },
        });
      }
    });
    child.once("error", (error) => this.failAll(error));
    child.once("exit", (code, signal) => {
      this.process = undefined;
      this.closed = true;
      this.failAll(new Error(`Codex app-server exited (${signal || code})`));
      if (!this.closing)
        this.options.onEvent({
          type: "error",
          data: { message: "Codex app-server exited", code, signal },
        });
    });
    await this.request("initialize", {
      clientInfo: {
        name: "stash_robot",
        title: "Ash",
        version: "0.1.0",
      },
      capabilities: {
        experimentalApi: true,
        mcpServerOpenaiFormElicitation: true,
      },
    });
    this.notify("initialized", {});
    this.initialized = true;
  }

  async startThread(): Promise<string> {
    if (this.threadFailure) throw this.threadFailure;
    if (this.threadId) return this.threadId;
    if (this.threadPromise) return this.threadPromise;
    this.threadPromise = this.startThreadInternal();
    try {
      return await this.threadPromise;
    } finally {
      this.threadPromise = undefined;
    }
  }

  private async startThreadInternal(): Promise<string> {
    await this.open();
    if (this.threadId) return this.threadId;
    const params: ThreadStartParams = {
      model: this.options.model,
      cwd: this.options.cwd,
      approvalPolicy: "on-request",
      sandbox: "read-only",
      serviceName: "stash-robot",
      dynamicTools: this.options.toolHost.tools,
      developerInstructions:
        "You operate the Stash Native sample only through robot_* tools. Observe after uncertainty. Every device interaction returns a real current screenshot. Repository access is for investigation only; do not edit source. Report results with screenshot and log evidence.",
    };
    const result = (await this.request("thread/start", params)) as {
      thread?: { id?: string; model?: string | null };
    };
    const id = result.thread?.id;
    if (!id) throw new Error("Codex did not return a thread id");
    try {
      await this.verifyImageCapability(
        result.thread?.model ?? this.options.model,
      );
    } catch (error) {
      this.threadId = id;
      this.threadFailure =
        error instanceof Error ? error : new Error(String(error));
      throw this.threadFailure;
    }
    this.threadId = id;
    return id;
  }

  async prompt(text: string, imageDataUrl?: string): Promise<void> {
    const operation = this.promptChain.then(() =>
      this.promptInternal(text, imageDataUrl),
    );
    this.promptChain = operation.catch(() => {});
    return operation;
  }

  private async promptInternal(
    text: string,
    imageDataUrl?: string,
  ): Promise<void> {
    const threadId = await this.startThread();
    const input: UserInput[] = [{ type: "text", text, text_elements: [] }];
    if (imageDataUrl)
      input.push({ type: "image", url: imageDataUrl, detail: "high" });
    if (this.activeTurnId) {
      const params: TurnSteerParams = {
        threadId,
        expectedTurnId: this.activeTurnId,
        input,
      };
      try {
        await this.request("turn/steer", params);
        this.options.onEvent({
          type: "agent",
          data: { kind: "steered", text },
        });
        return;
      } catch (error) {
        const detail = error instanceof Error ? error.message : String(error);
        if (
          !/(active turn|expected.?turn|turn.*(?:mismatch|not found|completed|inactive))/i.test(
            detail,
          )
        )
          throw error;
        this.activeTurnId = undefined;
      }
    }
    const params: TurnStartParams = {
      threadId,
      input,
      cwd: this.options.cwd,
      approvalPolicy: "on-request",
      sandboxPolicy: { type: "readOnly", networkAccess: false },
      model: this.options.model,
      effort: this.options.effort,
    };
    const result = (await this.request("turn/start", params)) as {
      turn?: { id?: string };
    };
    const returnedTurnId = result.turn?.id;
    if (!returnedTurnId) throw new Error("Codex did not return a turn id");
    this.activeTurnId = this.completedTurns.has(returnedTurnId)
      ? undefined
      : returnedTurnId;
  }

  async interrupt(cancelTools = true): Promise<void> {
    if (cancelTools)
      for (const controller of this.activeToolControllers.values())
        controller.abort(new Error("Agent interrupted"));
    if (!this.threadId || !this.activeTurnId) return;
    await this.request("turn/interrupt", {
      threadId: this.threadId,
      turnId: this.activeTurnId,
    });
    this.activeTurnId = undefined;
  }

  respond(requestId: string | number, result: unknown): void {
    const request = this.pendingServer.get(requestId);
    if (!request) throw new Error("Request is no longer pending");
    const response =
      result && typeof result === "object"
        ? (result as Record<string, unknown>)
        : {};
    if (
      request.method === "item/commandExecution/requestApproval" ||
      request.method === "item/fileChange/requestApproval"
    ) {
      if (response.decision !== "decline" && response.decision !== "cancel")
        throw new Error(
          "The stash-robot worker must remain read-only; permission escalation is disabled",
        );
    }
    if (request.method === "item/permissions/requestApproval") {
      if (JSON.stringify(response.permissions) !== "{}")
        throw new Error(
          "The stash-robot worker must remain read-only; permission escalation is disabled",
        );
    }
    this.pendingServer.delete(requestId);
    this.send({ id: requestId, result });
  }

  async close(): Promise<void> {
    if (this.closed) return;
    try {
      await this.interrupt();
    } catch {}
    this.closed = true;
    this.closing = true;
    const child = this.process;
    this.process = undefined;
    if (child && !child.killed) {
      const exited = new Promise<void>((resolve) =>
        child.once("exit", () => resolve()),
      );
      child.kill("SIGTERM");
      await Promise.race([
        exited,
        new Promise<void>((resolve) => setTimeout(resolve, 1500)),
      ]);
      if (child.exitCode === null && child.signalCode === null)
        child.kill("SIGKILL");
    }
    this.failAll(new Error("Codex bridge closed"));
  }

  request(method: string, params?: unknown): Promise<unknown> {
    if (!this.process)
      return Promise.reject(new Error("Codex app-server is not open"));
    const id = ++this.requestId;
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Codex ${method} request timed out`));
      }, 30_000);
      this.pending.set(id, {
        resolve: (value) => {
          clearTimeout(timeout);
          resolve(value);
        },
        reject: (error) => {
          clearTimeout(timeout);
          reject(error);
        },
      });
      this.send({ id, method, params });
    });
  }

  private notify(method: string, params?: unknown): void {
    this.send({ method, params });
  }
  private send(message: object): void {
    if (!this.process?.stdin.writable)
      throw new Error("Codex app-server is unavailable");
    this.process.stdin.write(`${JSON.stringify(message)}\n`);
  }

  private async receive(message: JsonRpcMessage): Promise<void> {
    if (isResponse(message)) {
      const pending = this.pending.get(message.id);
      if (!pending) return;
      this.pending.delete(message.id);
      if (message.error) pending.reject(new Error(message.error.message));
      else pending.resolve(message.result);
      return;
    }
    if (isServerRequest(message)) {
      if (message.method === "item/tool/call") {
        await this.runTool(message.id, message.params as DynamicToolCallParams);
      } else if (
        message.method === "account/chatgptAuthTokens/refresh" ||
        message.method === "attestation/generate"
      ) {
        this.send({
          id: message.id,
          error: { code: -32601, message: "Unsupported host request" },
        });
      } else {
        this.pendingServer.set(message.id, {
          method: message.method,
          params: message.params,
        });
        this.options.onEvent({
          type: "request",
          data: {
            id: message.id,
            method: message.method,
            params: message.params,
          },
        });
      }
      return;
    }
    const notification = message as { method: string; params?: any };
    if (notification.method === "turn/started")
      this.activeTurnId = notification.params?.turn?.id ?? this.activeTurnId;
    if (notification.method === "turn/completed") {
      const completedId = notification.params?.turn?.id;
      if (completedId) this.completedTurns.add(completedId);
      if (!completedId || this.activeTurnId === completedId)
        this.activeTurnId = undefined;
    }
    if (notification.method === "serverRequest/resolved") {
      const requestId = notification.params?.requestId;
      if (requestId !== undefined) this.pendingServer.delete(requestId);
    }
    const type =
      notification.method.includes("agentMessage") ||
      notification.method.startsWith("turn/")
        ? "agent"
        : notification.method.startsWith("item/")
          ? "tool"
          : notification.method === "error"
            ? "error"
            : "state";
    this.options.onEvent({
      type,
      data: { method: notification.method, params: notification.params },
    });
  }

  private async runTool(
    id: string | number,
    params: DynamicToolCallParams,
  ): Promise<void> {
    const controller = new AbortController();
    this.activeToolControllers.set(params.callId, controller);
    this.options.onEvent({
      type: "tool",
      data: { method: "item/tool/call", params },
    });
    try {
      const output = await this.options.toolHost.call(
        params.tool,
        params.arguments,
        controller.signal,
      );
      this.send({ id, result: output });
    } catch (error) {
      const output: DynamicToolCallResponse = {
        success: false,
        contentItems: [
          {
            type: "inputText",
            text: error instanceof Error ? error.message : String(error),
          },
        ],
      };
      this.send({ id, result: output });
    } finally {
      this.activeToolControllers.delete(params.callId);
    }
  }

  private async verifyImageCapability(
    effectiveModel?: string | null,
  ): Promise<void> {
    if (!effectiveModel) return;
    let result: { data?: Array<Record<string, unknown>> };
    try {
      result = (await this.request("model/list", {
        limit: 100,
        includeHidden: false,
      })) as { data?: Array<Record<string, unknown>> };
    } catch (error) {
      this.options.onEvent({
        type: "state",
        data: {
          source: "codex",
          message: `Image capability check unavailable: ${error instanceof Error ? error.message : error}`,
        },
      });
      return;
    }
    const model = result.data?.find(
      (item) => item.id === effectiveModel || item.model === effectiveModel,
    );
    const modalities = model?.inputModalities ?? model?.input_modalities;
    if (!model)
      throw new Error(
        `Could not verify image input for model ${effectiveModel}`,
      );
    if (!Array.isArray(modalities) || !modalities.includes("image"))
      throw new Error(`Model ${effectiveModel} does not accept image input`);
  }

  private failAll(error: Error): void {
    for (const pending of this.pending.values()) pending.reject(error);
    this.pending.clear();
  }
}
