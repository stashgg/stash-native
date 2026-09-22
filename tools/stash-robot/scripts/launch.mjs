#!/usr/bin/env node
import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { dirname, join, resolve } from "node:path";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";
import { spawn, spawnSync } from "node:child_process";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const acceptable = (version) => {
  const [major, minor] = version
    .trim()
    .replace(/^v/, "")
    .split(".")
    .map(Number);
  return (major === 22 && minor >= 12) || major >= 24;
};
const candidates = [
  process.execPath,
  ...(process.env.PATH || "").split(":").map((p) => join(p, "node")),
];
const nvmRoot = join(homedir(), ".nvm", "versions", "node");
if (existsSync(nvmRoot))
  for (const version of readdirSync(nvmRoot).sort((a, b) =>
    b.localeCompare(a, undefined, { numeric: true }),
  ))
    candidates.push(join(nvmRoot, version, "bin", "node"));
let node;
for (const candidate of new Set(candidates)) {
  if (!existsSync(candidate)) continue;
  const check = spawnSync(candidate, ["-p", "process.versions.node"], {
    encoding: "utf8",
  });
  if (check.status === 0 && acceptable(check.stdout)) {
    node = candidate;
    break;
  }
}
if (!node) {
  console.error(
    "stash-robot requires Node 22.12+ (22.x) or Node 24+. Install a compatible Node runtime and retry.",
  );
  process.exit(1);
}
const env = {
  ...process.env,
  PATH: `${dirname(node)}:${process.env.PATH || ""}`,
};
const hash = createHash("sha256")
  .update(readFileSync(join(root, "package-lock.json")))
  .digest("hex");
const stamp = join(root, "node_modules", ".stash-robot-lock");
if (
  !existsSync(stamp) ||
  readFileSync(stamp, "utf8") !== hash ||
  !existsSync(join(root, "node_modules", "tsx"))
) {
  console.error("Installing the pinned stash-robot dependencies...");
  const installed = spawnSync("npm", ["ci", "--no-audit", "--no-fund"], {
    cwd: root,
    env,
    stdio: "inherit",
  });
  if (installed.status !== 0) process.exit(installed.status || 1);
  writeFileSync(stamp, hash);
}
const child = spawn(
  node,
  ["--import", "tsx", join(root, "src", "cli.ts"), ...process.argv.slice(2)],
  { cwd: root, env, stdio: "inherit" },
);
child.on("error", (error) => {
  console.error(error.message);
  process.exitCode = 1;
});
child.on("exit", (code, signal) => {
  process.exitCode = code ?? (signal ? 1 : 0);
});
for (const signal of ["SIGINT", "SIGTERM"])
  process.on(signal, () => child.kill(signal));
