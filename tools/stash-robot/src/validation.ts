import type { Platform, RobotAction } from "./contracts.js";

export class HttpError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

export function record(
  value: unknown,
  label = "body",
): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new HttpError(400, `${label} must be an object`);
  return value as Record<string, unknown>;
}

export function string(
  value: unknown,
  name: string,
  options: { optional?: boolean; max?: number } = {},
): string | undefined {
  if (value === undefined && options.optional) return undefined;
  if (typeof value !== "string" || !value.trim())
    throw new HttpError(400, `${name} must be a non-empty string`);
  if (value.length > (options.max ?? 100_000))
    throw new HttpError(413, `${name} is too long`);
  return value;
}

export function platform(value: unknown): Platform {
  if (value !== "android" && value !== "ios")
    throw new HttpError(400, "platform must be android or ios");
  return value;
}

function fraction(value: unknown, name: string): number {
  if (
    typeof value !== "number" ||
    !Number.isFinite(value) ||
    value < 0 ||
    value > 1
  ) {
    throw new HttpError(400, `${name} must be a number from 0 to 1`);
  }
  return value;
}

export function robotAction(value: unknown): RobotAction {
  const input = record(value, "action");
  switch (input.type) {
    case "tap":
      return {
        type: "tap",
        x: fraction(input.x, "x"),
        y: fraction(input.y, "y"),
        frameId: string(input.frameId, "frameId")!,
      };
    case "swipe": {
      const durationMs =
        input.durationMs === undefined ? undefined : Number(input.durationMs);
      if (
        durationMs !== undefined &&
        (!Number.isFinite(durationMs) || durationMs < 50 || durationMs > 10_000)
      )
        throw new HttpError(400, "durationMs must be from 50 to 10000");
      return {
        type: "swipe",
        fromX: fraction(input.fromX, "fromX"),
        fromY: fraction(input.fromY, "fromY"),
        toX: fraction(input.toX, "toX"),
        toY: fraction(input.toY, "toY"),
        durationMs,
        frameId: string(input.frameId, "frameId")!,
      };
    }
    case "tapElement":
      return {
        type: "tapElement",
        selector: string(input.selector, "selector", { max: 2000 })!,
      };
    case "type":
      return {
        type: "type",
        text:
          typeof input.text === "string"
            ? input.text.slice(0, 20_000)
            : (() => {
                throw new HttpError(400, "text must be a string");
              })(),
        selector: string(input.selector, "selector", {
          optional: true,
          max: 2000,
        }),
      };
    case "back":
    case "hideKeyboard":
    case "home":
      return { type: input.type };
    case "rotate":
      if (input.orientation !== "portrait" && input.orientation !== "landscape")
        throw new HttpError(400, "invalid orientation");
      return { type: "rotate", orientation: input.orientation };
    default:
      throw new HttpError(400, "unknown action type");
  }
}

export async function readJson(
  request: import("node:http").IncomingMessage,
  limit = 1_000_000,
): Promise<unknown> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.from(chunk);
    size += buffer.length;
    if (size > limit) throw new HttpError(413, "request body too large");
    chunks.push(buffer);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
  } catch {
    throw new HttpError(400, "invalid JSON");
  }
}
