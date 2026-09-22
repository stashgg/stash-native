// GENERATED CODE SNAPSHOT. DO NOT MODIFY BY HAND.
// Source: codex-cli 0.153.4 app-server generate-ts --experimental
// Selected experimental types used by stash-robot.

export type JsonValue =
  | null
  | boolean
  | number
  | string
  | JsonValue[]
  | { [key in string]?: JsonValue };

export type DynamicToolFunctionSpec = {
  name: string;
  description: string;
  inputSchema: JsonValue;
  deferLoading?: boolean;
};

export type DynamicToolSpec = { type: "function" } & DynamicToolFunctionSpec;

export type DynamicToolCallParams = {
  threadId: string;
  turnId: string;
  callId: string;
  namespace: string | null;
  tool: string;
  arguments: JsonValue;
};

export type DynamicToolCallOutputContentItem =
  | { type: "inputText"; text: string }
  | { type: "inputImage"; imageUrl: string }
  | { type: "inputAudio"; audioUrl: string };

export type DynamicToolCallResponse = {
  contentItems: Array<DynamicToolCallOutputContentItem>;
  success: boolean;
};

export type ToolRequestUserInputQuestion = {
  id: string;
  header: string;
  question: string;
  isOther: boolean;
  isSecret: boolean;
  options: Array<{ label: string; description: string }> | null;
};

export type ToolRequestUserInputParams = {
  threadId: string;
  turnId: string;
  itemId: string;
  questions: Array<ToolRequestUserInputQuestion>;
  isBlocking: boolean;
  autoResolutionMs: number | null;
};
