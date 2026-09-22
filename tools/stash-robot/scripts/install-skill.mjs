#!/usr/bin/env node
import { lstat, mkdir, realpath, symlink } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const source = join(repoRoot, ".agents", "skills", "stash-robot");
const skillsRoot = join(
  process.env.CODEX_HOME || join(homedir(), ".codex"),
  "skills",
);
const target = join(skillsRoot, "stash-robot");
await mkdir(skillsRoot, { recursive: true });
try {
  await lstat(target);
  if ((await realpath(target)) !== (await realpath(source)))
    throw new Error(
      `A different skill already exists at ${target}; it was left untouched.`,
    );
  console.log(`stash-robot is already linked at ${target}`);
} catch (error) {
  if (error.code !== "ENOENT") throw error;
  await symlink(source, target, "dir");
  console.log(`Installed stash-robot at ${target}`);
}
