/**
 * Public developer contract for the SwiftCode SDK (TypeScript).
 *
 * Finalized from Docs/Intro-to-SDK.md §6.2 (TypeScript developer contract
 * intent) and §11.2/§11.3 (API minimums), matched against the Swift host
 * contracts in `SwiftCode/SDK/Contracts/Protocol/`.
 *
 * These are types only. The real implementations of the IPC client and the
 * context live in `ipc.ts` and `context.ts`.
 */

/** An extension module loaded by the SwiftCode runtime. */
export interface SwiftCodeExtension {
  /** Stable extension identity (the manifest `id`). */
  readonly id: string;
  /** Called once when the extension is activated. Register everything here. */
  activate(context: SwiftCodeContext): Promise<void>;
  /** Called once on deactivation/shutdown. Release extension resources here. */
  deactivate(): Promise<void>;
}

/** Stable identity of the running extension. */
export interface ExtensionInfo {
  readonly id: string;
  readonly name: string;
  readonly version: string;
}

/** Safe metadata about the currently open project. Never carries contents. */
export interface ProjectInfo {
  /** Stable host-assigned project identifier (opaque to extensions). */
  readonly id: string;
  /** Human-readable project display name. */
  readonly name: string;
  /** Absolute path of the project root on the host machine. */
  readonly rootPath: string;
  /** Always `true` for values produced by `getCurrent()`. */
  readonly isOpen: boolean;
}

export interface ProjectAPI {
  /**
   * The currently open project, or `null` when no project is open.
   *
   * NOTE: the Swift host dispatcher does not yet expose this method; the
   * request is sent as `project.getCurrent` and the host answers with a
   * typed `SDKError` until the method lands in a later phase (see
   * `context.ts`). This method never fabricates a project.
   */
  getCurrent(): Promise<ProjectInfo | null>;
}

/** Per-file change classification; mirrors the host's git porcelain subset. */
export type FileChangeStatus =
  | "modified"
  | "added"
  | "deleted"
  | "renamed"
  | "untracked"
  | "conflicted";

/** One changed file in a repository status snapshot. */
export interface FileChangeSummary {
  /** Repository-relative path (never absolute). */
  readonly path: string;
  readonly status: FileChangeStatus;
  /** True when the change is staged in the index. */
  readonly isStaged: boolean;
}

/**
 * Snapshot from `sourceControl.getStatus()`.
 *
 * When `isRepository` is false, `branchName` is undefined, all counts are 0,
 * and `files` is empty. `files` may be host-capped; counts always reflect
 * true totals.
 */
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

/** Options for `sourceControl.getDiff()`. */
export interface DiffOptions {
  /** Max total diff bytes before truncation. Defaults to 262144 (256 KiB). */
  readonly maxBytes?: number;
  /** Include untracked files. Defaults to true. */
  readonly includeUntracked?: boolean;
  /** Repository-relative path filter; undefined means the whole repo. */
  readonly paths?: readonly string[];
}

/** Bounded unified diff for a single file. */
export interface FileDiff {
  /** Repository-relative path (never absolute). */
  readonly path: string;
  /** Unified diff hunks (`@@ … @@` headers included). */
  readonly hunks: readonly string[];
  /** True when this file's diff was cut short by the byte limit. */
  readonly truncated: boolean;
}

/**
 * Result of `sourceControl.getDiff()`. Always bounded: `truncated` plus
 * `totalBytes`/`byteLimit` describe exactly how much was withheld.
 */
export interface RepositoryDiff {
  readonly files: readonly FileDiff[];
  readonly truncated: boolean;
  /** Full, untruncated byte size of the diff (may exceed `byteLimit`). */
  readonly totalBytes: number;
  /** The byte limit that was applied. */
  readonly byteLimit: number;
}

export interface SourceControlAPI {
  /** Repository status snapshot of the open project. */
  getStatus(): Promise<RepositoryStatus>;
  /** Bounded diff of the open project's working tree. */
  getDiff(options?: DiffOptions): Promise<RepositoryDiff>;
}

/** Intent to start a build through the host's managed build service. */
export interface BuildRequest {
  /** Build target (scheme) name, validated against the project's schemes. */
  readonly target: string;
  /** Build configuration (e.g. "Debug", "Release"). Undefined = default. */
  readonly configuration?: string;
  /** Destination specifier (e.g. "platform=macOS"). Undefined = default. */
  readonly destination?: string;
}

/** One streamed output event from a running build. */
export interface BuildOutputEvent {
  readonly kind: "stdout" | "stderr" | "status";
  /** Output text (one logical chunk; may be a partial line). */
  readonly text: string;
  /** Host-side emission time as a Unix timestamp (seconds). */
  readonly timestamp: number;
}

/** Terminal (or in-progress) state of a build. */
export type BuildStatus =
  | "running"
  | "succeeded"
  | "failed"
  | "cancelled"
  | "timedOut";

/** A single structured compiler/build diagnostic. */
export interface BuildDiagnostic {
  /** Repository-relative file path when the diagnostic has a location. */
  readonly file?: string;
  /** 1-based line number when the diagnostic has a location. */
  readonly line?: number;
  readonly message: string;
}

/**
 * Terminal result of a build. The final state reflects the actual build
 * service's terminal result — never "succeeded" merely because a process
 * was launched.
 */
export interface BuildResult {
  readonly status: BuildStatus;
  /** Process exit code; undefined when the build never produced one. */
  readonly exitCode?: number;
  /** Wall-clock duration of the build in seconds. */
  readonly durationSeconds: number;
  readonly errorCount: number;
  readonly warningCount: number;
  readonly diagnostics: readonly BuildDiagnostic[];
  /** Correlation ID shared with host logs and related errors. */
  readonly correlationId: string;
}

/** Handle for a started build, minted by `BuildAPI.run()`. */
export interface BuildHandle {
  /** Stable handle identity. */
  readonly id: string;
  /**
   * Async iterator of live output events. Safe to consume concurrently with
   * `wait()`: both are fed by the same underlying event channel.
   */
  readonly output: AsyncIterable<BuildOutputEvent>;
  /** Resolves to the terminal build result. */
  wait(): Promise<BuildResult>;
  /**
   * Requests cancellation of this build. Best-effort: if the underlying
   * build process cannot be terminated, `wait()` still reports the true
   * terminal state.
   */
  cancel(): Promise<void>;
}

export interface BuildAPI {
  /**
   * Starts a build through the host's managed build service. Resolves to a
   * stable handle only after the service accepts the request.
   */
  run(request: BuildRequest): Promise<BuildHandle>;
}

/**
 * Intent to run one sandboxed command through the host
 * (`terminalSandbox.run`). This is NOT a terminal UI: the host spawns a
 * single process with no shell, an allow-listed executable, a working
 * directory confined to the extension's project scope, a sanitized
 * environment, a hard timeout, and byte-capped output.
 */
export interface TerminalSandboxRequest {
  /**
   * Executable to run: a bare allow-listed name (e.g. "git") or an
   * absolute path inside a host-approved location (e.g. "/usr/bin/git").
   * Never a shell snippet — pipes, redirects, and `;` are rejected.
   */
  readonly command: string;
  /** Verbatim argv elements. Undefined = no arguments. */
  readonly args?: readonly string[];
  /**
   * Working directory as a path string. Relative paths anchor at the
   * project root. Must resolve inside the project scope; undefined =
   * the project root.
   */
  readonly workingDirectory?: string;
  /** Wall-clock budget in seconds. Undefined = host default (30). */
  readonly timeout?: number;
}

/**
 * Terminal result of one sandboxed run. Output is always byte-bounded:
 * `stdoutTruncated`/`stderrTruncated` plus the total/limit fields describe
 * exactly how much was withheld.
 */
export interface TerminalSandboxResult {
  readonly stdout: string;
  readonly stderr: string;
  /** Real process exit code. Timeouts surface as errors, never as codes. */
  readonly exitCode: number;
  readonly stdoutTruncated: boolean;
  readonly stderrTruncated: boolean;
  /** Full, untruncated stdout byte size (may exceed `byteLimit`). */
  readonly stdoutTotalBytes: number;
  /** Full, untruncated stderr byte size (may exceed `byteLimit`). */
  readonly stderrTotalBytes: number;
  /** The per-stream byte limit the host applied. */
  readonly byteLimit: number;
}

export interface TerminalSandboxAPI {
  /**
   * Runs one sandboxed command through the host. Requires the
   * `terminal.sandbox` capability grant; without it the host rejects the
   * call with a typed error. Never fabricates a result.
   */
  run(request: TerminalSandboxRequest): Promise<TerminalSandboxResult>;
}

/** A command contributed by the extension. */
export interface CommandDefinition {
  /** Lowercase kebab-case ID, unique within this extension. */
  readonly id: string;
  readonly title: string;
  /** Invoked by the host when the user runs the command. */
  execute(payload?: unknown): Promise<unknown>;
}

export interface CommandAPI {
  /**
   * Registers a command with the host. The returned `Disposable`
   * unregisters it; the host also removes all registrations on
   * deactivation.
   */
  register(definition: CommandDefinition): Disposable;
}

/** Cleanup handle for a registration or subscription. */
export interface Disposable {
  dispose(): void;
}

/** Event listener receiving an event payload. */
export type EventListener<T = unknown> = (payload: T) => void;

export interface EventAPI {
  /**
   * Subscribes to a host→extension event (e.g. "build.output",
   * "build.finished", "shutdown"). The returned `Disposable` unsubscribes.
   */
  subscribe<T = unknown>(event: string, listener: EventListener<T>): Disposable;
}

export interface Logger {
  debug(message: string, fields?: Record<string, unknown>): void;
  info(message: string, fields?: Record<string, unknown>): void;
  warn(message: string, fields?: Record<string, unknown>): void;
  error(message: string, fields?: Record<string, unknown>): void;
}

/** Collects disposables and releases them all at once. */
export interface DisposableStore extends Disposable {
  /** Adds a disposable to the store; returned for convenience. */
  add<T extends Disposable>(disposable: T): T;
  /** Disposes every collected disposable and clears the store. */
  disposeAll(): void;
}

/** One conversation turn preceding a cloud-model prompt. */
export interface CloudModelHistoryEntry {
  /** Message role, e.g. "user" or "assistant". */
  readonly role: string;
  /** Message content. */
  readonly content: string;
}

/**
 * Request for `cloudModel.complete()`. Carries only the content the host
 * needs: the endpoint, credentials, and quota are host-side and never
 * cross the IPC boundary.
 */
export interface CloudModelRequest {
  /** The user prompt. Required and non-empty. */
  readonly prompt: string;
  /** Conversation history preceding the prompt. Defaults to empty. */
  readonly history?: readonly CloudModelHistoryEntry[];
  /** Optional system prompt prepended by the host. */
  readonly systemPrompt?: string;
  /**
   * Optional model identifier (endpoint model name). Omit to let the
   * host resolve its default.
   */
  readonly modelIdentifier?: string;
}

/**
 * Host-mediated access to the SwiftCode Cloud Model.
 *
 * Requires the `use.SwiftCodeModel` capability grant. Every call is
 * authorized by the host and counted against the user's daily quota; a
 * quota denial surfaces as a typed error (`RESOURCE_LIMIT_EXCEEDED`) and
 * never as a fabricated response. The extension never sees the endpoint
 * URL, device fingerprint, or any credentials.
 */
export interface CloudModelAPI {
  /**
   * Runs one completion through the host's SwiftCode Cloud Model and
   * resolves to the assistant's text. Rejects with a typed
   * {@link SDKError} when the capability is not granted
   * (`PERMISSION_DENIED`), the quota is exhausted
   * (`RESOURCE_LIMIT_EXCEEDED`), or the service is unavailable.
   */
  complete(request: CloudModelRequest): Promise<string>;
}

/**
 * Host-mediated view opening, backed by the real `ui.openView` IPC route
 * (Swift `SDKIPCDispatcher` → `SDKViewOpener`).
 *
 * A "view" is a host-owned UI surface (Database Explorer, Virtualization
 * console, CI workflow dashboard, …) opened in an SDK-owned window. The
 * `viewId` is the view's own capability ID (e.g. `"sandbox.view"`), and the
 * dispatcher authorizes that exact grant at the capability broker before
 * the opener runs — so every view is gated by exactly the grant the
 * extension's manifest declared. An unknown viewId is rejected with a
 * typed `unknownCapability` error, never a silent no-op.
 */
export interface UIAPI {
  /**
   * Opens the host view identified by `viewId`. Resolves once the host
   * has opened the view; rejects with a typed {@link SDKError} when the
   * view is unknown (`UNKNOWN_CAPABILITY`), the capability is not granted
   * (`PERMISSION_DENIED`), or the opener itself fails.
   */
  openView(viewId: string): Promise<void>;
}

/**
 * The context handed to an extension on activation.
 *
 * Assist reaches extensions ONLY through the two entitled SDK variants
 * (Docs/Intro-to-SDK.md §11, task B2): `assist` (headless `assistSDK`)
 * and `assistUI` (`assistSDK.UI`). Both are entitlement-gated — the
 * `com.SwiftCode.developer-AI-Assist` entitlement on the developer's API
 * key (task B3), never the manifest — and every call fails with the
 * verbatim {@link ASSIST_ACCESS_DENIED_MESSAGE} when the host denies it.
 */
export interface SwiftCodeContext {
  readonly extension: ExtensionInfo;
  readonly project: ProjectAPI;
  readonly sourceControl: SourceControlAPI;
  readonly build: BuildAPI;
  /**
   * Host-mediated sandboxed command execution. NOT a terminal UI: one
   * process per call, no shell, allow-listed executables, working
   * directory confined to the project scope, sanitized environment, hard
   * timeout, byte-capped output. Requires the `terminal.sandbox` grant.
   */
  readonly terminalSandbox: TerminalSandboxAPI;
  /**
   * SwiftCode Cloud Model access. Requires the `use.SwiftCodeModel`
   * capability grant; calls are host-mediated and quota-enforced.
   */
  readonly cloudModel: CloudModelAPI;
  readonly commands: CommandAPI;
  readonly events: EventAPI;
  readonly log: Logger;
  /**
   * Keychain-backed secrets via host mediation. Requires the `use.Security`
   * capability grant. The extension never sees plaintext secrets: `addValue`
   * resolves with metadata only, and `useValue` lets the host perform the
   * HTTPS request with the secret attached as the `Authorization` header.
   */
  readonly security: SecurityAPI;
  /**
   * Host-owned view surfaces (Database Explorer, Virtualization console,
   * CI dashboards, …). Each view is gated by its own capability grant.
   */
  readonly ui: UIAPI;
  /**
   * Headless Assist variant (`assistSDK`): sessions, streaming responses,
   * and approved tool calls — no UI surface. Entitlement-gated
   * (`com.SwiftCode.developer-AI-Assist`); denials surface as
   * {@link SDKAssistAccessError} with the verbatim user message.
   */
  readonly assist: AssistAPI;
  /**
   * UI Assist variant (`assistSDK.UI`): embeds the host's real Assist main
   * view only. Entitlement-gated like `assist`; denials surface as
   * {@link SDKAssistAccessError} with the verbatim user message.
   */
  readonly assistUI: AssistUIAPI;
  /**
   * Collects every registration/subscription. The runtime calls
   * `disposeAll()` on deactivation so nothing leaks.
   */
  readonly subscriptions: DisposableStore;
}

/**
 * Options for `security.addValue(...)`.
 */
export interface SecurityAddOptions {
  /**
   * Human-readable label stored alongside the secret and shown in the
   * host's secure prompt (e.g. "GitHub personal access token").
   */
  readonly label?: string;
  /** Prompt text shown in the host's secure popup. */
  readonly prompt?: string;
}

/**
 * Metadata returned when a secret is stored. Carries identity only — the
 * secret itself never crosses the IPC boundary.
 */
export interface SecurityAddedValue {
  readonly valueID: string;
  /** True when a new entry was created; false when an existing one was updated. */
  readonly created: boolean;
}

/**
 * Metadata for one stored value. Never carries the secret — only what the
 * host is willing to reveal for listing.
 */
export interface SecurityStoredValue {
  readonly valueID: string;
  readonly label: string;
  /** ISO-8601 creation timestamp from the host. */
  readonly createdAt: string;
}

/** HTTPS request the host performs with a stored secret attached. */
export interface SecurityHTTPRequest {
  /** HTTP method token (e.g. "GET"). */
  readonly method: string;
  /**
   * HTTPS URL only. Client-side validation rejects anything else, and
   * rejects URLs that embed credentials — the secret is attached by the
   * host as the `Authorization` header, never read from the URL.
   */
  readonly url: string;
  /**
   * Extra headers. The `Authorization` header itself is rejected
   * client-side: the host owns that header when it attaches the secret.
   */
  readonly headers?: Record<string, string>;
  readonly body?: string;
}

/**
 * Operation the host performs with a stored secret. The only supported
 * kind is `httpAuthorization`: the host attaches the secret as the
 * `Authorization` header and performs the HTTPS request. The secret never
 * comes back to the extension — only the response status and body do.
 */
export interface SecurityOperation {
  readonly kind: "httpAuthorization";
  readonly request: SecurityHTTPRequest;
}

/**
 * Result of a host-performed HTTPS request. The secret is never echoed
 * back; `body` is the raw response body.
 */
export interface SecurityHTTPResponse {
  readonly status: number;
  readonly body: string;
}

/**
 * Host-mediated Keychain access (`security.*` IPC routes).
 *
 * Requires the `use.Security` capability grant. Secrets live in the macOS
 * Keychain under the app's Security ID; extension code only ever sees
 * metadata (security IDs, value IDs, labels) and response data — never
 * plaintext secrets. Storing a secret triggers the host's secure popup so
 * the user enters it directly into the host.
 */
export interface SecurityAPI {
  /**
   * Stores a secret: triggers the host's secure popup and resolves with
   * metadata (`{valueID, created}`) once stored. Never resolves with the
   * secret itself.
   */
  addValue(securityID: string, valueID: string, options?: SecurityAddOptions): Promise<SecurityAddedValue>;
  /** True when a value exists for the given IDs. */
  hasValue(securityID: string, valueID: string): Promise<boolean>;
  /** Metadata for every value stored under the security ID. */
  listValueIDs(securityID: string): Promise<SecurityStoredValue[]>;
  /** Deletes the stored value. */
  deleteValue(securityID: string, valueID: string): Promise<void>;
  /**
   * Asks the host to perform an HTTPS request with the stored secret
   * attached as the `Authorization` header. Resolves to `{status, body}`;
   * the secret never comes back to the extension.
   */
  useValue(securityID: string, valueID: string, operation: SecurityOperation): Promise<SecurityHTTPResponse>;
}

/**
 * Wire shape of a typed host error (`ok: false` responses). Only the stable
 * code, the user-safe message, and the correlation ID cross the IPC
 * boundary.
 */
export interface SDKErrorShape {
  readonly code: string;
  readonly message: string;
  readonly correlationId: string;
}

/* ------------------------------------------------------------------ */
/* Assist SDK variants (task B2: `assistSDK` and `assistSDK.UI`)       */
/* ------------------------------------------------------------------ */

/**
 * The exact user-facing message the host produces when an Assist call is
 * denied for lack of a verified entitlement (Docs/Intro-to-SDK.md §13).
 *
 * VERBATIM — do not reword. The TypeScript layer never fabricates this:
 * it is thrown only when the host answers with the typed `ASSIST_DENIED`
 * denial, via {@link SDKAssistAccessError}.
 */
export const ASSIST_ACCESS_DENIED_MESSAGE: string =
  "This app is not allowed to use Assist because access has not yet been verified. Please check with the app developer for further information.";

/**
 * Typed denial for Assist calls. Thrown ONLY when the host answers with
 * the typed `ASSIST_DENIED` error — i.e. the host has checked the
 * key-bound `com.SwiftCode.developer-AI-Assist` entitlement and found it
 * missing or revoked.
 *
 * The TS layer cannot know entitlement state itself and must NOT
 * fabricate it: any other host rejection (including `PERMISSION_DENIED`
 * for unrelated reasons) propagates as the original {@link SDKErrorShape}
 * untouched. Catch this class specifically to show the user the exact
 * §13 message.
 */
export class SDKAssistAccessError extends Error {
  /** Always `"ASSIST_DENIED"`: the typed host denial code. */
  readonly code: "ASSIST_DENIED" = "ASSIST_DENIED";
  /** Correlation ID of the denied request, for host-side log lookup. */
  readonly correlationId: string;

  constructor(correlationId?: string) {
    super(ASSIST_ACCESS_DENIED_MESSAGE);
    this.name = "SDKAssistAccessError";
    // randomUUID is called lazily to avoid importing node:crypto at module
    // load for pure-type consumers of this file.
    this.correlationId =
      typeof correlationId === "string" && correlationId.length > 0
        ? correlationId
        : "unknown";
  }
}

/** Metadata for one headless Assist session. Never carries contents. */
/* ------------------------------------------------------------------ */
/* Cloud-model access denial (Docs/Intro-to-SDK.md §12–§13, task B4)    */
/* ------------------------------------------------------------------ */

/**
 * The exact user-facing message the host produces when a cloud-model call
 * is denied for lack of a verified entitlement (Docs/Intro-to-SDK.md §13).
 *
 * PROPOSED WORDING — Dylan finalizes the exact text. The TypeScript layer
 * never fabricates this: it is thrown only when the host answers with the
 * typed `CLOUD_MODEL_DENIED` denial, via {@link SDKCloudModelAccessError}.
 */
export const CLOUD_MODEL_ACCESS_DENIED_MESSAGE: string =
  "This app is not allowed to use the SwiftCode Cloud Model because access has not yet been verified. Please check with the app developer for further information.";

/**
 * Typed denial for cloud-model calls. Thrown ONLY when the host answers
 * with the typed `CLOUD_MODEL_DENIED` error — i.e. the host has checked
 * the key-bound `com.SwiftCode.developer-AI-Allows-Cloud` entitlement and
 * found it missing or revoked.
 *
 * Mirrors {@link SDKAssistAccessError}: the TS layer cannot know
 * entitlement state itself and must NOT fabricate it. Any other host
 * rejection (including `PERMISSION_DENIED` for unrelated reasons or
 * `RESOURCE_LIMIT_EXCEEDED` for quota) propagates as the original
 * {@link SDKErrorShape} untouched. Catch this class specifically to show
 * the user the exact §13 message.
 */
export class SDKCloudModelAccessError extends Error {
  /** Always `"CLOUD_MODEL_DENIED"`: the typed host denial code. */
  readonly code: "CLOUD_MODEL_DENIED" = "CLOUD_MODEL_DENIED";
  /** Correlation ID of the denied request, for host-side log lookup. */
  readonly correlationId: string;

  constructor(correlationId?: string) {
    super(CLOUD_MODEL_ACCESS_DENIED_MESSAGE);
    this.name = "SDKCloudModelAccessError";
    // randomUUID is called lazily to avoid importing node:crypto at module
    // load for pure-type consumers of this file.
    this.correlationId =
      typeof correlationId === "string" && correlationId.length > 0
        ? correlationId
        : "unknown";
  }
}

/** Metadata for one headless Assist session. Never carries contents. */
export interface AssistSessionInfo {
  readonly sessionId: string;
  readonly createdAt: string;
}

/** Options for `AssistAPI.createSession`. */
export interface AssistSessionOptions {
  readonly systemPrompt?: string;
  readonly model?: string;
}

/** One tool invocation requested through an Assist session. */
export interface AssistToolCall {
  readonly tool: string;
  readonly arguments: Record<string, unknown>;
}

/** The host-mediated result of one tool invocation. */
export interface AssistToolResult {
  readonly tool: string;
  readonly result: unknown;
}

/** One chunk of a streamed Assist response. `done: true` ends the stream. */
export interface AssistStreamChunk {
  readonly delta: string;
  readonly done: boolean;
}

/**
 * Headless Assist variant (`assistSDK`): the full Assist API surface
 * EXCEPT UI — sessions, streaming responses, and tool access per the
 * approved scope. The developer renders everything themselves.
 *
 * Every function routes through the IPC connection to the host's
 * dedicated entitled route. There is intentionally NO view-opening path
 * in this interface: presenting UI belongs to {@link AssistUIAPI}.
 *
 * Entitlement: every call requires the key-bound
 * `com.SwiftCode.developer-AI-Assist` entitlement (task B3), enforced by
 * the host at the IPC dispatcher / capability broker. When the host
 * denies, the call throws {@link SDKAssistAccessError} carrying the
 * verbatim §13 message — the TS layer never decides entitlement itself.
 */
export interface AssistAPI {
  /** Creates a headless Assist session on the host. */
  createSession(options?: AssistSessionOptions): Promise<AssistSessionInfo>;
  /** Lists this extension's live headless Assist sessions. Metadata only. */
  listSessions(): Promise<AssistSessionInfo[]>;
  /**
   * Sends one message in a session; resolves with the full assistant
   * reply text.
   */
  sendMessage(sessionId: string, message: string): Promise<string>;
  /**
   * Sends one message and yields response chunks as they stream in.
   * The async iterator ends when the host sends a chunk with
   * `done: true`.
   */
  streamMessage(sessionId: string, message: string): AsyncIterable<AssistStreamChunk>;
  /**
   * Invokes one approved tool through the session, host-mediated. The
   * tool must be within the extension's approved scope; anything else is
   * denied by the host with the typed denial.
   */
  invokeTool(sessionId: string, call: AssistToolCall): Promise<AssistToolResult>;
  /** Closes a headless Assist session. */
  closeSession(sessionId: string): Promise<void>;
}

/**
 * UI Assist variant (`assistSDK.UI`): exposes ONLY embedding of the
 * host's real Assist main view inside the developer's app. The host
 * presents it; the extension never touches Assist internals and gets no
 * headless session/streaming APIs here.
 *
 * Entitlement: like {@link AssistAPI}, gated by the key-bound
 * `com.SwiftCode.developer-AI-Assist` entitlement; a host denial throws
 * {@link SDKAssistAccessError} with the verbatim §13 message.
 */
export interface AssistUIAPI {
  /**
   * Presents the host's Assist main view (`assist.main`). Resolves once
   * the host has opened it.
   */
  openAssistView(): Promise<void>;
}
