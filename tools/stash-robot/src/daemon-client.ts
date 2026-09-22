import type { SessionSnapshot } from "./session.js";

export interface ServerRecord {
  pid: number;
  port: number;
  token: string;
  url: string;
  startedAt: string;
}

export function isServerRecord(value: unknown): value is ServerRecord {
  if (!value || typeof value !== "object") return false;
  const record = value as ServerRecord;
  try {
    const url = new URL(record.url);
    return (
      Number.isSafeInteger(record.pid) &&
      record.pid > 1 &&
      Number.isSafeInteger(record.port) &&
      record.port > 0 &&
      record.port <= 65535 &&
      typeof record.token === "string" &&
      record.token.length >= 20 &&
      typeof record.startedAt === "string" &&
      url.protocol === "http:" &&
      url.hostname === "127.0.0.1" &&
      Number(url.port) === record.port &&
      !url.username &&
      !url.password
    );
  } catch {
    return false;
  }
}

export async function daemonRequest(
  record: ServerRecord,
  path: string,
  body?: unknown,
): Promise<Response> {
  if (!isServerRecord(record))
    throw new Error("Invalid stash-robot server record");
  return fetch(new URL(path, record.url), {
    method: body === undefined ? "GET" : "POST",
    headers: {
      "x-stash-token": record.token,
      origin: new URL(record.url).origin,
      "content-type": "application/json",
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    signal: AbortSignal.timeout(body === undefined ? 3000 : 120_000),
  });
}

export async function verifyDaemon(
  record: ServerRecord,
): Promise<SessionSnapshot | undefined> {
  try {
    const response = await daemonRequest(record, "/api/bootstrap");
    if (!response.ok) return undefined;
    const state = (await response.json()) as SessionSnapshot;
    return typeof state.id === "string" &&
      ["selecting", "starting", "ready", "error"].includes(state.phase)
      ? state
      : undefined;
  } catch {
    return undefined;
  }
}

export async function transferScenario(
  record: ServerRecord,
  text: string,
): Promise<void> {
  const response = await daemonRequest(record, "/api/scenario", { text });
  if (!response.ok)
    throw new Error(
      `Could not send scenario to the existing session: ${await response.text()}`,
    );
}
