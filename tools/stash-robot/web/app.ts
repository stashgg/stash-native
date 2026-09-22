import type {
  DebuggerStatus,
  DoctorReport,
  LogEntry,
  Observation,
  Platform,
  RobotAction,
  RobotEvent,
  WebViewTarget,
} from "../src/contracts.js";
import type { SessionSnapshot } from "../src/session.js";
const $ = <T extends HTMLElement = HTMLElement>(selector: string): T => {
  const element = document.querySelector<T>(selector);
  if (!element) throw new Error(`Missing interface element: ${selector}`);
  return element;
};
const tokenKey = `stash-robot:${location.origin}`;
const token =
  new URLSearchParams(location.hash.slice(1)).get("token") ||
  sessionStorage.getItem(tokenKey);
if (!token) {
  document.body.textContent =
    "Open the local URL printed by stash-robot to connect to this session.";
  throw new Error("Missing session token");
}
sessionStorage.setItem(tokenKey, token);
history.replaceState(null, "", `${location.pathname}${location.search}`);
let state: SessionSnapshot | null = null;
let observation: Observation | null = null;
let selectedPlatform: Platform = "android";
let lastEventId = 0,
  frameVersion = 0;
let manualBusy = false;
let frameRequest: AbortController | undefined;
let liveUrl: string | undefined;
let comparisonUrls: string[] = [];
let toastTimer: ReturnType<typeof setTimeout> | undefined;
let pointer: {
  x: number;
  y: number;
  id: number;
  at: number;
  frameId: string;
  rect: DOMRect;
} | null = null;
const agentBubbles = new Map<string, HTMLElement>();
const completedItems = new Set<string>();
const record = (value: unknown): Record<string, unknown> =>
  value && typeof value === "object" ? (value as Record<string, unknown>) : {};
const errorText = (error: unknown): string =>
  error instanceof Error ? error.message : String(error);
async function api<T = unknown>(path: string, body?: unknown): Promise<T> {
  const response = await fetch(path, {
    method: body === undefined ? "GET" : "POST",
    headers: {
      "x-stash-token": token!,
      ...(body === undefined ? {} : { "content-type": "application/json" }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data: unknown = await response.json().catch(() => ({}));
  if (!response.ok)
    throw new Error(
      String(record(data).error || `${response.status} ${response.statusText}`),
    );
  return data as T;
}
async function showFrame(next: Observation): Promise<void> {
  if (!next?.frameId || next.frameId === observation?.frameId) return;
  const version = ++frameVersion;
  frameRequest?.abort();
  frameRequest = new AbortController();
  let imageUrl: string | undefined;
  try {
    const response = await fetch(next.imageUrl, {
      headers: { "x-stash-token": token! },
      signal: frameRequest.signal,
    });
    if (!response.ok) return;
    imageUrl = URL.createObjectURL(await response.blob());
    const preload = new Image();
    preload.src = imageUrl;
    await preload.decode();
    if (version !== frameVersion) {
      URL.revokeObjectURL(imageUrl);
      return;
    }
    const previous = liveUrl;
    liveUrl = imageUrl;
    $("#screen").setAttribute("src", imageUrl);
    $("#screen").classList.add("visible");
    $("#screenEmpty").classList.add("hidden");
    observation = next;
    $("#timestamp").textContent =
      `Captured ${new Date(next.capturedAt).toLocaleTimeString()}`;
    $("#frameId").textContent = next.frameId;
    if (next.targets) updateTargets(next.targets);
    renderDebugger(next.debugger);
    if (next.activeCss !== undefined)
      $("#activeCss").textContent = next.activeCss || "No active CSS override";
    if (previous) URL.revokeObjectURL(previous);
  } catch (error) {
    if (imageUrl && imageUrl !== liveUrl) URL.revokeObjectURL(imageUrl);
    if (!(error instanceof DOMException && error.name === "AbortError"))
      toast(errorText(error));
  }
}
function renderState(next: SessionSnapshot): void {
  state = next;
  const ready = next.phase === "ready",
    starting = next.phase === "starting";
  $("#phase").textContent =
    `${next.phase}${next.platform ? ` · ${next.platform}` : ""}`;
  $("#selectScreen").classList.toggle(
    "hidden",
    ready || next.phase === "ended",
  );
  $("#workspace").classList.toggle("hidden", !ready);
  $("#diagnostics").classList.toggle("hidden", !ready);
  $("#ended").classList.toggle("hidden", next.phase !== "ended");
  $("#takeControl").toggleAttribute(
    "disabled",
    !ready || next.control === "manual",
  );
  $("#resumeAgent").toggleAttribute(
    "disabled",
    !ready || next.control !== "manual",
  );
  $("#stopAgent").toggleAttribute(
    "disabled",
    !ready || next.control === "stopped",
  );
  $("#endSession").toggleAttribute(
    "disabled",
    next.phase === "stopping" || next.phase === "ended",
  );
  $("#screenWrap").classList.toggle("manual", next.control === "manual");
  $("#controlMode").textContent =
    next.control === "manual"
      ? "Manual control"
      : next.control === "stopped"
        ? "Agent stopped"
        : "Agent control";
  $("#prompt").toggleAttribute("disabled", !ready || next.control === "manual");
  $("#promptForm button").toggleAttribute(
    "disabled",
    !ready || next.control === "manual",
  );
  setManualEnabled();
  document
    .querySelector('[data-action="back"]')
    ?.classList.toggle("hidden", next.platform === "ios");
  renderPlatforms(next.doctors || {}, starting);
  renderLogs(next.logs || []);
  renderRequests(next.requests || []);
  $("#activeCss").textContent = next.activeCss || "No active CSS override";
  renderDebugger(next.debugger);
  if (next.observation && next.phase !== "ended" && next.phase !== "stopping")
    void showFrame(next.observation);
  if (next.error) toast(next.error);
}
function renderDebugger(status?: DebuggerStatus): void {
  $("#debuggerStatus").textContent = status
    ? `${status.connected ? "WebView debugger connected" : "WebView debugger disconnected"}${status.coverageSince ? ` · Log coverage from ${new Date(status.coverageSince).toLocaleTimeString()}` : ""}${status.detail ? ` · ${status.detail}` : ""}`
    : "WebView debugger has not attached.";
}
function setManualEnabled(): void {
  document
    .querySelectorAll<HTMLButtonElement>(
      "[data-action],[data-app],#typeForm button,[data-debug]",
    )
    .forEach((el) => {
      el.disabled = state?.control !== "manual" || manualBusy;
    });
  $("#debugHint").textContent =
    state?.control === "manual"
      ? "Changes affect the current document only."
      : "Take control to use the diagnostics controls.";
}
function renderPlatforms(
  doctors: Partial<Record<Platform, DoctorReport>>,
  starting: boolean,
): void {
  const holder = $("#platforms");
  holder.replaceChildren();
  for (const name of ["android", "ios"] as const) {
    const report = doctors[name],
      card = document.createElement("button");
    card.className = `platform-card ${selectedPlatform === name ? "selected" : ""}`;
    card.disabled = starting;
    card.setAttribute("aria-pressed", String(selectedPlatform === name));
    const heading = document.createElement("div");
    heading.className = "platform-heading";
    const title = document.createElement("strong");
    title.textContent = name === "ios" ? "iOS" : "Android";
    const status = document.createElement("span");
    status.className = `platform-status ${report ? (report.ready ? "check-ok" : "check-fail") : "muted"}`;
    status.textContent = report
      ? report.ready
        ? "Ready"
        : "Needs attention"
      : "Checking…";
    heading.append(title, status);
    card.append(heading);
    const list = document.createElement("ul");
    list.className = "checks";
    for (const check of report?.checks || []) {
      const item = document.createElement("li");
      item.className = check.ok ? "check-ok" : "check-fail";
      const label =
        check.name === "Simulator app conflict"
          ? "Simulator availability"
          : check.name;
      item.title = check.detail;
      item.setAttribute(
        "aria-label",
        `${label}: ${check.ok ? "Passed" : `Needs attention. ${check.detail}`}`,
      );
      const icon = document.createElement("span");
      icon.className = "check-icon";
      icon.setAttribute("aria-hidden", "true");
      icon.textContent = check.ok ? "✓" : "!";
      const text = document.createElement("span");
      text.className = "check-label";
      text.textContent = label;
      if (!check.ok) {
        const detail = document.createElement("small");
        detail.className = "check-detail";
        detail.textContent = check.detail;
        text.append(detail);
      }
      item.append(icon, text);
      list.append(item);
    }
    card.append(list);
    card.onclick = () => {
      selectedPlatform = name;
      fillAdvanced(report);
      if (state) renderState(state);
    };
    holder.append(card);
  }
  const selected = doctors[selectedPlatform];
  if (!$("#device").dataset.loaded && selected) fillAdvanced(selected);
  $("#startPlatform").toggleAttribute("disabled", starting || !selected?.ready);
  $("#startPlatform").textContent = starting
    ? "Starting…"
    : `Start ${selectedPlatform === "ios" ? "iOS" : "Android"}`;
}
function fillAdvanced(report?: DoctorReport): void {
  fillSelect($("#device"), "Default phone", report?.devices || []);
  fillSelect(
    $("#runtime"),
    "Default compatible runtime",
    report?.runtimes || [],
  );
  $("#device").dataset.loaded = report?.platform || "";
  $("#runtimeLabel").classList.toggle("hidden", !report?.runtimes?.length);
}
function fillSelect(
  select: HTMLSelectElement,
  label: string,
  choices: {
    id: string;
    name: string;
    runtime?: string;
  }[],
): void {
  select.replaceChildren(new Option(label, ""));
  for (const choice of choices)
    select.add(
      new Option(
        choice.runtime ? `${choice.name} · ${choice.runtime}` : choice.name,
        choice.id,
      ),
    );
}
function renderLogs(logs: LogEntry[]): void {
  const source = $<HTMLSelectElement>("#logSource").value;
  $("#logs").textContent = logs
    .filter((entry) => !source || entry.source === source)
    .slice(-250)
    .map(
      (entry) =>
        `${entry.timestamp.slice(11, 19)} [${entry.source}/${entry.level}] ${entry.message}`,
    )
    .join("\n");
}
function addMessage(kind: string, text: string): HTMLElement {
  const item = document.createElement("div");
  item.className = `message ${kind}`;
  item.textContent = text;
  $("#chat").append(item);
  $("#chat").scrollTop = $("#chat").scrollHeight;
  return item;
}
function renderRequests(requests: SessionSnapshot["requests"]): void {
  const holder = $("#requests");
  holder.replaceChildren();
  for (const request of requests) {
    const params = record(request.params),
      card = document.createElement("div");
    card.className = "request";
    const title = document.createElement("strong");
    title.textContent = request.method;
    card.append(title);
    const details = document.createElement("pre");
    details.textContent = JSON.stringify(params, null, 2);
    card.append(details);
    const controls = document.createElement("div");
    controls.className = "controls";
    if (request.method === "item/tool/requestUserInput") {
      const inputs: Record<string, HTMLInputElement> = {};
      for (const raw of Array.isArray(params.questions)
        ? params.questions
        : []) {
        const question = record(raw),
          label = document.createElement("label");
        label.textContent = String(question.question || "");
        const input = document.createElement("input");
        input.autocomplete = "off";
        if (Array.isArray(question.options)) {
          const hint = document.createElement("small");
          hint.textContent = question.options
            .map((option) => String(record(option).label || ""))
            .join(" / ");
          label.append(hint);
        }
        inputs[String(question.id)] = input;
        label.append(input);
        card.append(label);
      }
      button(controls, "Submit", () =>
        respond(request.id, {
          answers: Object.fromEntries(
            Object.entries(inputs).map(([id, input]) => [
              id,
              { answers: [input.value] },
            ]),
          ),
        }),
      );
    } else if (
      request.method === "item/commandExecution/requestApproval" ||
      request.method === "item/fileChange/requestApproval"
    ) {
      const explanation = document.createElement("p");
      explanation.textContent =
        "This worker has read-only repository access. Escalated commands and source changes are outside this session.";
      card.append(explanation);
      button(controls, "Decline", () =>
        respond(request.id, { decision: "decline" }),
      );
    } else if (request.method === "item/permissions/requestApproval") {
      const explanation = document.createElement("p");
      explanation.textContent =
        "This session keeps the worker in its read-only sandbox. Device and WebView operations use the robot tools.";
      card.append(explanation);
      button(controls, "Decline", () =>
        respond(request.id, { permissions: {}, scope: "turn" }),
      );
    } else {
      const info = document.createElement("p");
      info.textContent =
        "This request needs a supported response from the harness. Stop the agent to cancel.";
      card.append(info);
    }
    card.append(controls);
    holder.append(card);
  }
}
function button(
  parent: HTMLElement,
  label: string,
  action: () => Promise<void>,
): void {
  const el = document.createElement("button");
  el.textContent = label;
  el.onclick = () => {
    void action().catch((error) => toast(errorText(error)));
  };
  parent.append(el);
}
async function respond(id: string | number, result: unknown): Promise<void> {
  await api("/api/respond", { id, result });
  if (state) {
    state.requests = state.requests.filter((item) => item.id !== id);
    renderRequests(state.requests);
  }
}
function updateTargets(targets: WebViewTarget[]): void {
  const select = $<HTMLSelectElement>("#target"),
    prior = select.value;
  select.replaceChildren(new Option("Automatic target", ""));
  for (const target of targets)
    select.add(
      new Option(`${target.title || "(untitled)"} · ${target.url}`, target.id),
    );
  if ([...select.options].some((option) => option.value === prior))
    select.value = prior;
}
async function showComparison(
  before: Observation,
  after: Observation,
): Promise<void> {
  const urls: string[] = [];
  try {
    for (const frame of [before, after]) {
      const response = await fetch(frame.imageUrl, {
        headers: { "x-stash-token": token! },
      });
      if (!response.ok)
        throw new Error("Comparison screenshot is no longer available");
      urls.push(URL.createObjectURL(await response.blob()));
    }
    $("#beforeImage").setAttribute("src", urls[0]!);
    $("#afterImage").setAttribute("src", urls[1]!);
    $("#comparison").classList.remove("hidden");
    for (const url of comparisonUrls) URL.revokeObjectURL(url);
    comparisonUrls = urls;
  } catch (error) {
    for (const url of urls) URL.revokeObjectURL(url);
    toast(errorText(error));
  }
}
async function diagnostic(
  operation: string,
  extras: Record<string, unknown> = {},
): Promise<void> {
  await manualOperation(async () => {
    const value = await api<{
      result: unknown;
      before?: Observation;
      after: Observation;
    }>("/api/webview", {
      operation,
      targetId: $<HTMLSelectElement>("#target").value || undefined,
      ...extras,
    });
    $("#diagnosticResult").textContent = JSON.stringify(value.result, null, 2);
    if (operation === "targets") updateTargets(value.result as WebViewTarget[]);
    const result = record(value.result);
    if (typeof result.css === "string")
      $("#activeCss").textContent = result.css || "No active CSS override";
    if (value.before) await showComparison(value.before, value.after);
    await showFrame(value.after);
  });
}
function toast(message: string): void {
  $("#toast").textContent = message;
  $("#toast").classList.add("visible");
  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = setTimeout(() => $("#toast").classList.remove("visible"), 7000);
}
function point(
  event: PointerEvent,
  rect: DOMRect,
): {
  x: number;
  y: number;
} {
  return {
    x: Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width)),
    y: Math.max(0, Math.min(1, (event.clientY - rect.top) / rect.height)),
  };
}
async function manualOperation(operation: () => Promise<void>): Promise<void> {
  if (manualBusy || state?.control !== "manual") return;
  manualBusy = true;
  setManualEnabled();
  try {
    await operation();
  } catch (error) {
    toast(errorText(error));
  } finally {
    manualBusy = false;
    setManualEnabled();
  }
}
async function manualAction(action: RobotAction): Promise<void> {
  await manualOperation(async () =>
    showFrame(await api<Observation>("/api/action", { action })),
  );
}
$("#screen").addEventListener("pointerdown", (event) => {
  if (state?.control !== "manual" || manualBusy || !observation) return;
  const rect = $("#screen").getBoundingClientRect();
  pointer = {
    ...point(event, rect),
    id: event.pointerId,
    at: Date.now(),
    frameId: observation.frameId,
    rect,
  };
  $("#screen").setPointerCapture(event.pointerId);
});
$("#screen").addEventListener("pointerup", (event) => {
  if (!pointer || pointer.id !== event.pointerId) return;
  const start = pointer;
  pointer = null;
  const to = point(event, start.rect);
  void manualAction(
    Math.hypot(to.x - start.x, to.y - start.y) < 0.025
      ? { type: "tap", x: to.x, y: to.y, frameId: start.frameId }
      : {
          type: "swipe",
          fromX: start.x,
          fromY: start.y,
          toX: to.x,
          toY: to.y,
          durationMs: Math.max(100, Math.min(3000, Date.now() - start.at)),
          frameId: start.frameId,
        },
  );
});
$("#screen").addEventListener("pointercancel", () => {
  pointer = null;
});
document.querySelectorAll<HTMLButtonElement>("[data-action]").forEach((el) => {
  el.onclick = () => {
    const type = el.dataset.action;
    if (type === "rotate")
      void manualAction({
        type,
        orientation:
          observation?.orientation === "portrait" ? "landscape" : "portrait",
      });
    else if (type === "back" || type === "hideKeyboard" || type === "home")
      void manualAction({ type });
  };
});
document.querySelectorAll<HTMLButtonElement>("[data-app]").forEach((el) => {
  el.onclick = () =>
    void manualOperation(async () =>
      showFrame(
        await api<Observation>("/api/app", { operation: el.dataset.app }),
      ),
    );
});
$("#typeForm").onsubmit = (event) => {
  event.preventDefault();
  void manualAction({
    type: "type",
    text: $<HTMLInputElement>("#typeText").value,
  });
};
$("#promptForm").onsubmit = (event) => {
  event.preventDefault();
  const input = $<HTMLTextAreaElement>("#prompt"),
    text = input.value.trim();
  if (!text) return;
  input.value = "";
  void api("/api/prompt", { text }).catch((error) => toast(errorText(error)));
};
for (const [selector, route] of [
  ["#takeControl", "take-control"],
  ["#resumeAgent", "resume-agent"],
  ["#stopAgent", "stop-agent"],
  ["#endSession", "end"],
] as const)
  $(selector).onclick = () => {
    void api(`/api/${route}`, {}).catch((error) => toast(errorText(error)));
  };
$("#startPlatform").onclick = () => {
  $("#progress").textContent = `Starting ${selectedPlatform}…`;
  void api("/api/start", {
    platform: selectedPlatform,
    device: $<HTMLSelectElement>("#device").value || undefined,
    runtime: $<HTMLSelectElement>("#runtime").value || undefined,
  }).catch((error) => toast(errorText(error)));
};
$("#recheck").onclick = () => {
  void api("/api/doctor", {}).catch((error) => toast(errorText(error)));
};
$("#targets").onclick = () => void diagnostic("targets");
$("#inspect").onclick = () =>
  void diagnostic("inspect", {
    selector: $<HTMLInputElement>("#selector").value || "body",
  });
$("#reload").onclick = () => void diagnostic("reload");
$("#evaluate").onclick = () =>
  void diagnostic("evaluate", {
    script: $<HTMLTextAreaElement>("#script").value,
  });
$("#applyCss").onclick = () =>
  void diagnostic("setCss", { css: $<HTMLTextAreaElement>("#css").value });
$("#resetCss").onclick = () => void diagnostic("resetCss");
$("#logSource").onchange = () => renderLogs(state?.logs || []);
function agentEvent(data: Record<string, unknown>): void {
  if (data.kind === "user") {
    addMessage("user", String(data.text || ""));
    return;
  }
  const method = String(data.method || ""),
    params = record(data.params),
    item = record(params.item);
  if (method === "item/agentMessage/delta") {
    const id = String(params.itemId || params.turnId || "current");
    if (completedItems.has(id)) return;
    let bubble = agentBubbles.get(id);
    if (!bubble) {
      bubble = addMessage("agent", "");
      agentBubbles.set(id, bubble);
    }
    bubble.textContent += String(params.delta || "");
  } else if (method === "item/completed" && item.type === "agentMessage") {
    const id = String(item.id || "current");
    let bubble = agentBubbles.get(id);
    if (!bubble) {
      bubble = addMessage("agent", "");
      agentBubbles.set(id, bubble);
    }
    bubble.textContent = String(item.text || "");
    completedItems.add(id);
  } else if (method === "turn/completed") {
    const turn = record(params.turn);
    if (turn.status === "failed")
      toast(String(record(turn.error).message || "Agent turn failed"));
  }
}
function handleEvent(event: RobotEvent): void {
  if (event.id <= lastEventId) return;
  lastEventId = event.id;
  const data = record(event.data);
  switch (event.type) {
    case "state":
      renderState(event.data as SessionSnapshot);
      break;
    case "frame":
      void showFrame(event.data as Observation);
      break;
    case "progress":
      $("#progress").textContent = (
        $("#progress").textContent + `\n${data.message}`
      ).slice(-14000);
      break;
    case "log":
      if (state) {
        state.logs = [...state.logs, event.data as LogEntry].slice(-300);
        renderLogs(state.logs);
      }
      break;
    case "request":
      if (state) {
        const request = event.data as SessionSnapshot["requests"][number];
        state.requests = [
          ...state.requests.filter((item) => item.id !== request.id),
          request,
        ];
        renderRequests(state.requests);
      }
      break;
    case "agent":
      agentEvent(data);
      break;
    case "tool": {
      agentEvent(data);
      const params = record(data.params),
        item = record(params.item);
      if (data.method === "item/tool/call")
        addMessage("tool", `Running ${String(params.tool || "device tool")}`);
      else if (
        data.method === "item/completed" &&
        item.type !== "agentMessage" &&
        item.type !== "reasoning"
      )
        addMessage("tool", `${String(item.type || "Operation")} completed`);
      if (data.kind === "webview") {
        $("#diagnosticResult").textContent = JSON.stringify(
          data.result,
          null,
          2,
        );
        if (data.before && data.after)
          void showComparison(
            data.before as Observation,
            data.after as Observation,
          );
      }
      break;
    }
    case "error":
      toast(String(data.message || JSON.stringify(data)));
      break;
  }
}
function connectEvents(): void {
  const events = new EventSource(
    `/api/events?token=${encodeURIComponent(token!)}&lastEventId=${lastEventId}`,
  );
  events.onopen = () => {
    $("#connection").textContent = "Connected";
  };
  events.addEventListener("robot", (raw) => {
    try {
      handleEvent(JSON.parse((raw as MessageEvent).data) as RobotEvent);
    } catch (error) {
      toast(errorText(error));
    }
  });
  events.onerror = () => {
    $("#connection").textContent = "Reconnecting";
    events.close();
    setTimeout(connectEvents, 1000);
  };
}
try {
  renderState(await api<SessionSnapshot>("/api/bootstrap"));
  connectEvents();
} catch (error) {
  toast(errorText(error));
}
