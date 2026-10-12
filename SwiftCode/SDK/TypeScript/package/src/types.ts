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

/**
 * The context handed to an extension on activation.
 *
 * Assist is deliberately NOT present here (spec §9): it is a separately
 * protected authorization boundary and stays unavailable to extensions.
 */
export interface SwiftCodeContext {
  readonly extension: ExtensionInfo;
  readonly project: ProjectAPI;
  readonly sourceControl: SourceControlAPI;
  readonly build: BuildAPI;
  readonly commands: CommandAPI;
  readonly events: EventAPI;
  readonly log: Logger;
  /**
   * Collects every registration/subscription. The runtime calls
   * `disposeAll()` on deactivation so nothing leaks.
   */
  readonly subscriptions: DisposableStore;
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
