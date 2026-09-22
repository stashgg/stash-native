export type Platform = "android" | "ios";
export type LogSource =
  | "native"
  | "console"
  | "network"
  | "build"
  | "driver"
  | "harness";
export interface LogEntry {
  timestamp: string;
  source: LogSource;
  level: string;
  message: string;
  details?: unknown;
}
export interface Check {
  name: string;
  ok: boolean;
  detail: string;
}
export interface DeviceChoice {
  id: string;
  name: string;
  runtime?: string;
}
export interface DoctorReport {
  platform: Platform;
  ready: boolean;
  checks: Check[];
  devices: DeviceChoice[];
  runtimes?: DeviceChoice[];
}
export interface AdapterOptions {
  repoRoot: string;
  cacheDir: string;
  onLog: (entry: LogEntry) => void;
  onProgress: (message: string) => void;
}
export interface StartOptions {
  device?: string;
  runtime?: string;
}
export interface DeviceInfo {
  platform: Platform;
  id: string;
  name: string;
  runtime: string;
  appId: string;
}
export interface RawFrame {
  png: Buffer;
  width: number;
  height: number;
  /** Native interaction bounds; screenshot pixels may differ on iOS. */
  logicalWidth: number;
  logicalHeight: number;
}
export interface Observation {
  debugger?: DebuggerStatus;
  activeCss?: string;
  frameId: string;
  capturedAt: string;
  width: number;
  height: number;
  logicalWidth: number;
  logicalHeight: number;
  orientation: "portrait" | "landscape";
  imagePath: string;
  imageUrl: string;
  hierarchy?: string;
  targets?: WebViewTarget[];
}
/** Coordinate inputs are fractions of the complete device screen, from 0 to 1. */
export type RobotAction =
  | { type: "tap"; x: number; y: number; frameId: string }
  | {
      type: "swipe";
      fromX: number;
      fromY: number;
      toX: number;
      toY: number;
      durationMs?: number;
      frameId: string;
    }
  | { type: "tapElement"; selector: string }
  | { type: "type"; text: string; selector?: string }
  | { type: "back" | "hideKeyboard" | "home" }
  | { type: "rotate"; orientation: "portrait" | "landscape" };
export interface WebViewTarget {
  id: string;
  appId: string;
  url: string;
  title: string;
}
/** evaluate accepts a JavaScript expression, including async IIFEs, and returns its JSON value. */
export interface DebuggerStatus {
  connected: boolean;
  coverageSince?: string;
  detail?: string;
}
export interface WebViewAdapter {
  status?(): DebuggerStatus;
  listTargets(signal?: AbortSignal): Promise<WebViewTarget[]>;
  inspect(
    targetId?: string,
    selector?: string,
    signal?: AbortSignal,
  ): Promise<unknown>;
  evaluate(
    script: string,
    targetId?: string,
    signal?: AbortSignal,
  ): Promise<unknown>;
  setCss(
    css: string,
    targetId?: string,
    signal?: AbortSignal,
  ): Promise<unknown>;
  resetCss(targetId?: string, signal?: AbortSignal): Promise<unknown>;
  reload(targetId?: string, signal?: AbortSignal): Promise<void>;
  pollLogs?(signal?: AbortSignal): Promise<void>;
  stop(): Promise<void>;
}
export interface DeviceAdapter {
  readonly platform: Platform;
  readonly webview: WebViewAdapter;
  doctor(): Promise<DoctorReport>;
  start(options: StartOptions, signal?: AbortSignal): Promise<DeviceInfo>;
  capture(signal?: AbortSignal): Promise<RawFrame>;
  hierarchy(signal?: AbortSignal): Promise<string>;
  act(action: RobotAction, signal?: AbortSignal): Promise<void>;
  restart(signal?: AbortSignal): Promise<void>;
  rebuild(signal?: AbortSignal): Promise<void>;
  stop(): Promise<void>;
  /** Erase only the harness-owned device while no session is running. */
  reset(options?: StartOptions): Promise<void>;
}
export interface RobotEvent {
  id: number;
  timestamp: string;
  type:
    | "state"
    | "progress"
    | "frame"
    | "log"
    | "agent"
    | "tool"
    | "error"
    | "request";
  data: unknown;
}
