import { spawn, type ChildProcess } from "node:child_process";
import { createServer } from "node:net";
import { join } from "node:path";
import type { AdapterOptions } from "./contracts.js";

export interface RunOptions {
  cwd?: string;
  env?: NodeJS.ProcessEnv;
  signal?: AbortSignal;
  timeoutMs?: number;
  onLine?: (line: string) => void;
  maxBuffer?: number;
  input?: string;
}
export interface ManagedProcess {
  child: ChildProcess;
  stop(): Promise<void>;
  exited: Promise<{ code: number | null; signal: NodeJS.Signals | null }>;
}

export function spawnManaged(
  command: string,
  args: string[],
  options: RunOptions = {},
): ManagedProcess {
  options.signal?.throwIfAborted();
  const child = spawn(command, args, {
    cwd: options.cwd,
    env: { ...process.env, ...options.env },
    detached: true,
    stdio: ["pipe", "pipe", "pipe"],
  });
  let done = false;
  let spawnError: Error | undefined;
  const exited = new Promise<{
    code: number | null;
    signal: NodeJS.Signals | null;
  }>((resolve) => {
    child.once("error", (error) => {
      spawnError = error;
      done = true;
      resolve({ code: -1, signal: null });
    });
    child.once("close", (code, signal) => {
      done = true;
      resolve({ code, signal });
    });
  });
  function send(signal: NodeJS.Signals) {
    if (done || !child.pid) return;
    try {
      process.kill(-child.pid, signal);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ESRCH") throw error;
    }
  }
  let stopping: Promise<void> | undefined;
  function stop(): Promise<void> {
    return (stopping ??= (async () => {
      send("SIGTERM");
      let timer: NodeJS.Timeout | undefined;
      await Promise.race([
        exited,
        new Promise<void>((resolve) => {
          timer = setTimeout(resolve, 2500);
        }),
      ]);
      if (timer) clearTimeout(timer);
      if (!done) {
        send("SIGKILL");
        await exited;
      }
    })());
  }
  const onAbort = () => {
    void stop();
  };
  options.signal?.addEventListener("abort", onAbort, { once: true });
  const timeout = options.timeoutMs
    ? setTimeout(onAbort, options.timeoutMs)
    : undefined;
  void exited.then(() => {
    options.signal?.removeEventListener("abort", onAbort);
    if (timeout) clearTimeout(timeout);
  });
  if (options.onLine) {
    for (const stream of [child.stdout, child.stderr]) {
      let rest = "";
      stream?.on("data", (data: Buffer) => {
        const lines = (rest + data.toString()).split(/\r?\n/);
        rest = lines.pop() || "";
        for (const line of lines) options.onLine!(line);
        if (rest.length > 65536) {
          options.onLine!(rest.slice(0, 65536));
          rest = "";
        }
      });
      stream?.on("end", () => {
        if (rest) options.onLine!(rest);
      });
    }
  }
  child.stdin?.on("error", () => {});
  child.stdin?.end(options.input);
  // Error events are consumed above, including missing executable errors.
  void spawnError;
  return { child, stop, exited };
}

export async function run(
  command: string,
  args: string[],
  options: RunOptions = {},
): Promise<{ stdout: Buffer; stderr: string }> {
  const managed = spawnManaged(command, args, options);
  const stdout: Buffer[] = [];
  const stderr: Buffer[] = [];
  let bytes = 0;
  let overflow = false;
  let error: Error | undefined;
  const limit = options.maxBuffer ?? 32 * 1024 * 1024;
  managed.child.once("error", (e) => {
    error = e;
  });
  for (const [stream, chunks] of [
    [managed.child.stdout, stdout],
    [managed.child.stderr, stderr],
  ] as const) {
    stream?.on("data", (chunk: Buffer) => {
      bytes += chunk.length;
      if (bytes > limit) {
        overflow = true;
        void managed.stop();
      } else chunks.push(chunk);
    });
  }
  const result = await managed.exited;
  options.signal?.throwIfAborted();
  const errText = Buffer.concat(stderr).toString();
  if (error) throw error;
  if (overflow) throw new Error(`${command} output exceeded ${limit} bytes`);
  if (result.code !== 0)
    throw new Error(
      `${command} ${args[0] || ""} failed (${result.signal || result.code}): ${(errText || Buffer.concat(stdout).toString()).slice(-6000)}`,
    );
  return { stdout: Buffer.concat(stdout), stderr: errText };
}

export async function freePort(): Promise<number> {
  const server = createServer();
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const port = (server.address() as { port: number }).port;
      server.close((error) => (error ? reject(error) : resolve(port)));
    });
  });
}

/** Emulator console and ADB ports must be an available consecutive even/odd pair. */
export async function freeEmulatorPort(): Promise<number> {
  for (let port = 5554; port <= 5682; port += 2) {
    const servers = [createServer(), createServer()];
    try {
      for (let index = 0; index < servers.length; index++) {
        await new Promise<void>((resolve, reject) => {
          servers[index]!.once("error", reject);
          servers[index]!.listen(port + index, "127.0.0.1", resolve);
        });
      }
      return port;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "EADDRINUSE") throw error;
    } finally {
      await Promise.all(
        servers
          .filter((server) => server.listening)
          .map(
            (server) =>
              new Promise<void>((resolve) => server.close(() => resolve())),
          ),
      );
    }
  }
  throw new Error(
    "No free Android emulator console/ADB port pair is available",
  );
}

export function pngDimensions(png: Buffer): { width: number; height: number } {
  if (
    png.length < 24 ||
    !png.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
  )
    throw new Error("Device did not return a PNG screenshot");
  return { width: png.readUInt32BE(16), height: png.readUInt32BE(20) };
}

export async function delay(ms: number, signal?: AbortSignal): Promise<void> {
  signal?.throwIfAborted();
  return new Promise((resolve, reject) => {
    const finish = () => {
      signal?.removeEventListener("abort", abort);
      resolve();
    };
    const timer = setTimeout(finish, ms);
    const abort = () => {
      clearTimeout(timer);
      reject(signal?.reason ?? new Error("Aborted"));
    };
    signal?.addEventListener("abort", abort, { once: true });
  });
}

export async function startAppium(
  options: AdapterOptions,
  driver: "uiautomator2" | "xcuitest",
  signal?: AbortSignal,
  env: NodeJS.ProcessEnv = {},
): Promise<{ port: number; stop(): Promise<void> }> {
  const port = await freePort();
  const harnessRoot = join(options.repoRoot, "tools", "stash-robot");
  const managed = spawnManaged(
    process.execPath,
    [
      join(harnessRoot, "node_modules", "appium", "index.js"),
      "--address",
      "127.0.0.1",
      "--port",
      String(port),
      "--use-drivers",
      driver,
      "--log-no-colors",
      "--log-level",
      "warn",
    ],
    {
      cwd: harnessRoot,
      env: { ...env, APPIUM_HOME: harnessRoot },
      onLine: (message) =>
        options.onLog({
          timestamp: new Date().toISOString(),
          source: "driver",
          level: "info",
          message,
        }),
    },
  );
  let exited = false;
  void managed.exited.then(() => {
    exited = true;
  });
  try {
    const deadline = Date.now() + 60000;
    while (Date.now() < deadline) {
      signal?.throwIfAborted();
      if (exited)
        throw new Error("Appium exited during startup; inspect driver logs");
      try {
        const response = await fetch(`http://127.0.0.1:${port}/status`, {
          signal: AbortSignal.timeout(1500),
        });
        if (response.ok) return { port, stop: managed.stop };
      } catch {
        /* The server is still starting. */
      }
      await delay(250, signal);
    }
    throw new Error("Appium did not become ready within 60 seconds");
  } catch (error) {
    await managed.stop();
    throw error;
  }
}
