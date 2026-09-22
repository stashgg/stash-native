import WebSocket from "ws";
import type { LogEntry, WebViewAdapter, WebViewTarget } from "../contracts.js";
import { cssScript, inspectScript, resetCssScript } from "../web-scripts.js";

type CdpSocket = {
  socket: WebSocket;
  nextId: number;
  pending: Map<
    number,
    { resolve: (value: unknown) => void; reject: (error: Error) => void }
  >;
  close: () => void;
};

type TargetRecord = WebViewTarget & { wsUrl: string; socketName: string };

export interface AndroidCdpOptions {
  serial: () => string | undefined;
  runAdb: (
    args: string[],
    signal?: AbortSignal,
    timeoutMs?: number,
  ) => Promise<Buffer>;
  onLog: (entry: LogEntry) => void;
}

/** Chrome DevTools Protocol client for Android's exposed WebView sockets. */
export class AndroidCdp implements WebViewAdapter {
  private readonly options: AndroidCdpOptions;
  private targets = new Map<string, TargetRecord>();
  private sockets = new Map<string, CdpSocket>();
  private logSockets = new Map<string, CdpSocket>();
  private forwards = new Map<string, number>();
  private stopped = false;
  private coverageSince?: string;

  status() {
    const connected = [...this.logSockets.values()].some(
      (value) => value.socket.readyState === WebSocket.OPEN,
    );
    return {
      connected,
      coverageSince: this.coverageSince,
      detail: connected
        ? "CDP console and network metadata"
        : "No attached WebView debugger; native device controls remain available",
    };
  }

  constructor(options: AndroidCdpOptions) {
    this.options = options;
  }

  async listTargets(signal?: AbortSignal): Promise<WebViewTarget[]> {
    const serial = this.options.serial();
    if (!serial || this.stopped) return [];
    const sockets = await this.discoverSockets(signal);
    const next = new Map<string, TargetRecord>();
    for (const socketName of sockets) {
      let port: number;
      try {
        port = await this.forward(socketName, signal);
        const response = await fetch(`http://127.0.0.1:${port}/json/list`, {
          signal: signal
            ? AbortSignal.any([signal, AbortSignal.timeout(5000)])
            : AbortSignal.timeout(5000),
        });
        if (!response.ok) continue;
        const entries = (await response.json()) as Array<
          Record<string, unknown>
        >;
        for (const entry of entries) {
          if (
            entry.type !== "page" ||
            typeof entry.id !== "string" ||
            typeof entry.webSocketDebuggerUrl !== "string"
          )
            continue;
          const id = `${serial}:${socketName}:${entry.id}`;
          next.set(id, {
            id,
            appId: "com.stash.stashnative.sample",
            url: typeof entry.url === "string" ? entry.url : "",
            title: typeof entry.title === "string" ? entry.title : "",
            wsUrl: this.forwardedWebSocketUrl(entry.webSocketDebuggerUrl, port),
            socketName,
          });
        }
      } catch (error) {
        this.log(
          "driver",
          "warn",
          `Unable to discover Android WebView targets on ${socketName}`,
          error,
        );
      }
    }
    this.targets = next;
    for (const [id] of this.logSockets)
      if (!next.has(id)) this.closeLogSocket(id);
    for (const [id, socket] of this.sockets)
      if (!next.has(id)) {
        socket.close();
        this.sockets.delete(id);
      }
    for (const [name, port] of this.forwards)
      if (!sockets.includes(name)) {
        await this.options
          .runAdb(["forward", "--remove", `tcp:${port}`], signal, 5000)
          .catch(() => {});
        this.forwards.delete(name);
      }
    await Promise.all(
      [...next.values()].map((target) => this.attachLogSocket(target, signal)),
    );
    return [...next.values()].map(
      ({ wsUrl: _wsUrl, socketName: _socketName, ...target }) => target,
    );
  }

  async inspect(
    targetId?: string,
    selector?: string,
    signal?: AbortSignal,
  ): Promise<unknown> {
    return this.evaluate(inspectScript(selector), targetId, signal);
  }

  async evaluate(
    script: string,
    targetId?: string,
    signal?: AbortSignal,
  ): Promise<unknown> {
    const target = await this.resolveTarget(targetId, signal);
    const result = (await this.command(
      target,
      "Runtime.evaluate",
      {
        expression: script,
        returnByValue: true,
        awaitPromise: true,
        userGesture: true,
      },
      signal,
    )) as {
      result?: { value?: unknown; description?: string };
      exceptionDetails?: unknown;
    };
    if (result?.exceptionDetails)
      throw new Error(
        `WebView evaluation failed: ${JSON.stringify(result.exceptionDetails)}`,
      );
    return result?.result?.value;
  }

  async setCss(
    css: string,
    targetId?: string,
    signal?: AbortSignal,
  ): Promise<unknown> {
    return this.evaluate(cssScript(css), targetId, signal);
  }

  async resetCss(targetId?: string, signal?: AbortSignal): Promise<unknown> {
    return this.evaluate(resetCssScript, targetId, signal);
  }

  async reload(targetId?: string, signal?: AbortSignal): Promise<void> {
    const target = await this.resolveTarget(targetId, signal);
    await this.command(target, "Page.reload", { ignoreCache: false }, signal);
  }

  async pollLogs(signal?: AbortSignal): Promise<void> {
    await this.listTargets(signal);
  }

  private async attachLogSocket(
    target: TargetRecord,
    signal?: AbortSignal,
  ): Promise<void> {
    if (this.logSockets.get(target.id)?.socket.readyState === WebSocket.OPEN)
      return;
    this.closeLogSocket(target.id);
    try {
      const cdp = await this.connect(target.wsUrl);
      this.logSockets.set(target.id, cdp);
      cdp.socket.on("message", (message: WebSocket.RawData) => {
        let event: { method?: string; params?: Record<string, unknown> };
        try {
          event = JSON.parse(message.toString()) as typeof event;
        } catch {
          return;
        }
        if (!event.method || !event.method.includes(".")) return;
        if (event.method === "Runtime.consoleAPICalled") {
          const params = event.params || {};
          const args = Array.isArray(params.args) ? params.args : [];
          this.log(
            "console",
            String(params.type || "log"),
            args
              .map((arg: any) => arg?.value ?? arg?.description ?? "")
              .join(" "),
            { target: target.id },
          );
        } else if (event.method === "Runtime.exceptionThrown") {
          this.log("console", "error", JSON.stringify(event.params || {}), {
            target: target.id,
          });
        } else if (event.method === "Log.entryAdded") {
          const entry = (event.params?.entry || {}) as Record<string, unknown>;
          this.log(
            "console",
            String(entry.level || "info"),
            String(entry.text || ""),
            { target: target.id, entry },
          );
        } else if (event.method === "Network.requestWillBeSent") {
          const request = (event.params?.request || {}) as Record<
            string,
            unknown
          >;
          this.log("network", "request", String(request.url || ""), {
            target: target.id,
            method: request.method,
            requestId: event.params?.requestId,
          });
        } else if (
          event.method === "Network.loadingFinished" ||
          event.method === "Network.loadingFailed"
        ) {
          this.log(
            "network",
            event.method.endsWith("Failed") ? "error" : "info",
            event.method,
            { target: target.id, ...event.params },
          );
        }
      });
      await this.commandSocket(cdp, "Runtime.enable", {}, signal);
      await this.commandSocket(cdp, "Log.enable", {}, signal);
      await this.commandSocket(cdp, "Network.enable", {}, signal);
      this.coverageSince = new Date().toISOString();
      this.log(
        "driver",
        "info",
        `WebView logging attached at ${new Date().toISOString()}`,
        { target: target.id, url: target.url },
      );
      cdp.socket.once("close", () =>
        this.log(
          "driver",
          "warn",
          "WebView debugger disconnected; device remains available",
          { target: target.id },
        ),
      );
    } catch (error) {
      this.log(
        "driver",
        "warn",
        `Unable to enable WebView logs for ${target.id}`,
        error,
      );
      this.closeLogSocket(target.id);
    }
  }

  async stop(): Promise<void> {
    this.stopped = true;
    for (const id of this.logSockets.keys()) this.closeLogSocket(id);
    for (const socket of this.sockets.values()) socket.close();
    this.sockets.clear();
    const serial = this.options.serial();
    if (serial) {
      for (const port of this.forwards.values()) {
        try {
          await this.options.runAdb(["forward", "--remove", `tcp:${port}`]);
        } catch {
          /* device may be gone */
        }
      }
    }
    this.forwards.clear();
    this.targets.clear();
  }

  private async discoverSockets(signal?: AbortSignal): Promise<string[]> {
    const output = await this.options.runAdb(
      ["shell", "cat", "/proc/net/unix"],
      signal,
      5000,
    );
    const found = new Set<string>();
    const pidOutput = await this.options
      .runAdb(["shell", "pidof", "com.stash.stashnative.sample"], signal, 5000)
      .catch(() => Buffer.from(""));
    const pids = new Set(
      pidOutput.toString().trim().split(/\s+/).filter(Boolean),
    );
    if (!pids.size) return [];
    for (const line of output.toString().split(/\r?\n/)) {
      const match = line.match(/(?:@|\0)(webview_devtools_remote(?:_\d+)?)/);
      if (!match) continue;
      const suffix = match[1].match(/_(\d+)$/)?.[1];
      if (!suffix || !pids.has(suffix)) continue;
      found.add(`localabstract:${match[1]}`);
    }
    return [...found];
  }

  private async forward(
    socketName: string,
    signal?: AbortSignal,
  ): Promise<number> {
    const known = this.forwards.get(socketName);
    if (known) return known;
    // Let ADB allocate a port, so an existing user's forwarding rule cannot be rebound.
    const output = await this.options.runAdb(
      ["forward", "tcp:0", socketName],
      signal,
      5000,
    );
    const fromAdb = Number(output.toString().trim());
    if (!Number.isSafeInteger(fromAdb) || fromAdb <= 0 || fromAdb > 65535)
      throw new Error("ADB did not return an allocated debugging port");
    const actual = fromAdb;
    this.forwards.set(socketName, actual);
    return actual;
  }

  private forwardedWebSocketUrl(value: string, port: number): string {
    try {
      const url = new URL(value);
      url.hostname = "127.0.0.1";
      url.port = String(port);
      return url.toString();
    } catch {
      return value;
    }
  }

  private async resolveTarget(
    targetId: string | undefined,
    signal?: AbortSignal,
  ): Promise<TargetRecord> {
    if (!this.targets.size) await this.listTargets(signal);
    const target = targetId
      ? this.targets.get(targetId)
      : this.targets.values().next().value;
    if (!target)
      throw new Error("No inspectable Android WebView target is attached");
    return target;
  }

  private async command(
    target: TargetRecord,
    method: string,
    params: Record<string, unknown>,
    signal?: AbortSignal,
  ): Promise<unknown> {
    let socket = this.sockets.get(target.id);
    if (!socket || socket.socket.readyState !== WebSocket.OPEN) {
      socket = await this.connect(target.wsUrl);
      this.sockets.set(target.id, socket);
    }
    try {
      return await this.commandSocket(socket, method, params, signal);
    } catch (error) {
      this.sockets.delete(target.id);
      socket.close();
      throw error;
    }
  }

  private connect(url: string): Promise<CdpSocket> {
    return new Promise((resolve, reject) => {
      const socket = new WebSocket(url, { handshakeTimeout: 5000 });
      const pending = new Map<
        number,
        { resolve: (value: unknown) => void; reject: (error: Error) => void }
      >();
      let nextId = 1;
      const rejectPending = (error: Error) => {
        for (const item of pending.values()) item.reject(error);
        pending.clear();
      };
      socket.once("open", () =>
        resolve({
          socket,
          nextId,
          pending,
          close: () => {
            rejectPending(new Error("WebView debugger disconnected"));
            try {
              socket.close();
            } catch {}
          },
        }),
      );
      socket.once("error", (error) => {
        reject(error instanceof Error ? error : new Error(String(error)));
        rejectPending(
          error instanceof Error ? error : new Error(String(error)),
        );
      });
      socket.on("close", () =>
        rejectPending(new Error("WebView debugger disconnected")),
      );
      socket.on("message", (message) => {
        let value: {
          id?: number;
          result?: unknown;
          error?: { message?: string };
        };
        try {
          value = JSON.parse(message.toString()) as typeof value;
        } catch {
          return;
        }
        if (typeof value.id !== "number") return;
        const item = pending.get(value.id);
        if (!item) return;
        pending.delete(value.id);
        if (value.error)
          item.reject(new Error(value.error.message || "CDP command failed"));
        else item.resolve(value.result);
      });
    });
  }

  private commandSocket(
    socket: CdpSocket,
    method: string,
    params: Record<string, unknown>,
    signal?: AbortSignal,
  ): Promise<unknown> {
    const id = socket.nextId++;
    return new Promise((resolve, reject) => {
      if (signal?.aborted) {
        reject(new Error("Operation aborted"));
        return;
      }
      const cleanup = () => {
        clearTimeout(timer);
        signal?.removeEventListener("abort", abort);
        socket.pending.delete(id);
      };
      const abort = () => {
        cleanup();
        reject(new Error("Operation aborted; observe before continuing"));
      };
      const timer = setTimeout(() => {
        cleanup();
        reject(
          new Error(
            "WebView debugger reply timed out; completion is uncertain, observe before continuing",
          ),
        );
      }, 15_000);
      signal?.addEventListener("abort", abort, { once: true });
      socket.pending.set(id, {
        resolve: (value) => {
          cleanup();
          resolve(value);
        },
        reject: (error) => {
          cleanup();
          reject(error);
        },
      });
      try {
        socket.socket.send(JSON.stringify({ id, method, params }));
      } catch (error) {
        cleanup();
        reject(error);
      }
    });
  }

  private closeLogSocket(id: string): void {
    const socket = this.logSockets.get(id);
    if (socket) socket.close();
    this.logSockets.delete(id);
  }

  private log(
    source: LogEntry["source"],
    level: string,
    message: string,
    details?: unknown,
  ): void {
    this.options.onLog({
      timestamp: new Date().toISOString(),
      source,
      level,
      message,
      details,
    });
  }
}
