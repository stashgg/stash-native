/**
 * Selected protocol bindings generated with:
 * codex-cli 0.153.4 app-server generate-ts --experimental
 *
 * Kept as one file so protocol drift is reviewable without vendoring the full
 * generated schema. Do not change wire names without regenerating the types.
 */

export const CODEX_PROTOCOL_VERSION = "0.153.4";

export type JsonValue =
  | null
  | boolean
  | number
  | string
  | JsonValue[]
  | { [key: string]: JsonValue };

export interface InitializeParams {
  clientInfo: { name: string; title: string; version: string };
  capabilities?: {
    experimentalApi?: boolean;
    optOutNotificationMethods?: string[];
    mcpServerOpenaiFormElicitation?: boolean;
  };
}

export interface DynamicToolFunctionSpec {
  type: "function";
  name: string;
  description: string;
  inputSchema: JsonValue;
  deferLoading?: boolean;
}

export interface ThreadStartParams {
  model?: string | null;
  cwd?: string | null;
  approvalPolicy?: "untrusted" | "on-request" | "never";
  sandbox?: "read-only" | "workspace-write" | "danger-full-access";
  serviceName?: string | null;
  baseInstructions?: string | null;
  developerInstructions?: string | null;
  ephemeral?: boolean | null;
  dynamicTools?: DynamicToolFunctionSpec[] | null;
}

export type UserInput =
  | { type: "text"; text: string; text_elements: [] }
  | { type: "image"; detail?: "low" | "high" | "auto"; url: string }
  | { type: "localImage"; detail?: "low" | "high" | "auto"; path: string };

export interface TurnStartParams {
  threadId: string;
  input: UserInput[];
  cwd?: string | null;
  approvalPolicy?: "untrusted" | "on-request" | "never";
  sandboxPolicy?: { type: "readOnly"; networkAccess: boolean };
  model?: string | null;
  effort?: string | null;
}

export interface TurnSteerParams {
  threadId: string;
  input: UserInput[];
  expectedTurnId: string;
}

export interface DynamicToolCallParams {
  threadId: string;
  turnId: string;
  callId: string;
  namespace: string | null;
  tool: string;
  arguments: JsonValue;
}

export type DynamicToolOutputItem =
  | { type: "inputText"; text: string }
  | { type: "inputImage"; imageUrl: string };

export interface DynamicToolCallResponse {
  contentItems: DynamicToolOutputItem[];
  success: boolean;
}

export interface ToolRequestUserInputParams {
  threadId: string;
  turnId: string;
  itemId: string;
  isBlocking: boolean;
  autoResolutionMs: number | null;
  questions: Array<{
    id: string;
    header: string;
    question: string;
    isOther: boolean;
    isSecret: boolean;
    options: Array<{ label: string; description: string }> | null;
  }>;
}

export interface JsonRpcRequest {
  id: string | number;
  method: string;
  params?: unknown;
}
export interface JsonRpcNotification {
  method: string;
  params?: unknown;
}
export interface JsonRpcResponse {
  id: string | number;
  result?: unknown;
  error?: { code: number; message: string; data?: unknown };
}
export type JsonRpcMessage =
  | JsonRpcRequest
  | JsonRpcNotification
  | JsonRpcResponse;

export function isServerRequest(
  message: JsonRpcMessage,
): message is JsonRpcRequest {
  return "id" in message && "method" in message;
}

export function isResponse(
  message: JsonRpcMessage,
): message is JsonRpcResponse {
  return "id" in message && !("method" in message);
}
