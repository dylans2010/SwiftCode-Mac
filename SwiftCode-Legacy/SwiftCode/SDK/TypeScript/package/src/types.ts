export interface SwiftCodeExtension {
  readonly id: string;
  activate(context: SwiftCodeContext): Promise<void>;
  deactivate(): Promise<void>;
}

export interface ExtensionInfo {
  readonly id: string;
  readonly name: string;
  readonly version: string;
}

export interface ProjectInfo {
  readonly id: string;
  readonly name: string;
  readonly rootPath: string;
  readonly isOpen: boolean;
}

export interface ProjectAPI {
  getCurrent(): Promise<ProjectInfo | null>;
}

export type FileChangeStatus =
  | "modified"
  | "added"
  | "deleted"
  | "renamed"
  | "untracked"
  | "conflicted";

export interface FileChangeSummary {
  readonly path: string;
  readonly status: FileChangeStatus;
  readonly isStaged: boolean;
}

export interface RepositoryStatus {
  readonly isRepository: boolean;
  readonly branchName?: string;
  readonly ahead: number;
  readonly behind: number;
  readonly stagedCount: number;
  readonly unstagedCount: number;
  readonly untrackedCount: number;
  readonly files: readonly FileChangeSummary[];
}

export interface DiffOptions {
  readonly maxBytes?: number;
  readonly includeUntracked?: boolean;
  readonly paths?: readonly string[];
}

export interface FileDiff {
  readonly path: string;
  readonly hunks: readonly string[];
  readonly truncated: boolean;
}

export interface RepositoryDiff {
  readonly files: readonly FileDiff[];
  readonly truncated: boolean;
  readonly totalBytes: number;
  readonly byteLimit: number;
}

export interface SourceControlAPI {
  getStatus(): Promise<RepositoryStatus>;
  getDiff(options?: DiffOptions): Promise<RepositoryDiff>;
}

export interface BuildRequest {
  readonly target: string;
  readonly configuration?: string;
  readonly destination?: string;
}

export interface BuildOutputEvent {
  readonly kind: "stdout" | "stderr" | "status";
  readonly text: string;
  readonly timestamp: number;
}

export type BuildStatus =
  | "running"
  | "succeeded"
  | "failed"
  | "cancelled"
  | "timedOut";

export interface BuildDiagnostic {
  readonly file?: string;
  readonly line?: number;
  readonly message: string;
}

export interface BuildResult {
  readonly status: BuildStatus;
  readonly exitCode?: number;
  readonly durationSeconds: number;
  readonly errorCount: number;
  readonly warningCount: number;
  readonly diagnostics: readonly BuildDiagnostic[];
  readonly correlationId: string;
}

export interface BuildHandle {
  readonly id: string;
  readonly output: AsyncIterable<BuildOutputEvent>;
  wait(): Promise<BuildResult>;
  cancel(): Promise<void>;
}

export interface BuildAPI {
  run(request: BuildRequest): Promise<BuildHandle>;
}

export interface TerminalSandboxRequest {
  readonly command: string;
  readonly args?: readonly string[];
  readonly workingDirectory?: string;
  readonly timeout?: number;
}

export interface TerminalSandboxResult {
  readonly stdout: string;
  readonly stderr: string;
  readonly exitCode: number;
  readonly stdoutTruncated: boolean;
  readonly stderrTruncated: boolean;
  readonly stdoutTotalBytes: number;
  readonly stderrTotalBytes: number;
  readonly byteLimit: number;
}

export interface TerminalSandboxAPI {
  run(request: TerminalSandboxRequest): Promise<TerminalSandboxResult>;
}

export interface CommandDefinition {
  readonly id: string;
  readonly title: string;
  execute(payload?: unknown): Promise<unknown>;
}

export interface CommandAPI {
  register(definition: CommandDefinition): Disposable;
}

export interface Disposable {
  dispose(): void;
}

export type EventListener<T = unknown> = (payload: T) => void;

export interface EventAPI {
  subscribe<T = unknown>(event: string, listener: EventListener<T>): Disposable;
}

export interface Logger {
  debug(message: string, fields?: Record<string, unknown>): void;
  info(message: string, fields?: Record<string, unknown>): void;
  warn(message: string, fields?: Record<string, unknown>): void;
  error(message: string, fields?: Record<string, unknown>): void;
}

export interface DisposableStore extends Disposable {
  add<T extends Disposable>(disposable: T): T;
  disposeAll(): void;
}

export interface CloudModelHistoryEntry {
  readonly role: string;
  readonly content: string;
}

export interface CloudModelRequest {
  readonly prompt: string;
  readonly history?: readonly CloudModelHistoryEntry[];
  readonly systemPrompt?: string;
  readonly modelIdentifier?: string;
}

export interface CloudModelAPI {
  complete(request: CloudModelRequest): Promise<string>;
}

export interface UIAPI {
  openView(viewId: string): Promise<void>;
}

export interface SwiftCodeContext {
  readonly extension: ExtensionInfo;
  readonly project: ProjectAPI;
  readonly sourceControl: SourceControlAPI;
  readonly build: BuildAPI;
  readonly terminalSandbox: TerminalSandboxAPI;
  readonly cloudModel: CloudModelAPI;
  readonly commands: CommandAPI;
  readonly events: EventAPI;
  readonly log: Logger;
  readonly security: SecurityAPI;
  readonly ui: UIAPI;
  readonly assist: AssistAPI;
  readonly assistUI: AssistUIAPI;
  readonly subscriptions: DisposableStore;
}

export interface SecurityAddOptions {
  readonly label?: string;
  readonly prompt?: string;
}

export interface SecurityAddedValue {
  readonly valueID: string;
  readonly created: boolean;
}

export interface SecurityStoredValue {
  readonly valueID: string;
  readonly label: string;
  readonly createdAt: string;
}

export interface SecurityHTTPRequest {
  readonly method: string;
  readonly url: string;
  readonly headers?: Record<string, string>;
  readonly body?: string;
}

export interface SecurityOperation {
  readonly kind: "httpAuthorization";
  readonly request: SecurityHTTPRequest;
}

export interface SecurityHTTPResponse {
  readonly status: number;
  readonly body: string;
}

export interface SecurityAPI {
  addValue(securityID: string, valueID: string, options?: SecurityAddOptions): Promise<SecurityAddedValue>;
  hasValue(securityID: string, valueID: string): Promise<boolean>;
  listValueIDs(securityID: string): Promise<SecurityStoredValue[]>;
  deleteValue(securityID: string, valueID: string): Promise<void>;
  useValue(securityID: string, valueID: string, operation: SecurityOperation): Promise<SecurityHTTPResponse>;
}

export interface SDKErrorShape {
  readonly code: string;
  readonly message: string;
  readonly correlationId: string;
}

export const ASSIST_ACCESS_DENIED_MESSAGE: string =
  "This app is not allowed to use Assist because access has not yet been verified. Please check with the app developer for further information.";

export class SDKAssistAccessError extends Error {
  readonly code: "ASSIST_DENIED" = "ASSIST_DENIED";
  readonly correlationId: string;

  constructor(correlationId?: string) {
    super(ASSIST_ACCESS_DENIED_MESSAGE);
    this.name = "SDKAssistAccessError";
    this.correlationId =
      typeof correlationId === "string" && correlationId.length > 0
        ? correlationId
        : "unknown";
  }
}

export const CLOUD_MODEL_ACCESS_DENIED_MESSAGE: string =
  "This app is not allowed to use the SwiftCode Cloud Model because access has not yet been verified. Please check with the app developer for further information.";

export class SDKCloudModelAccessError extends Error {
  readonly code: "CLOUD_MODEL_DENIED" = "CLOUD_MODEL_DENIED";
  readonly correlationId: string;

  constructor(correlationId?: string) {
    super(CLOUD_MODEL_ACCESS_DENIED_MESSAGE);
    this.name = "SDKCloudModelAccessError";
    this.correlationId =
      typeof correlationId === "string" && correlationId.length > 0
        ? correlationId
        : "unknown";
  }
}

export interface AssistSessionInfo {
  readonly sessionId: string;
  readonly createdAt: string;
}

export interface AssistSessionOptions {
  readonly systemPrompt?: string;
  readonly model?: string;
}

export interface AssistToolCall {
  readonly tool: string;
  readonly arguments: Record<string, unknown>;
}

export interface AssistToolResult {
  readonly tool: string;
  readonly result: unknown;
}

export interface AssistStreamChunk {
  readonly delta: string;
  readonly done: boolean;
}

export interface AssistAPI {
  createSession(options?: AssistSessionOptions): Promise<AssistSessionInfo>;
  listSessions(): Promise<AssistSessionInfo[]>;
  sendMessage(sessionId: string, message: string): Promise<string>;
  streamMessage(sessionId: string, message: string): AsyncIterable<AssistStreamChunk>;
  invokeTool(sessionId: string, call: AssistToolCall): Promise<AssistToolResult>;
  closeSession(sessionId: string): Promise<void>;
}

export interface AssistUIAPI {
  openAssistView(): Promise<void>;
}
