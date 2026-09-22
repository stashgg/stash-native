import crypto from "node:crypto";

import type { DeviceChoice } from "../contracts.js";

export const IOS_APP_ID = "com.stash.stashnative.sample";
export const MIN_RUNTIME = 16_004_000;
export const MIN_RUNTIME_LABEL = "16.4";

export interface SimRuntime {
  id: string;
  version: string;
  name: string;
}
export interface SimDevice {
  id: string;
  name: string;
  state: string;
  runtimeId: string;
  runtime?: string;
  deviceType?: string;
}

export function inspectorProcessBundleId(executableName: string): string {
  if (!executableName) throw new Error("An iOS executable name is required");
  return `process-${executableName}`;
}

export function evaluationValue(
  response:
    | { ok?: boolean; value?: unknown; error?: string }
    | null
    | undefined,
): unknown {
  if (response?.ok === false)
    throw new Error(response.error || "WebView evaluation failed");
  return response?.value;
}

export function versionNumber(value: string): number {
  const match = value.match(/(\d+)(?:\.(\d+))?(?:\.(\d+))?/);
  if (!match) return 0;
  return (
    Number(match[1]) * 1_000_000 +
    Number(match[2] || 0) * 1_000 +
    Number(match[3] || 0)
  );
}

export function parseRuntimes(output: string): SimRuntime[] {
  const runtimes: SimRuntime[] = [];
  for (const line of output.split(/\r?\n/)) {
    const m = line.match(
      /^\s*iOS\s+([\d.]+).*?[-]\s*(com\.apple\.CoreSimulator\.SimRuntime\.iOS-[^\s]+)/,
    );
    if (m) runtimes.push({ id: m[2], version: m[1], name: `iOS ${m[1]}` });
  }
  return runtimes;
}

export function parseDevices(
  output: string,
  runtimes: SimRuntime[] = [],
): SimDevice[] {
  const devices: SimDevice[] = [];
  let runtimeId = "";
  for (const line of output.split(/\r?\n/)) {
    const section = line.match(/^--\s*(.+?)\s*--$/);
    if (section) {
      const value = section[1].trim();
      runtimeId = value.startsWith("com.apple.")
        ? value
        : runtimes.find(
            (item) =>
              item.name === value || item.name.replace(/^iOS\s+/, "") === value,
          )?.id || runtimeId;
      continue;
    }
    const match = line.match(
      /^\s*(.+?)\s+\(([0-9A-Fa-f-]{20,})\)\s+\(([^)]+)\)/,
    );
    if (!match) continue;
    const runtime = runtimes.find((item) => item.id === runtimeId);
    devices.push({
      id: match[2],
      name: match[1].trim(),
      state: match[3],
      runtimeId,
      runtime: runtime?.version,
    });
  }
  return devices;
}

export function chooseRuntime(
  runtimes: SimRuntime[],
  requested?: string,
): SimRuntime | undefined {
  const usable = runtimes.filter(
    (runtime) => versionNumber(runtime.version) >= MIN_RUNTIME,
  );
  if (requested) {
    return usable.find(
      (item) =>
        item.id === requested ||
        item.version === requested ||
        item.name === requested,
    );
  }
  return [...usable].sort(
    (a, b) => versionNumber(b.version) - versionNumber(a.version),
  )[0];
}

export function ownedDeviceName(repoRoot: string, profile?: string): string {
  const digest = crypto
    .createHash("sha1")
    .update(repoRoot)
    .digest("hex")
    .slice(0, 8);
  const base = `Stash Robot iPhone ${digest}`;
  const suffix = profile?.trim().replace(/\s+/g, " ");
  return suffix ? `${base} (${suffix})` : base;
}

export function isOwnedDeviceName(repoRoot: string, name: string): boolean {
  const base = ownedDeviceName(repoRoot);
  return name === base || (name.startsWith(`${base} (`) && name.endsWith(")"));
}

export function isTransientSimulatorInstallError(error: unknown): boolean {
  const message = String(error);
  return (
    /IXErrorDomain/i.test(message) &&
    /Failed to (?:set metadata|create promise)/i.test(message)
  );
}

export function coordinate(value: number, size: number): number {
  if (!Number.isFinite(value) || !Number.isFinite(size) || size <= 0)
    throw new Error("Invalid device coordinate");
  return Math.max(0, Math.min(Math.max(0, size - 1), value * size));
}

export function toDeviceChoices(devices: SimDevice[]): DeviceChoice[] {
  return devices
    .filter((device) => device.state !== "Unavailable")
    .map((device) => ({
      id: device.id,
      name: device.name,
      ...(device.runtime ? { runtime: device.runtime } : {}),
    }));
}
