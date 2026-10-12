/**
 * Headless Assist SDK variant: `assistSDK` (Docs/Intro-to-SDK.md §11, task B2).
 *
 * The full Assist API surface EXCEPT UI — sessions, streaming responses,
 * tool access per the approved scope. The developer renders everything
 * themselves. There is intentionally NO view-opening path in this module:
 * it never imports or calls `ui.openView` (or anything from
 * `assistUI.ts`); presenting UI belongs to `assistSDK.UI`.
 *
 * WIRE CONTRACT — DEPENDENCY ON THE SIBLING TASK:
 * Every public function routes through the IPC connection to the
 * dedicated entitled route `assist.invoke`, with an `op` discriminator in
 * the payload:
 *
 *   assist.invoke  {"op":"session.create","systemPrompt?","model?"}
 *                  → {"sessionId","createdAt"}
 *   assist.invoke  {"op":"session.list"} → {"sessions":[{"sessionId","createdAt"}]}
 *   assist.invoke  {"op":"message.send","sessionId","message"} → {"reply"}
 *   assist.invoke  {"op":"message.stream","sessionId","message"} → {"accepted":true}
 *   assist.invoke  {"op":"tool.invoke","sessionId","tool","arguments"} → {"tool","result"}
 *   assist.invoke  {"op":"session.close","sessionId"} → null
 *
 * The sibling task implements the `assist.invoke` route in
 * `SDKIPCDispatcher` and carves the entitled path out of
 * `SDKAssistGate.check` (which currently deny-lists the `assist`
 * substring); until that lands, the host answers with the typed
 * `ASSIST_DENIED` denial and every call below throws
 * {@link SDKAssistAccessError}. Nothing here is a stub: calls genuinely
 * go to the host, and host rejections surface as real errors.
 *
 * Streaming: `message.stream` resolves once the host accepts the stream
 * (or rejects with the typed denial). Response chunks arrive as
 * `assist.stream` host events correlated by the request's `requestId`,
 * each with payload `{"delta","done"}`; a final `done: true` chunk ends
 * the stream. A chunk carrying `"error"` fails the iterator with the
 * host's typed error.
 *
 * ENTITLEMENT HONESTY: the TS layer cannot know entitlement state itself
 * and never fabricates it. Only the host's typed `ASSIST_DENIED` denial
 * is translated into {@link SDKAssistAccessError} (carrying the verbatim
 * §13 user message). Every other rejection — including `PERMISSION_DENIED`
 * from unrelated checks — propagates as the original SDKError untouched.
 */

import { randomUUID } from "node:crypto";
import { SDKError, type HostConnection } from "./ipc.js";
import {
  SDKAssistAccessError,
  type AssistAPI,
  type AssistSessionInfo,
  type AssistSessionOptions,
  type AssistStreamChunk,
  type AssistToolCall,
  type AssistToolResult,
} from "./types.js";

/** The dedicated entitled IPC route for the headless Assist variant. */
const ASSIST_INVOKE_METHOD = "assist.invoke";
/** Host→extension event carrying stream chunks for `message.stream`. */
const ASSIST_STREAM_EVENT = "assist.stream";

function validateSessionId(sessionId: unknown): string {
  if (typeof sessionId !== "string" || sessionId.length === 0) {
    throw new SDKError("INVALID_ARGUMENT", "Assist sessionId must be a non-empty string.");
  }
  return sessionId;
}

function validateMessage(message: unknown): string {
  if (typeof message !== "string" || message.length === 0) {
    throw new SDKError("INVALID_ARGUMENT", "Assist message must be a non-empty string.");
  }
  return message;
}

/**
 * Translates ONLY the host's typed Assist denial into the user-facing
 * error. Everything else rethrows unchanged — the TS layer never decides
 * entitlement on its own.
 */
function mapAssistDenial(error: unknown): never {
  if (error instanceof SDKError && error.code === "ASSIST_DENIED") {
    throw new SDKAssistAccessError(error.correlationId);
  }
  throw error;
}

function assertSessionInfo(payload: unknown): AssistSessionInfo {
  if (typeof payload !== "object" || payload === null) {
    throw new SDKError("IPC_MALFORMED", "The host returned an invalid assist session.", undefined);
  }
  const record = payload as Record<string, unknown>;
  if (typeof record["sessionId"] !== "string" || typeof record["createdAt"] !== "string") {
    throw new SDKError("IPC_MALFORMED", "The host returned an invalid assist session.", undefined);
  }
  return { sessionId: record["sessionId"], createdAt: record["createdAt"] };
}

/**
 * Builds the real headless Assist API over an IPC connection. Every call
 * below performs a genuine `assist.invoke` round-trip; nothing is
 * simulated. In extension code prefer `context.assist` (wired by
 * `createContext` in `context.ts`).
 */
export function createAssistAPI(connection: HostConnection): AssistAPI {
  async function invoke<T>(op: string, payload: Record<string, unknown>, requestId?: string): Promise<T> {
    try {
      // CALL SITE — `assist.invoke` is the dedicated entitled route the
      // sibling task implements in SDKIPCDispatcher + SDKAssistGate (the
      // gate currently deny-lists the `assist` substring; the sibling
      // carves out the entitled path). Until that lands, the host answers
      // with the typed ASSIST_DENIED denial, mapped below.
      return await connection.request<T>(ASSIST_INVOKE_METHOD, { op, ...payload }, requestId);
    } catch (error) {
      mapAssistDenial(error);
    }
  }

  /**
   * Streams one message's response. The `message.stream` request is
   * awaited FIRST so a host denial surfaces as SDKAssistAccessError
   * before any chunk is yielded; chunks arriving meanwhile are queued.
   */
  async function* streamChunks(sessionId: string, message: string): AsyncGenerator<AssistStreamChunk> {
    const requestId = randomUUID();
    const queue: AssistStreamChunk[] = [];
    let done = false;
    let failure: unknown = null;
    let wake: (() => void) | null = null;

    const unsubscribe = connection.onEvent((event) => {
      if (event.requestId !== requestId || event.name !== ASSIST_STREAM_EVENT) return;
      const payload =
        typeof event.payload === "object" && event.payload !== null
          ? (event.payload as Record<string, unknown>)
          : null;
      if (payload === null) return;
      if (payload["error"] !== undefined) {
        failure = new SDKError(
          "IPC_MALFORMED",
          `Assist stream failed: ${String(payload["error"])}`,
          requestId,
        );
      } else {
        const chunk: AssistStreamChunk = {
          delta: typeof payload["delta"] === "string" ? payload["delta"] : "",
          done: payload["done"] === true,
        };
        queue.push(chunk);
        if (chunk.done) done = true;
      }
      wake?.();
    });

    try {
      await invoke<unknown>("message.stream", { sessionId, message }, requestId);
      for (;;) {
        const chunk = queue.shift();
        if (chunk !== undefined) {
          if (failure !== null) throw failure;
          yield chunk;
          if (chunk.done) return;
          continue;
        }
        if (failure !== null) throw failure;
        if (done) return;
        await new Promise<void>((resolve) => {
          wake = resolve;
        });
        wake = null;
      }
    } finally {
      unsubscribe();
    }
  }

  const api: AssistAPI = {
    async createSession(options?: AssistSessionOptions): Promise<AssistSessionInfo> {
      const payload: Record<string, unknown> = {};
      if (options?.systemPrompt !== undefined) {
        if (typeof options.systemPrompt !== "string" || options.systemPrompt.length === 0) {
          throw new SDKError("INVALID_ARGUMENT", "Assist systemPrompt must be a non-empty string.");
        }
        payload["systemPrompt"] = options.systemPrompt;
      }
      if (options?.model !== undefined) {
        if (typeof options.model !== "string" || options.model.length === 0) {
          throw new SDKError("INVALID_ARGUMENT", "Assist model must be a non-empty string.");
        }
        payload["model"] = options.model;
      }
      const response = await invoke<unknown>("session.create", payload);
      return assertSessionInfo(response);
    },

    async listSessions(): Promise<AssistSessionInfo[]> {
      const response = await invoke<unknown>("session.list", {});
      if (typeof response !== "object" || response === null) {
        throw new SDKError("IPC_MALFORMED", "The host returned an invalid assist session list.", undefined);
      }
      const sessions = (response as Record<string, unknown>)["sessions"];
      if (!Array.isArray(sessions)) {
        throw new SDKError("IPC_MALFORMED", "The host returned an invalid assist session list.", undefined);
      }
      return sessions.map(assertSessionInfo);
    },

    async sendMessage(sessionId: string, message: string): Promise<string> {
      const sid = validateSessionId(sessionId);
      const text = validateMessage(message);
      const response = await invoke<unknown>("message.send", { sessionId: sid, message: text });
      if (typeof response !== "object" || response === null) {
        throw new SDKError("IPC_MALFORMED", "The host returned an invalid assist reply.", undefined);
      }
      const reply = (response as Record<string, unknown>)["reply"];
      if (typeof reply !== "string") {
        throw new SDKError("IPC_MALFORMED", "The host returned an invalid assist reply.", undefined);
      }
      return reply;
    },

    streamMessage(sessionId: string, message: string): AsyncIterable<AssistStreamChunk> {
      // Validated eagerly (synchronously at call time), not deferred to
      // first iterator pull.
      const sid = validateSessionId(sessionId);
      const text = validateMessage(message);
      const generator = streamChunks(sid, text);
      return {
        [Symbol.asyncIterator](): AsyncIterator<AssistStreamChunk> {
          return generator;
        },
      };
    },

    async invokeTool(sessionId: string, call: AssistToolCall): Promise<AssistToolResult> {
      const sid = validateSessionId(sessionId);
      if (typeof call !== "object" || call === null) {
        throw new SDKError("INVALID_ARGUMENT", "Assist tool call must be an object.");
      }
      if (typeof call.tool !== "string" || call.tool.length === 0) {
        throw new SDKError("INVALID_ARGUMENT", "Assist tool name must be a non-empty string.");
      }
      if (typeof call.arguments !== "object" || call.arguments === null || Array.isArray(call.arguments)) {
        throw new SDKError("INVALID_ARGUMENT", "Assist tool arguments must be an object.");
      }
      const response = await invoke<unknown>("tool.invoke", {
        sessionId: sid,
        tool: call.tool,
        arguments: call.arguments,
      });
      if (typeof response !== "object" || response === null) {
        throw new SDKError("IPC_MALFORMED", "The host returned an invalid assist tool result.", undefined);
      }
      const record = response as Record<string, unknown>;
      if (typeof record["tool"] !== "string" || !("result" in record)) {
        throw new SDKError("IPC_MALFORMED", "The host returned an invalid assist tool result.", undefined);
      }
      return { tool: record["tool"], result: record["result"] };
    },

    async closeSession(sessionId: string): Promise<void> {
      const sid = validateSessionId(sessionId);
      // The host answers with a null payload on success.
      await invoke<unknown>("session.close", { sessionId: sid });
    },
  };

  return api;
}
