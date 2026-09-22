import { deflateSync } from "node:zlib";
import type {
  AdapterOptions,
  DeviceAdapter,
  DeviceInfo,
  DoctorReport,
  RawFrame,
  RobotAction,
  WebViewAdapter,
} from "./contracts.js";

function crc32(data: Buffer): number {
  let crc = 0xffffffff;
  for (const byte of data) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++)
      crc = crc & 1 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type: string, data: Buffer): Buffer {
  const tag = Buffer.from(type);
  const size = Buffer.alloc(4);
  size.writeUInt32BE(data.length);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([tag, data])));
  return Buffer.concat([size, tag, data, crc]);
}
function screenshot(width: number, height: number, accent: boolean): Buffer {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 2;
  const pixels = Buffer.alloc((width * 3 + 1) * height);
  for (let y = 0; y < height; y++)
    for (let x = 0; x < width; x++) {
      const i = y * (width * 3 + 1) + 1 + x * 3;
      const card = x > 20 && x < width - 20 && y > 90 && y < height - 70;
      pixels[i] = card ? (accent ? 90 : 225) : 22;
      pixels[i + 1] = card ? (accent ? 180 : 232) : 30;
      pixels[i + 2] = card ? 235 : 46;
    }
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(pixels)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

/** Deterministic adapter for harness tests; never enabled implicitly. */
export function createFakeAdapter(
  options: AdapterOptions,
  platform: "android" | "ios" = "android",
): DeviceAdapter {
  let running = false;
  let css = "";
  let landscape = false;
  let text = "";
  let hasWebview = false;
  let coverageSince: string | undefined;
  const log = (source: "native" | "console", message: string) =>
    options.onLog({
      source,
      timestamp: new Date().toISOString(),
      level: "info",
      message,
    });
  const check = (signal?: AbortSignal) => {
    signal?.throwIfAborted();
    if (!running) throw new Error("Fake device is stopped");
  };
  const webview: WebViewAdapter = {
    status() {
      if (hasWebview) coverageSince ??= new Date().toISOString();
      return {
        connected: running && hasWebview,
        coverageSince,
        detail: "Fake adapter",
      };
    },
    async listTargets(signal) {
      check(signal);
      return hasWebview
        ? [
            {
              id: "fake-checkout",
              appId: "com.stash.stashnative.sample",
              title: "Test checkout",
              url: "https://test.stashpreview.com/",
            },
          ]
        : [];
    },
    async inspect(_target, selector, signal) {
      check(signal);
      if (!hasWebview) throw new Error("No WebView target");
      return {
        url: "https://test.stashpreview.com/",
        title: "Test checkout",
        css,
        elements: [
          {
            tag: "BODY",
            text,
            selector: selector || "body",
            bounds: { x: 0, y: 0, width: 320, height: 640 },
          },
        ],
      };
    },
    async evaluate(script, _target, signal) {
      check(signal);
      if (!hasWebview) throw new Error("No WebView target");
      log("console", "Fake evaluation");
      return { script, fake: true };
    },
    async setCss(value, _target, signal) {
      check(signal);
      css = value;
      return { css };
    },
    async resetCss(_target, signal) {
      check(signal);
      css = "";
      return { css };
    },
    async reload(_target, signal) {
      check(signal);
      css = "";
    },
    async stop() {
      hasWebview = false;
    },
  };
  return {
    platform,
    webview,
    async doctor(): Promise<DoctorReport> {
      return {
        platform,
        ready: true,
        checks: [
          {
            name: "Fake adapter",
            ok: true,
            detail: "No simulator or model is launched",
          },
        ],
        devices: [{ id: "fake", name: "Fake phone" }],
      };
    },
    async start(_settings, signal): Promise<DeviceInfo> {
      signal?.throwIfAborted();
      running = true;
      options.onProgress("Fake sample ready");
      log("native", "Sample started");
      return {
        platform,
        id: "fake",
        name: "Fake phone",
        runtime: "test",
        appId: "com.stash.stashnative.sample",
      };
    },
    async capture(signal): Promise<RawFrame> {
      check(signal);
      const width = landscape ? 640 : 320;
      const height = landscape ? 320 : 640;
      return {
        png: screenshot(width, height, !!css),
        width,
        height,
        logicalWidth: width,
        logicalHeight: height,
      };
    },
    async hierarchy(signal) {
      check(signal);
      return '<App><TextField accessibility-id="card-url-field"/><Button accessibility-id="card-open-button"/></App>';
    },
    async act(action: RobotAction, signal) {
      check(signal);
      if (action.type === "rotate")
        landscape = action.orientation === "landscape";
      if (action.type === "tap" || action.type === "tapElement")
        hasWebview = true;
      if (action.type === "type") text = action.text;
      log("native", `Action: ${action.type}`);
    },
    async restart(signal) {
      check(signal);
      hasWebview = false;
      css = "";
      log("native", "Sample restarted");
    },
    async rebuild(signal) {
      check(signal);
      options.onProgress("Fake build complete");
      hasWebview = false;
      css = "";
    },
    async stop() {
      running = false;
      hasWebview = false;
    },
    async reset() {
      if (running) throw new Error("End the session before reset");
      css = "";
      text = "";
      landscape = false;
    },
  };
}
