/**
 * Real implementation of the developer-facing SDK context
 * (Docs/Intro-to-SDK.md §6.2, §11.2, §11.3).
 *
 * Method list is taken from the Swift host's `SDKIPCDispatcher` routing
 * table — only methods the dispatcher actually supports are called:
 *
 *   sourceControl.getStatus   payload {}
 *   sourceControl.getDiff     payload {"options": {...}} (optional)
 *   build.run                 payload {"target","configuration?","destination?"}
 *                             → {"handleId"}
 *   build.wait                payload {"handleId"} → BuildResult
 *   build.cancel              payload {"handleId"}
 *   cloudModel.complete       payload {"prompt","history?","systemPrompt?","modelIdentifier?"}
 *                             → {"response"}
 *   assist.invoke             payload {"op", ...} — the entitled headless
 *                             Assist route (see assist.ts); handled by
 *                             createAssistAPI, not by the context object
 *   terminalSandbox.run       payload {"command","args","workingDirectory?","timeout?"}
 *                             → TerminalSandboxResult
 *   commands.register         payload {"id","title"}
 *   commands.unregister       payload {"commandID"}
 *   ui.openView                 payload {"viewId"} — viewId is the view's
 *                               own capability ID (e.g. "sandbox.view")
 *   log.debug|info|warn|error payload {"message","correlationId?"}
 *   security.addValue       payload {"securityID","valueID","label?","prompt?"}
 *                             → {"valueID","created"} (metadata only, never the secret)
 *   security.hasValue       payload {"securityID","valueID"} → {"hasValue"}
 *   security.listValueIDs   payload {"securityID"} → {"values":[…]}
 *   security.deleteValue    payload {"securityID","valueID"}
 *   security.useValue       payload {"securityID","valueID","operation"}
 *                             → {"status","body"} (the host attaches the
 *                               secret as the Authorization header; it never
 *                               comes back to the extension)
 *
 * `security.*` routes are served by the host's Security dispatcher (the
 * `use.Security` host phase, capability ID "use.Security"). Until the
 * routes land, the host answers with a typed error — calls reject with an
 * {@link SDKError}, never a fabricated result.
 *
 * `project.getCurrent` is NOT in the dispatcher routing table. It is sent
 * as `project.getCurrent` anyway, and the host answers with a typed error
 * (`IPC_MALFORMED`: "Unknown method") until the method lands in a later
 * host phase. This method never fabricates a project — a failed request
 * surfaces as an {@link SDKError}, never a fake `ProjectInfo`.
 */

import { randomUUID } from "node:crypto";
import type {
  AssistAPI,
  AssistUIAPI,
  BuildDiagnostic,
  BuildHandle,
  BuildOutputEvent,
  BuildRequest,
  BuildResult,
  CloudModelAPI,
  CloudModelRequest,
  CommandAPI,
  CommandDefinition,
  DiffOptions,
  Disposable,
  DisposableStore,
  EventAPI,
  EventListener,
  ExtensionInfo,
  Logger,
  ProjectAPI,
  ProjectInfo,
  RepositoryDiff,
  RepositoryStatus,
  SecurityAPI,
  SourceControlAPI,
  SwiftCodeContext,
  TerminalSandboxAPI,
  TerminalSandboxRequest,
  TerminalSandboxResult,
  UIAPI,
} from "./types.js";
import { SDKError, type HostConnection, type HostEvent } from "./ipc.js";
import { SDKCloudModelAccessError } from "./types.js";
import { createSecurityAPI } from "./security.js";
import { createAssistAPI } from "./assist.js";
import { createAssistUIAPI } from "./assistUI.js";

/** Client-side mirror of the host's command-ID rule (SDKCommandRegistry). */
const COMMAND_ID_PATTERN = /^[a-z][a-z0-9-]{0,63}$/;
/** Client-side mirror of the host's command-title cap. */
const MAX_COMMAND_TITLE_LENGTH = 128;
/**
 * Client-side mirror of the host's sandboxed-command rule
 * (`SDKSandboxedTerminal`): a bare allow-listed name, or an absolute path.
 * Anything else — shell snippets, relative paths — is rejected here with
 * `INVALID_ARGUMENT` before it ever reaches the host. The host re-validates
 * everything; this is an early, friendly failure, not a security boundary.
 */
const SANDBOX_BARE_COMMAND_PATTERN = /^[A-Za-z0-9._-]{1,64}$/;
/** Client-side mirror of the host's argv caps (`SDKSandboxedTerminal`). */
const SANDBOX_MAX_ARGS = 256;
const SANDBOX_MAX_ARG_BYTES = 8 * 1024;

/** Validates one argv element client-side (host re-validates). */
function validateSandboxArg(arg: unknown, index: number): string {
  if (typeof arg !== "string") {
    throw new SDKError("INVALID_ARGUMENT", `Sandboxed command argument #${index} must be a string.`);
  }
  if (arg.includes("\0")) {
    throw new SDKError("INVALID_ARGUMENT", `Sandboxed command argument #${index} must not contain NUL bytes.`);
  }
  if (Buffer.byteLength(arg, "utf8") > SANDBOX_MAX_ARG_BYTES) {
    throw new SDKError(
      "INVALID_ARGUMENT",
      `Sandboxed command argument #${index} exceeds the ${SANDBOX_MAX_ARG_BYTES}-byte limit.`,
    );
  }
  return arg;
}

/** Real {@link DisposableStore} implementation. */
class RealDisposableStore implements DisposableStore {
  private readonly items = new Set<Disposable>();

  add<T extends Disposable>(disposable: T): T {
    this.items.add(disposable);
    return disposable;
  }

  dispose(): void {
    this.disposeAll();
  }

  disposeAll(): void {
    const items = [...this.items];
    this.items.clear();
    for (const item of items) {
      try {
        item.dispose();
      } catch {
        // Best-effort cleanup: one bad disposable must not prevent others.
      }
    }
  }
}

interface OutputSubscriber {
  queue: Array<BuildOutputEvent | null>;
  wake: (() => void) | null;
}

/**
 * Live build handle. Output events are broadcast from the host's
 * `build.output` events; `wait()` returns the cached `build.finished`
 * result when it has already arrived, and falls back to `build.wait`
 * otherwise. Both paths may be used concurrently.
 *
 * Event correlation: the Swift host forwards build events with the event
 * envelope's `requestId` set to the originating `build.run` request ID, and
 * a `handleId` inside the payload when the host provides one. Both are
 * matched so the handle stays correct under either host shape.
 */
class RealBuildHandle implements BuildHandle {
  readonly id: string;
  private readonly connection: HostConnection;
  private readonly runRequestId: string;
  private finished: BuildResult | null = null;
  private readonly subscribers = new Set<OutputSubscriber>();
  /**
   * Events that arrived before any iterator subscribed (e.g. replayed from
   * the context's early-event stash). Drained into the first iterator that
   * subscribes, preserving arrival order.
   */
  private readonly backlog: BuildOutputEvent[] = [];
  /** Called once when the handle reaches a terminal state. */
  private readonly onTerminal: () => void;

  constructor(
    connection: HostConnection,
    handleId: string,
    runRequestId: string,
    onTerminal: () => void,
  ) {
    this.connection = connection;
    this.id = handleId;
    this.runRequestId = runRequestId;
    this.onTerminal = onTerminal;
  }

  get output(): AsyncIterable<BuildOutputEvent> {
    // A fresh independent iterator per access, all fed by the same channel.
    const handle = this;
    const subscriber: OutputSubscriber = { queue: [], wake: null };
    return {
      [Symbol.asyncIterator](): AsyncIterator<BuildOutputEvent> {
        // Drain any backlog from before subscription, in arrival order.
        subscriber.queue.push(...handle.backlog.splice(0));
        handle.subscribers.add(subscriber);
        return {
          async next(): Promise<IteratorResult<BuildOutputEvent>> {
            for (;;) {
              const item = subscriber.queue.shift();
              if (item !== undefined) {
                if (item === null) {
                  handle.subscribers.delete(subscriber);
                  return { done: true, value: undefined as never };
                }
                return { done: false, value: item };
              }
              if (handle.finished !== null) {
                handle.subscribers.delete(subscriber);
                return { done: true, value: undefined as never };
              }
              await new Promise<void>((resolve) => {
                subscriber.wake = resolve;
              });
              subscriber.wake = null;
            }
          },
        };
      },
    };
  }

  async wait(): Promise<BuildResult> {
    if (this.finished !== null) return this.finished;
    try {
      const result = await this.connection.request<BuildResult>("build.wait", {
        handleId: this.id,
      });
      this.finished = result;
      return result;
    } catch (error) {
      if (this.finished !== null) return this.finished;
      throw error;
    } finally {
      this.endOutput();
    }
  }

  async cancel(): Promise<void> {
    await this.connection.request<unknown>("build.cancel", { handleId: this.id });
  }

  /**
   * Feeds one host event into this handle. Called by the context-level
   * event router (see `createContext`): the router guarantees no event is
   * lost even when it arrives before the handle exists, by stashing early
   * events and replaying them at construction.
   */
  feed(event: HostEvent): void {
    const payload =
      typeof event.payload === "object" && event.payload !== null
        ? (event.payload as Record<string, unknown>)
        : null;
    if (event.name === "build.output" && payload !== null) {
      const kind = payload["kind"];
      if (kind === "stdout" || kind === "stderr" || kind === "status") {
        this.push({
          kind,
          text: typeof payload["text"] === "string" ? payload["text"] : "",
          timestamp: typeof payload["timestamp"] === "number" ? payload["timestamp"] : Date.now() / 1000,
        });
      }
      return;
    }

    if (event.name === "build.finished") {
      // The host sends the BuildResult as the event payload; some shapes
      // wrap it in {"result": …}, and error fallbacks carry a message only.
      const result = this.normalizeResult(payload);
      if (result !== null) {
        this.finished = result;
      }
      this.endOutput();
    }
  }

  private normalizeResult(payload: Record<string, unknown> | null): BuildResult | null {
    if (payload === null) return null;
    const candidate =
      typeof payload["result"] === "object" && payload["result"] !== null
        ? (payload["result"] as Record<string, unknown>)
        : payload;
    const status = candidate["status"];
    if (status !== "succeeded" && status !== "failed" && status !== "cancelled" && status !== "timedOut" && status !== "running") {
      return null;
    }
    const diagnostics: BuildDiagnostic[] = [];
    if (Array.isArray(candidate["diagnostics"])) {
      for (const raw of candidate["diagnostics"]) {
        if (typeof raw === "object" && raw !== null && "message" in raw) {
          const entry = raw as Record<string, unknown>;
          const diagnostic: BuildDiagnostic = {
            message: String(entry["message"] ?? ""),
          };
          const withFile =
            typeof entry["file"] === "string" ? { ...diagnostic, file: entry["file"] } : diagnostic;
          const withLine =
            typeof entry["line"] === "number" ? { ...withFile, line: entry["line"] } : withFile;
          diagnostics.push(withLine);
        }
      }
    } else if (typeof candidate["message"] === "string") {
      // Host error fallback shape: {status: "failed", message, code?, correlationId?}.
      diagnostics.push({ message: candidate["message"] });
    }
    const result: BuildResult = {
      status,
      durationSeconds: typeof candidate["durationSeconds"] === "number" ? candidate["durationSeconds"] : 0,
      errorCount: typeof candidate["errorCount"] === "number" ? candidate["errorCount"] : diagnostics.length,
      warningCount: typeof candidate["warningCount"] === "number" ? candidate["warningCount"] : 0,
      diagnostics,
      correlationId:
        typeof candidate["correlationId"] === "string" ? candidate["correlationId"] : "",
    };
    return typeof candidate["exitCode"] === "number"
      ? { ...result, exitCode: candidate["exitCode"] }
      : result;
  }

  private push(event: BuildOutputEvent): void {
    if (this.subscribers.size === 0) {
      this.backlog.push(event);
      return;
    }
    for (const subscriber of this.subscribers) {
      subscriber.queue.push(event);
      subscriber.wake?.();
    }
  }

  private endOutput(): void {
    for (const subscriber of this.subscribers) {
      subscriber.queue.push(null);
      subscriber.wake?.();
    }
    this.onTerminal();
  }
}

export interface CreatedContext {
  readonly context: SwiftCodeContext;
  /**
   * Returns the handler for a registered command ID, or undefined.
   * Used by the runtime to dispatch `commands.execute` host events.
   */
  getCommandHandler(id: string): ((payload?: unknown) => Promise<unknown>) | undefined;
}

/**
 * Builds the real extension context over an IPC connection.
 *
 * The runtime wires `commands.execute` host events to registered handlers
 * via the returned `getCommandHandler`. `log.*` calls are fire-and-forget:
 * they are sent but never awaited, so logging can never stall an extension.
 */
export function createContext(
  connection: HostConnection,
  extensionInfo: ExtensionInfo,
): CreatedContext {
  const subscriptions = new RealDisposableStore();
  const commandHandlers = new Map<string, (payload?: unknown) => Promise<unknown>>();

  function validateCommandDefinition(definition: CommandDefinition): void {
    if (!COMMAND_ID_PATTERN.test(definition.id)) {
      throw new SDKError(
        "INVALID_ARGUMENT",
        `Command ID "${definition.id}" is invalid. Use a lowercase kebab-case ID (1–64 characters), e.g. "my-command-2".`,
      );
    }
    const title = definition.title.trim();
    if (title.length === 0) {
      throw new SDKError("INVALID_ARGUMENT", `Command "${definition.id}" has a blank title.`);
    }
    if (title.length > MAX_COMMAND_TITLE_LENGTH) {
      throw new SDKError(
        "INVALID_ARGUMENT",
        `Command "${definition.id}" has a title longer than ${MAX_COMMAND_TITLE_LENGTH} characters.`,
      );
    }
    if (commandHandlers.has(definition.id)) {
      throw new SDKError(
        "INVALID_ARGUMENT",
        `Command "${definition.id}" is already registered by this extension.`,
      );
    }
  }

  const project: ProjectAPI = {
    async getCurrent(): Promise<ProjectInfo | null> {
      // NOT in the Swift dispatcher routing table (see file header): the
      // host rejects this with a typed error until the method is added.
      // Never fabricate a project here.
      return connection.request<ProjectInfo | null>("project.getCurrent", {});
    },
  };

  const sourceControl: SourceControlAPI = {
    async getStatus(): Promise<RepositoryStatus> {
      return connection.request<RepositoryStatus>("sourceControl.getStatus", {});
    },
    async getDiff(options?: DiffOptions): Promise<RepositoryDiff> {
      return connection.request<RepositoryDiff>(
        "sourceControl.getDiff",
        options === undefined ? {} : { options },
      );
    },
  };

  /**
   * True when a build event belongs to the given handle: the host forwards
   * build events with the event envelope's `requestId` set to the
   * originating `build.run` request ID, and a `handleId` inside the payload
   * when the host provides one. Both are matched.
   */
  function eventMatchesHandle(event: HostEvent, handleId: string, runRequestId: string): boolean {
    const payload =
      typeof event.payload === "object" && event.payload !== null
        ? (event.payload as Record<string, unknown>)
        : null;
    return (
      (payload !== null && (payload["handleId"] === handleId || payload["handleID"] === handleId)) ||
      event.requestId === runRequestId
    );
  }

  // --- Build event routing -------------------------------------------------
  //
  // The host forwards build events detached from the `build.run` request
  // (see `SDKIPCDispatcher.forwardBuildEvents`), so `build.output` /
  // `build.finished` frames can arrive BEFORE the extension has constructed
  // its BuildHandle — even in the same NDJSON chunk as the run response.
  // This router never drops those events: build events with no live handle
  // are stashed and replayed, in arrival order, when `build.run` resolves.
  const liveHandles = new Map<string, RealBuildHandle>();
  const liveHandlesByRunId = new Map<string, RealBuildHandle>();
  const stashedBuildEvents: HostEvent[] = [];

  function routeBuildEvent(event: HostEvent): void {
    const payload =
      typeof event.payload === "object" && event.payload !== null
        ? (event.payload as Record<string, unknown>)
        : null;
    const handleId =
      payload !== null && typeof payload["handleId"] === "string"
        ? payload["handleId"]
        : payload !== null && typeof payload["handleID"] === "string"
          ? payload["handleID"]
          : undefined;
    const handle =
      (handleId !== undefined ? liveHandles.get(handleId) : undefined) ??
      liveHandlesByRunId.get(event.requestId);
    if (handle !== undefined) {
      handle.feed(event);
    } else {
      stashedBuildEvents.push(event);
    }
  }

  function registerBuildHandle(handle: RealBuildHandle, runRequestId: string): void {
    liveHandles.set(handle.id, handle);
    liveHandlesByRunId.set(runRequestId, handle);
    // Replay stashed events for this handle, in arrival order.
    const replay: HostEvent[] = [];
    for (let i = stashedBuildEvents.length - 1; i >= 0; i--) {
      const event = stashedBuildEvents[i];
      if (event !== undefined && eventMatchesHandle(event, handle.id, runRequestId)) {
        replay.unshift(event);
        stashedBuildEvents.splice(i, 1);
      }
    }
    for (const event of replay) {
      handle.feed(event);
    }
  }

  const build = {
    async run(request: BuildRequest): Promise<BuildHandle> {
      if (request.target.trim().length === 0) {
        throw new SDKError("INVALID_ARGUMENT", "Build target must be a non-empty string.");
      }
      const payload: Record<string, unknown> = { target: request.target };
      if (request.configuration !== undefined) payload["configuration"] = request.configuration;
      if (request.destination !== undefined) payload["destination"] = request.destination;
      // The run requestId is captured so build events can be correlated:
      // the host forwards build events with the originating request's ID.
      const runRequestId = randomUUID();
      const response = await connection.request<{ handleId: string }>(
        "build.run",
        payload,
        runRequestId,
      );
      if (typeof response?.handleId !== "string" || response.handleId.length === 0) {
        throw new SDKError(
          "IPC_MALFORMED",
          "The host returned an invalid build handle.",
          undefined,
        );
      }
      // Constructing the handle synchronously in the response continuation
      // guarantees no event is processed between response and registration:
      // incoming frames are macrotasks, and this microtask drains first.
      const handle = new RealBuildHandle(connection, response.handleId, runRequestId, () => {
        liveHandles.delete(response.handleId);
        liveHandlesByRunId.delete(runRequestId);
      });
      registerBuildHandle(handle, runRequestId);
      return handle;
    },
  };

  const cloudModel: CloudModelAPI = {
    async complete(request: CloudModelRequest): Promise<string> {
      if (typeof request?.prompt !== "string" || request.prompt.length === 0) {
        throw new SDKError("INVALID_ARGUMENT", "Cloud model prompt must be a non-empty string.");
      }
      const payload: Record<string, unknown> = { prompt: request.prompt };
      if (request.history !== undefined) {
        if (!Array.isArray(request.history)) {
          throw new SDKError("INVALID_ARGUMENT", "Cloud model history must be an array of {role, content} entries.");
        }
        payload["history"] = request.history.map((entry) => ({
          role: entry.role,
          content: entry.content,
        }));
      }
      if (request.systemPrompt !== undefined) payload["systemPrompt"] = request.systemPrompt;
      if (request.modelIdentifier !== undefined) payload["modelIdentifier"] = request.modelIdentifier;
      // Exact method string: matches the Swift dispatcher's "cloudModel.complete" route.
      // ENTITLEMENT HONESTY (mirrors assist.ts's mapAssistDenial): the TS
      // layer cannot know entitlement state itself and never fabricates
      // it. Only the host's typed CLOUD_MODEL_DENIED denial is translated
      // into SDKCloudModelAccessError (carrying the verbatim §13 user
      // message — proposed wording until Dylan finalizes it). Every other
      // rejection — including PERMISSION_DENIED from unrelated checks and
      // RESOURCE_LIMIT_EXCEEDED for quota — propagates untouched.
      let response: { response: string };
      try {
        response = await connection.request<{ response: string }>("cloudModel.complete", payload);
      } catch (error) {
        if (error instanceof SDKError && error.code === "CLOUD_MODEL_DENIED") {
          throw new SDKCloudModelAccessError(error.correlationId);
        }
        throw error;
      }
      if (typeof response?.response !== "string") {
        throw new SDKError(
          "IPC_MALFORMED",
          "The host returned an invalid cloud model response.",
          undefined,
        );
      }
      // Host denies (PERMISSION_DENIED / RESOURCE_LIMIT_EXCEEDED) arrive
      // here as rejected SDKError promises from connection.request — never
      // as fabricated text. They propagate untouched.
      return response.response;
    },
  };

  const terminalSandbox: TerminalSandboxAPI = {
    async run(request: TerminalSandboxRequest): Promise<TerminalSandboxResult> {
      const command = request?.command;
      if (typeof command !== "string" || command.length === 0) {
        throw new SDKError("INVALID_ARGUMENT", "Sandboxed command must be a non-empty string.");
      }
      const isBareName = SANDBOX_BARE_COMMAND_PATTERN.test(command);
      const isAbsolutePath = command.startsWith("/");
      if (!isBareName && !isAbsolutePath) {
        throw new SDKError(
          "INVALID_ARGUMENT",
          `Sandboxed command "${command}" is invalid: use a bare executable name (e.g. "git") or an absolute path (e.g. "/usr/bin/git"). Shell syntax is not supported.`,
        );
      }
      const rawArgs = request.args ?? [];
      if (!Array.isArray(rawArgs)) {
        throw new SDKError("INVALID_ARGUMENT", "Sandboxed command args must be an array of strings.");
      }
      if (rawArgs.length > SANDBOX_MAX_ARGS) {
        throw new SDKError(
          "INVALID_ARGUMENT",
          `Sandboxed command accepts at most ${SANDBOX_MAX_ARGS} arguments.`,
        );
      }
      const args = rawArgs.map((arg, index) => validateSandboxArg(arg, index));
      const payload: Record<string, unknown> = { command, args };
      if (request.workingDirectory !== undefined) {
        if (typeof request.workingDirectory !== "string" || request.workingDirectory.length === 0) {
          throw new SDKError("INVALID_ARGUMENT", "Sandboxed workingDirectory must be a non-empty string.");
        }
        payload["workingDirectory"] = request.workingDirectory;
      }
      if (request.timeout !== undefined) {
        if (typeof request.timeout !== "number" || !Number.isFinite(request.timeout) || request.timeout <= 0) {
          throw new SDKError("INVALID_ARGUMENT", "Sandboxed timeout must be a positive finite number of seconds.");
        }
        payload["timeout"] = request.timeout;
      }
      // Exact method string: matches the Swift dispatcher's "terminalSandbox.run" route.
      const result = await connection.request<TerminalSandboxResult>("terminalSandbox.run", payload);
      if (
        typeof result?.stdout !== "string" ||
        typeof result?.stderr !== "string" ||
        typeof result?.exitCode !== "number"
      ) {
        throw new SDKError(
          "IPC_MALFORMED",
          "The host returned an invalid sandboxed command result.",
          undefined,
        );
      }
      return result;
    },
  };

  const commands: CommandAPI = {
    register(definition: CommandDefinition): Disposable {
      validateCommandDefinition(definition);
      const handler = definition.execute;
      commandHandlers.set(definition.id, handler);
      let disposed = false;
      const disposable: Disposable = {
        dispose(): void {
          if (disposed) return;
          disposed = true;
          commandHandlers.delete(definition.id);
          // Fire-and-forget: disposal is synchronous; a failed unregister
          // must not throw out of dispose(). The handler is already gone
          // locally, so no command can fire after this point.
          connection.request("commands.unregister", { commandID: definition.id }).catch(() => undefined);
        },
      };
      // Registration itself is synchronous from the extension's view: the
      // request is sent without awaiting so activate() cannot stall on it.
      // A host-side rejection is delivered to the developer log instead.
      connection
        .request("commands.register", { id: definition.id, title: definition.title.trim() })
        .catch((error: unknown) => {
          commandHandlers.delete(definition.id);
          const message = error instanceof Error ? error.message : String(error);
          log.error(`Failed to register command "${definition.id}": ${message}`);
        });
      return subscriptions.add(disposable);
    },
  };

  const events: EventAPI = {
    subscribe<T = unknown>(event: string, listener: EventListener<T>): Disposable {
      const unsubscribe = connection.onEvent((hostEvent: HostEvent) => {
        if (hostEvent.name === event) {
          listener(hostEvent.payload as T);
        }
      });
      return subscriptions.add({ dispose: unsubscribe });
    },
  };

  const log: Logger = {
    debug(message: string, fields?: Record<string, unknown>): void {
      sendLog("log.debug", message, fields);
    },
    info(message: string, fields?: Record<string, unknown>): void {
      sendLog("log.info", message, fields);
    },
    warn(message: string, fields?: Record<string, unknown>): void {
      sendLog("log.warn", message, fields);
    },
    error(message: string, fields?: Record<string, unknown>): void {
      sendLog("log.error", message, fields);
    },
  };

  const ui: UIAPI = {
    async openView(viewId: string): Promise<void> {
      if (typeof viewId !== "string" || viewId.length === 0) {
        throw new SDKError("INVALID_ARGUMENT", "View ID must be a non-empty capability ID string (e.g. \"sandbox.view\").");
      }
      // Exact method string: matches the Swift dispatcher's "ui.openView"
      // route. The host authorizes the view's own capability ID at the
      // broker before the opener runs; unknown viewIds and ungranted
      // capabilities surface as typed SDKError rejections, never silent
      // no-ops. The host answers with a null payload on success.
      await connection.request<unknown>("ui.openView", { viewId });
    },
  };

  function sendLog(method: string, message: string, fields?: Record<string, unknown>): void {
    if (connection.closed) return;
    const payload: Record<string, unknown> = { message };
    const correlationId = fields?.["correlationId"];
    if (typeof correlationId === "string" && correlationId.length > 0) {
      payload["correlationId"] = correlationId;
    }
    // Fire-and-forget by design (see createContext docs): swallow failures
    // so a broken pipe can never take down extension code.
    connection.request(method, payload).catch(() => undefined);
  }

  // Security API over the same IPC connection. Also installs the active
  // connection for the standalone security.* helpers in security.ts.
  const security: SecurityAPI = createSecurityAPI(connection);

  // Assist SDK variants (task B2) over the same IPC connection. Both are
  // entitlement-gated host-side; the TS layer translates only the host's
  // typed ASSIST_DENIED denial and never fabricates entitlement state.
  const assist: AssistAPI = createAssistAPI(connection);
  const assistUI: AssistUIAPI = createAssistUIAPI(connection);

  const context: SwiftCodeContext = {
    extension: extensionInfo,
    project,
    sourceControl,
    build,
    cloudModel,
    terminalSandbox,
    commands,
    events,
    log,
    ui,
    security,
    assist,
    assistUI,
    subscriptions,
  };

  // Route host→extension frames: build events go to their handle (stashing
  // early ones; see above).
  //
  // NOTE: `commands.execute` dispatch is owned exclusively by the runtime
  // adapter via the returned `getCommandHandler` (see its docstring). This
  // router must NOT self-dispatch command events: a duplicate listener here
  // would invoke every registered command handler a second time. Command
  // failures are reported by the adapter as `commands.executeResult` events.
  connection.onEvent((event: HostEvent) => {
    if (event.name === "build.output" || event.name === "build.finished") {
      routeBuildEvent(event);
    }
  });

  return {
    context,
    getCommandHandler(id: string) {
      return commandHandlers.get(id);
    },
  };
}
