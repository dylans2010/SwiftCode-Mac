/**
 * Public entry point for `@swiftcode/sdk` — the real TypeScript SDK for
 * writing SwiftCode extensions.
 *
 * Extensions talk to the SwiftCode host over an NDJSON stdio IPC channel
 * (Docs/Intro-to-SDK.md §10.4). This package implements the IPC client
 * (`createStdioConnection`), the error type (`SDKError`), and the full
 * developer-facing context (`createContext`) — not just the types.
 */

export type {
  SwiftCodeExtension,
  ExtensionInfo,
  ProjectInfo,
  ProjectAPI,
  FileChangeStatus,
  FileChangeSummary,
  RepositoryStatus,
  DiffOptions,
  FileDiff,
  RepositoryDiff,
  SourceControlAPI,
  CloudModelHistoryEntry,
  CloudModelRequest,
  CloudModelAPI,
  BuildRequest,
  BuildOutputEvent,
  BuildStatus,
  BuildDiagnostic,
  BuildResult,
  BuildHandle,
  BuildAPI,
  CommandDefinition,
  CommandAPI,
  Disposable,
  EventListener,
  EventAPI,
  Logger,
  DisposableStore,
  SwiftCodeContext,
  TerminalSandboxRequest,
  TerminalSandboxResult,
  TerminalSandboxAPI,
  UIAPI,
  SecurityAPI,
  SecurityAddOptions,
  SecurityAddedValue,
  SecurityStoredValue,
  SecurityHTTPRequest,
  SecurityOperation,
  SecurityHTTPResponse,
  SDKErrorShape,
  AssistAPI,
  AssistUIAPI,
  AssistSessionInfo,
  AssistSessionOptions,
  AssistStreamChunk,
  AssistToolCall,
  AssistToolResult,
} from "./types.js";
export { SDKAssistAccessError, ASSIST_ACCESS_DENIED_MESSAGE } from "./types.js";
export { SDKCloudModelAccessError, CLOUD_MODEL_ACCESS_DENIED_MESSAGE } from "./types.js";

export {
  SDKError,
  SDK_PROTOCOL_VERSION,
  REQUEST_TIMEOUT_MS,
  createStdioConnection,
} from "./ipc.js";
export type {
  HostConnection,
  HostEvent,
  HostEventListener,
} from "./ipc.js";

export { createContext } from "./context.js";
export type { CreatedContext } from "./context.js";

export { SNIPPETS, searchSnippets, getSnippet } from "./snippets.js";
export type { Snippet } from "./snippets.js";

export {
  createSecurityAPI,
  securityAddValue,
  securityHasValue,
  securityListValueIDs,
  securityDeleteValue,
  securityUseValue,
} from "./security.js";

export { createAssistAPI } from "./assist.js";
export { createAssistUIAPI, ASSIST_VIEW_ID } from "./assistUI.js";

export { SCOPES_ID_LIST, SCOPES_BY_ID } from "./ScopesIDLists.js";
export type { ScopeIDEntry, ScopeKind } from "./ScopesIDLists.js";
