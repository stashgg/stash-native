import {
  createServer,
  type IncomingMessage,
  type ServerResponse,
} from "node:http";
import { readFile } from "node:fs/promises";
import { dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { randomBytes, timingSafeEqual as safeEqual } from "node:crypto";
import type { Platform } from "./contracts.js";
import { RobotSession, type SessionOptions } from "./session.js";
import { HttpError, platform, readJson, record, string } from "./validation.js";

const moduleDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(moduleDir, "..");

export interface HarnessServerOptions extends SessionOptions {
  host?: string;
  port?: number;
  token?: string;
}
export interface HarnessServer {
  host: string;
  port: number;
  token: string;
  url: string;
  session: RobotSession;
  close(): Promise<void>;
}

export async function startServer(
  options: HarnessServerOptions,
): Promise<HarnessServer> {
  const requestedHost = options.host ?? "127.0.0.1";
  const host = requestedHost === "localhost" ? "127.0.0.1" : requestedHost;
  if (host !== "127.0.0.1" && host !== "::1" && host !== "localhost")
    throw new Error("stash-robot only binds to loopback");
  const token = options.token ?? randomBytes(32).toString("base64url");
  const session = new RobotSession(options);
  let actualPort = 0;
  const streams = new Set<ServerResponse>();
  const server = createServer(
    (request, response) =>
      void route(request, response).catch((error) =>
        sendError(response, error),
      ),
  );

  async function route(
    request: IncomingMessage,
    response: ServerResponse,
  ): Promise<void> {
    const origin = `http://${urlHost(host)}:${actualPort}`;
    const url = new URL(request.url ?? "/", origin);
    if (
      request.method === "GET" &&
      (url.pathname === "/" || url.pathname === "/index.html")
    )
      return serveStatic(response, "web/index.html");
    if (request.method === "GET" && url.pathname === "/app.js")
      return serveStatic(response, "app.js");
    if (request.method === "GET" && url.pathname === "/style.css")
      return serveStatic(response, "web/style.css");
    authenticate(request, url, token);
    if (request.method !== "GET") assertSameOrigin(request, origin);

    if (request.method === "GET" && url.pathname === "/api/bootstrap")
      return json(response, 200, session.snapshot());
    if (request.method === "GET" && url.pathname === "/api/events") {
      response.writeHead(200, {
        "content-type": "text/event-stream",
        "cache-control": "no-cache, no-transform",
        connection: "keep-alive",
        "x-accel-buffering": "no",
      });
      streams.add(response);
      response.write(": connected\n\n");
      const last =
        Number(
          request.headers["last-event-id"] ??
            url.searchParams.get("lastEventId") ??
            0,
        ) || 0;
      const disconnect = session.connect(
        (event) =>
          response.write(
            `id: ${event.id}\nevent: robot\ndata: ${JSON.stringify(event)}\n\n`,
          ),
        last,
      );
      const heartbeat = setInterval(
        () => response.write(": heartbeat\n\n"),
        15_000,
      );
      request.once("close", () => {
        streams.delete(response);
        clearInterval(heartbeat);
        disconnect();
      });
      return;
    }
    const frameMatch =
      request.method === "GET" &&
      url.pathname.match(/^\/api\/frames\/([^/]+)\.png$/);
    if (frameMatch) {
      const path = session.framePath(decodeURIComponent(frameMatch[1]!));
      if (!path) throw new HttpError(404, "frame not found");
      let png: Buffer;
      try {
        png = await readFile(path);
      } catch {
        throw new HttpError(404, "frame not found");
      }
      response.writeHead(200, {
        "content-type": "image/png",
        "cache-control": "no-store",
        "content-length": png.length,
      });
      response.end(png);
      return;
    }
    if (request.method !== "POST") throw new HttpError(404, "not found");
    if (
      !request.headers["content-type"]
        ?.toLowerCase()
        .startsWith("application/json")
    )
      throw new HttpError(415, "application/json required");
    const body = record(await readJson(request));
    switch (url.pathname) {
      case "/api/doctor":
        return json(
          response,
          200,
          await session.doctor(
            body.platform ? [platform(body.platform)] : undefined,
          ),
        );
      case "/api/start": {
        const selected = platform(body.platform);
        const device = string(body.device, "device", { optional: true });
        const runtime = string(body.runtime, "runtime", { optional: true });
        try {
          session.assertCanStart(selected, true);
        } catch (error) {
          throw new HttpError(
            409,
            error instanceof Error ? error.message : String(error),
          );
        }
        void session.start(selected, { device, runtime }).catch(() => {});
        return json(response, 202, { accepted: true });
      }
      case "/api/scenario":
        await session.queueScenario(
          string(body.text, "text", { max: 200_000 })!,
        );
        return json(response, 202, { accepted: true });
      case "/api/observe":
        return json(
          response,
          200,
          (await session.observe("manual")).observation,
        );
      case "/api/action":
        return json(
          response,
          200,
          (await session.act(body.action, "manual")).observation,
        );
      case "/api/app": {
        const operation = string(body.operation, "operation");
        if (operation !== "restart" && operation !== "rebuild")
          throw new HttpError(400, "invalid app operation");
        return json(
          response,
          200,
          (await session.app(operation, "manual")).observation,
        );
      }
      case "/api/webview": {
        const value = await session.webview(body, "manual");
        return json(response, 200, {
          result: value.result,
          before: value.before,
          after: value.after.observation,
        });
      }
      case "/api/prompt":
        await session.sendPrompt(string(body.text, "text", { max: 200_000 })!);
        return json(response, 202, { accepted: true });
      case "/api/take-control":
        return json(response, 200, (await session.takeControl()).observation);
      case "/api/resume-agent":
        await session.resumeAgent();
        return json(response, 202, { accepted: true });
      case "/api/stop-agent":
        await session.stopAgent();
        return json(response, 200, { stopped: true });
      case "/api/respond": {
        const id = body.id;
        if (typeof id !== "string" && typeof id !== "number")
          throw new HttpError(400, "id must be a string or number");
        session.respondToAgent(id, body.result);
        return json(response, 200, { accepted: true });
      }
      case "/api/end":
        await session.end();
        return json(response, 200, { ended: true });
      default:
        throw new HttpError(404, "not found");
    }
  }

  await new Promise<void>((resolveListen, reject) => {
    server.once("error", reject);
    server.listen(options.port ?? 0, host, () => resolveListen());
  });
  const address = server.address();
  if (!address || typeof address === "string")
    throw new Error("Could not determine server port");
  actualPort = address.port;
  const url = `http://${urlHost(host)}:${actualPort}/`;
  void session.doctor().catch(() => {});
  return {
    host,
    port: actualPort,
    token,
    url,
    session,
    close: async () => {
      await session.end();
      for (const stream of streams) stream.end();
      streams.clear();
      const closed = new Promise<void>((done) => server.close(() => done()));
      server.closeAllConnections();
      await closed;
    },
  };
}

function authenticate(
  request: IncomingMessage,
  url: URL,
  expected: string,
): void {
  const supplied =
    request.headers["x-stash-token"] ?? url.searchParams.get("token");
  if (
    typeof supplied !== "string" ||
    supplied.length !== expected.length ||
    !timingSafeEqual(supplied, expected)
  )
    throw new HttpError(401, "invalid session token");
}
function timingSafeEqual(left: string, right: string): boolean {
  const a = Buffer.from(left);
  const b = Buffer.from(right);
  if (a.length !== b.length) return false;
  return safeEqual(a, b);
}
function assertSameOrigin(request: IncomingMessage, expected: string): void {
  const origin = request.headers.origin;
  if (!origin || origin !== expected)
    throw new HttpError(403, "same-origin request required");
  const fetchSite = request.headers["sec-fetch-site"];
  if (fetchSite && fetchSite !== "same-origin")
    throw new HttpError(403, "cross-site request rejected");
}
function urlHost(host: string): string {
  return host === "::1" ? "[::1]" : host;
}
function json(response: ServerResponse, status: number, body: unknown): void {
  const data = Buffer.from(JSON.stringify(body));
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": data.length,
    "cache-control": "no-store",
  });
  response.end(data);
}
function sendError(response: ServerResponse, error: unknown): void {
  if (response.headersSent) {
    response.end();
    return;
  }
  const status = error instanceof HttpError ? error.status : 500;
  json(response, status, {
    error: error instanceof Error ? error.message : String(error),
  });
}
async function serveStatic(
  response: ServerResponse,
  asset: string,
): Promise<void> {
  const candidates =
    asset === "app.js"
      ? [join(packageRoot, "dist/web/app.js")]
      : [join(packageRoot, asset)];
  let data: Buffer | undefined;
  for (const path of candidates) {
    try {
      data = await readFile(path);
      break;
    } catch {}
  }
  if (!data) throw new HttpError(404, "asset not built");
  const extension = extname(candidates[0]!);
  const type =
    asset === "app.js"
      ? "application/javascript; charset=utf-8"
      : extension === ".html"
        ? "text/html; charset=utf-8"
        : "text/css; charset=utf-8";
  response.writeHead(200, {
    "content-type": type,
    "content-length": data.length,
    "cache-control": "no-cache",
    "content-security-policy":
      "default-src 'self'; img-src 'self' blob: data:; connect-src 'self'; style-src 'self'; script-src 'self'; base-uri 'none'; frame-ancestors 'none'",
    "x-content-type-options": "nosniff",
  });
  response.end(data);
}
