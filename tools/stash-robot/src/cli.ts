#!/usr/bin/env node
import { execFile, spawn } from "node:child_process";
import {
  mkdir,
  open as openFile,
  readFile,
  unlink,
  writeFile,
} from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { build } from "esbuild";
import type { AdapterOptions, Check, Platform } from "./contracts.js";
import { createAndroidAdapter } from "./android.js";
import { createIosAdapter } from "./ios.js";
import { createFakeAdapter } from "./fake.js";
import { checkCodex } from "./codex.js";
import { startServer } from "./server.js";
import {
  daemonRequest,
  isServerRecord,
  transferScenario,
  verifyDaemon,
  type ServerRecord,
} from "./daemon-client.js";

const execFileAsync = promisify(execFile);
const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

interface Args {
  command: string;
  repoRoot: string;
  daemon: boolean;
  foreground: boolean;
  open: boolean;
  fake: boolean;
  agent: boolean;
  scenario?: string;
  model?: string;
  effort?: string;
  platform?: Platform;
}

async function main(): Promise<void> {
  requireNode();
  const args = parse(process.argv.slice(2));
  const cacheDir = join(args.repoRoot, "build", "stash-robot");
  const recordPath = join(cacheDir, "server.json");
  if (args.command === "stop") {
    await stop(recordPath);
    return;
  }
  if (args.command === "doctor") {
    await doctor(args, cacheDir);
    return;
  }
  if (args.command === "reset-device") {
    await ensureStopped(recordPath);
    await resetDevices(args, cacheDir);
    return;
  }
  if (args.command !== "start") usage(`Unknown command: ${args.command}`);
  if (args.daemon && !args.foreground) {
    await launchDaemon(args, recordPath);
    return;
  }
  await runServer(args, cacheDir, recordPath);
}

function adapter(
  args: Args,
  cacheDir: string,
  platform: Platform,
  callbacks: Pick<AdapterOptions, "onLog" | "onProgress">,
) {
  const options: AdapterOptions = {
    repoRoot: args.repoRoot,
    cacheDir: join(cacheDir, "cache"),
    ...callbacks,
  };
  return args.fake
    ? createFakeAdapter(options, platform)
    : platform === "android"
      ? createAndroidAdapter(options)
      : createIosAdapter(options);
}

async function sharedChecks(): Promise<Check[]> {
  const checks: Check[] = [
    {
      name: "Node",
      ok: compatibleNode(process.versions.node),
      detail: `Node ${process.versions.node}`,
    },
  ];
  try {
    const { stdout } = await execFileAsync("npm", ["--version"], {
      timeout: 5000,
    });
    const major = Number(stdout.trim().split(".")[0]);
    checks.push({
      name: "npm",
      ok: major >= 10,
      detail: `npm ${stdout.trim()}${major < 10 ? "; version 10 or newer required" : ""}`,
    });
  } catch (error) {
    checks.push({ name: "npm", ok: false, detail: message(error) });
  }
  const codex = await checkCodex();
  checks.push({ name: "Codex", ...codex });
  return checks;
}

async function runServer(
  args: Args,
  cacheDir: string,
  recordPath: string,
): Promise<void> {
  await mkdir(cacheDir, { recursive: true });
  await build({
    entryPoints: [join(packageRoot, "web", "app.ts")],
    bundle: true,
    outfile: join(packageRoot, "dist", "web", "app.js"),
    target: "es2022",
    platform: "browser",
    format: "esm",
    logLevel: "silent",
  });
  const existing = await readRecord(recordPath);
  if (existing && alive(existing.pid))
    throw new Error(`stash-robot is already running at ${existing.url}`);
  const harness = await startServer({
    repoRoot: args.repoRoot,
    cacheDir,
    model: args.model,
    effort: args.effort,
    scenario: args.scenario,
    enableAgent: args.agent,
    createAdapter: (platform, hooks) =>
      adapter(args, cacheDir, platform, hooks),
    prerequisiteChecks: sharedChecks,
  });
  const record: ServerRecord = {
    pid: process.pid,
    port: harness.port,
    token: harness.token,
    url: harness.url,
    startedAt: new Date().toISOString(),
  };
  await writeFile(recordPath, JSON.stringify(record, null, 2), { mode: 0o600 });
  const browserUrl = `${harness.url}#token=${encodeURIComponent(harness.token)}`;
  process.stdout.write(`${browserUrl}\n`);
  if (args.open)
    spawn("open", [browserUrl], { detached: true, stdio: "ignore" }).unref();
  let stopping = false;
  const shutdown = async () => {
    if (stopping) return;
    stopping = true;
    await harness.close().catch(() => {});
    await unlink(recordPath).catch(() => {});
  };
  process.once("SIGTERM", () => void shutdown().then(() => process.exit(0)));
  process.once("SIGINT", () => void shutdown().then(() => process.exit(130)));
  await new Promise<void>((resolveWait) => {
    const unsubscribe = harness.session.subscribe((event) => {
      if (
        event.type === "state" &&
        (event.data as { phase?: string }).phase === "ended" &&
        !stopping
      )
        void shutdown().then(() => {
          unsubscribe();
          resolveWait();
        });
    });
  });
}

async function launchDaemon(args: Args, recordPath: string): Promise<void> {
  await mkdir(dirname(recordPath), { recursive: true });
  const prior = await readRecord(recordPath);
  if (prior && alive(prior.pid)) {
    if (!(await verifyDaemon(prior)))
      throw new Error(
        "The recorded process is alive but did not authenticate as an active stash-robot server. Its record and process were left intact.",
      );
    if (args.model || args.effort)
      process.stderr.write(
        "Reusing the existing worker configuration; model and effort overrides apply to new sessions.\n",
      );
    if (args.scenario) await transferScenario(prior, args.scenario);
    const browserUrl = `${prior.url}#token=${encodeURIComponent(prior.token)}`;
    process.stdout.write(`${browserUrl}\n`);
    if (args.open)
      spawn("open", [browserUrl], { detached: true, stdio: "ignore" }).unref();
    return;
  }
  const forwarded = [
    "start",
    "--foreground",
    "--repo",
    args.repoRoot,
    ...(args.open ? [] : ["--no-open"]),
    ...(args.fake ? ["--fake"] : []),
    ...(args.agent ? [] : ["--no-agent"]),
    ...(args.scenario ? ["--scenario", args.scenario] : []),
    ...(args.model ? ["--model", args.model] : []),
    ...(args.effort ? ["--effort", args.effort] : []),
  ];
  const logPath = join(dirname(recordPath), "server.log");
  const log = await openFile(logPath, "a", 0o600);
  const child = spawn(
    process.execPath,
    ["--import", "tsx", join(packageRoot, "src", "cli.ts"), ...forwarded],
    {
      cwd: packageRoot,
      detached: true,
      stdio: ["ignore", log.fd, log.fd],
      env: process.env,
    },
  );
  child.unref();
  await log.close();
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    const current = await readRecord(recordPath);
    if (
      current &&
      current.pid === child.pid &&
      alive(current.pid) &&
      (await verifyDaemon(current))
    ) {
      process.stdout.write(
        `${current.url}#token=${encodeURIComponent(current.token)}\n`,
      );
      return;
    }
    await new Promise((done) => setTimeout(done, 100));
  }
  const detail = await readFile(logPath, "utf8")
    .then((value) => value.slice(-4000))
    .catch(() => "No daemon log was written.");
  throw new Error(
    `stash-robot did not start within 30 seconds. Log: ${logPath}\n${detail}`,
  );
}

async function doctor(args: Args, cacheDir: string): Promise<void> {
  const checks = await sharedChecks();
  const sharedFailed = checks.some((check) => !check.ok);
  let failed = sharedFailed;
  for (const platform of args.platform
    ? [args.platform]
    : (["android", "ios"] as Platform[])) {
    const instance = adapter(args, cacheDir, platform, {
      onLog: () => {},
      onProgress: () => {},
    });
    try {
      const report = await instance.doctor();
      report.checks = [...checks, ...report.checks];
      report.ready = report.ready && !sharedFailed;
      failed ||= !report.ready;
      process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    } finally {
      await instance.stop().catch(() => {});
    }
  }
  if (failed) process.exitCode = 1;
}
async function resetDevices(args: Args, cacheDir: string): Promise<void> {
  for (const platform of args.platform
    ? [args.platform]
    : (["android", "ios"] as Platform[])) {
    const instance = adapter(args, cacheDir, platform, {
      onLog: () => {},
      onProgress: (value) => process.stderr.write(`${value}\n`),
    });
    try {
      await instance.reset();
      process.stdout.write(`Reset ${platform} harness device\n`);
    } finally {
      await instance.stop().catch(() => {});
    }
  }
}
async function stop(path: string): Promise<void> {
  const record = await readRecord(path);
  if (!record) {
    process.stdout.write("stash-robot is not running\n");
    return;
  }
  if (!alive(record.pid)) {
    await unlink(path).catch(() => {});
    process.stdout.write("Removed stale stash-robot server record\n");
    return;
  }
  let response: Response;
  try {
    response = await daemonRequest(record, "/api/end", {});
  } catch (error) {
    throw new Error(
      `Could not contact the recorded stash-robot process; it was left running: ${message(error)}`,
    );
  }
  if (!response.ok)
    throw new Error(
      `Recorded stash-robot process rejected shutdown (${response.status}); it was left running`,
    );
  const deadline = Date.now() + 10_000;
  while (Date.now() < deadline && alive(record.pid))
    await new Promise((done) => setTimeout(done, 100));
  if (alive(record.pid))
    throw new Error(
      "stash-robot accepted shutdown but is still running; the server record was preserved",
    );
  await unlink(path).catch(() => {});
  process.stdout.write("stash-robot stopped\n");
}
async function ensureStopped(path: string): Promise<void> {
  const current = await readRecord(path);
  if (current && alive(current.pid))
    throw new Error(
      `End or stop the running session at ${current.url} before resetting its device`,
    );
}
async function readRecord(path: string): Promise<ServerRecord | undefined> {
  try {
    const value: unknown = JSON.parse(await readFile(path, "utf8"));
    return isServerRecord(value) ? value : undefined;
  } catch {
    return undefined;
  }
}
function alive(pid: number): boolean {
  if (!Number.isSafeInteger(pid) || pid <= 1) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function parse(argv: string[]): Args {
  const result: Args = {
    command: argv.shift() ?? "start",
    repoRoot: resolve(packageRoot, "../.."),
    daemon: false,
    foreground: false,
    open: true,
    fake: false,
    agent: true,
  };
  while (argv.length) {
    const flag = argv.shift()!;
    if (flag === "--daemon") result.daemon = true;
    else if (flag === "--foreground") result.foreground = true;
    else if (flag === "--no-open") result.open = false;
    else if (flag === "--fake") result.fake = true;
    else if (flag === "--no-agent") result.agent = false;
    else if (flag === "--repo") result.repoRoot = resolve(required(argv, flag));
    else if (flag === "--scenario") result.scenario = required(argv, flag);
    else if (flag === "--model") result.model = required(argv, flag);
    else if (flag === "--effort") result.effort = required(argv, flag);
    else if (flag === "--platform")
      result.platform = parsePlatform(required(argv, flag));
    else if (flag === "android" || flag === "ios") result.platform = flag;
    else usage(`Unknown option: ${flag}`);
  }
  return result;
}
function required(argv: string[], flag: string): string {
  const value = argv.shift();
  if (!value) usage(`${flag} requires a value`);
  return value!;
}
function parsePlatform(value: string): Platform {
  if (value !== "android" && value !== "ios")
    usage("platform must be android or ios");
  return value as Platform;
}
function requireNode(): void {
  if (!compatibleNode(process.versions.node))
    throw new Error(
      `stash-robot requires Node 22.12+ (22.x) or Node 24+; found ${process.versions.node}`,
    );
}
function compatibleNode(value: string): boolean {
  const [major, minor] = value.split(".").map(Number);
  return major === 22 ? minor! >= 12 : major! >= 24;
}
function message(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
function usage(error?: string): never {
  if (error) process.stderr.write(`${error}\n`);
  process.stderr.write(
    "Usage: stash-robot <start|stop|doctor|reset-device> [--daemon] [--repo PATH] [--scenario TEXT] [--model MODEL] [--effort LEVEL] [--no-open]\n",
  );
  process.exit(2);
}

main().catch((error) => {
  process.stderr.write(`${message(error)}\n`);
  process.exitCode = 1;
});
