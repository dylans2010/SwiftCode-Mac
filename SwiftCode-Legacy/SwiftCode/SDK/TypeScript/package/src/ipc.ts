import { randomUUID } from "node:crypto";
import type { Readable } from "node:stream";
import type { SDKErrorShape } from "./types.js";

export const SDK_PROTOCOL_VERSION = 1;

export const REQUEST_TIMEOUT_MS = 60_000;

export class SDKError extends Error implements SDKErrorShape {
  readonly code: string;
  readonly correlationId: string;

  constructor(code: string, message: string, correlationId?: string) {
    super(message);
    this.name = "SDKError";
    this.code = code;
    this.correlationId = correlationId ?? randomUUID();
  }
}

export interface HostEvent {
  readonly name: string;
  readonly payload: unknown;
  readonly requestId: string;
}

export type HostEventListener = (event: HostEvent) => void;

export interface HostConnection {
  request<T>(method: string, payload?: unknown, requestId?: string): Promise<T>;
  onEvent(listener: HostEventListener): () => void;
  sendEvent(name: string, payload?: unknown): void;
  close(): void;
  readonly closed: boolean;
}

interface PendingRequest {
  resolve: (value: unknown) => void;
  reject: (reason: unknown) => void;
  timer: NodeJS.Timeout;
}

export function createStdioConnection(
  stdin: Readable = process.stdin,
  stdout: NodeJS.WritableStream = process.stdout,
): HostConnection {
  const pending = new Map<string, PendingRequest>();
  const eventListeners = new Set<HostEventListener>();
  let closed = false;
  let buffer = "";

  function diagnose(message: string, detail?: unknown): void {
    const suffix = detail === undefined ? "" : ` ${String(detail)}`;
    process.stderr.write(`[@swiftcode/sdk ipc] ${message}${suffix}\n`);
  }

  function failPending(requestId: string, error: unknown): void {
    const entry = pending.get(requestId);
    if (entry === undefined) return;
    pending.delete(requestId);
    clearTimeout(entry.timer);
    entry.reject(error);
  }

  function handleResponse(frame: Record<string, unknown>): void {
    const requestId = frame["requestId"];
    if (typeof requestId !== "string" || requestId.length === 0) {
      diagnose("response frame missing requestId; ignoring");
      return;
    }
    const entry = pending.get(requestId);
    if (entry === undefined) {
      diagnose(`response for unknown requestId ${requestId}; ignoring`);
      return;
    }
    pending.delete(requestId);
    clearTimeout(entry.timer);

    if (frame["protocolVersion"] !== SDK_PROTOCOL_VERSION) {
      entry.reject(
        new SDKError(
          "IPC_PROTOCOL_MISMATCH",
          `Unsupported IPC protocol version ${String(frame["protocolVersion"])}; this SDK speaks version ${SDK_PROTOCOL_VERSION}.`,
          requestId,
        ),
      );
      return;
    }

    if (frame["ok"] === false) {
      const raw = frame["error"];
      const code = typeof raw === "object" && raw !== null && "code" in raw ? String((raw as Record<string, unknown>)["code"]) : "UNKNOWN_ERROR";
      const message =
        typeof raw === "object" && raw !== null && "message" in raw ? String((raw as Record<string, unknown>)["message"]) : "The host rejected the request.";
      const correlationId =
        typeof raw === "object" && raw !== null && "correlationId" in raw ? String((raw as Record<string, unknown>)["correlationId"]) : requestId;
      entry.reject(new SDKError(code, message, correlationId));
      return;
    }

    entry.resolve(frame["payload"]);
  }

  function handleEvent(frame: Record<string, unknown>): void {
    if (frame["protocolVersion"] !== SDK_PROTOCOL_VERSION) {
      diagnose(
        `event frame with unsupported protocolVersion ${String(frame["protocolVersion"])}; ignoring (this SDK speaks version ${SDK_PROTOCOL_VERSION})`,
      );
      return;
    }
    const name = frame["event"];
    if (typeof name !== "string" || name.length === 0) {
      diagnose("event frame missing event name; ignoring");
      return;
    }
    const event: HostEvent = {
      name,
      payload: frame["payload"],
      requestId: typeof frame["requestId"] === "string" ? frame["requestId"] : "",
    };
    for (const listener of eventListeners) {
      try {
        listener(event);
      } catch (error) {
        diagnose(`event listener threw for "${name}"`, error instanceof Error ? error.message : error);
      }
    }
  }

  function handleLine(line: string): void {
    if (line.trim().length === 0) return;
    let frame: unknown;
    try {
      frame = JSON.parse(line) as unknown;
    } catch {
      diagnose("malformed IPC frame ignored", line.slice(0, 160));
      return;
    }
    if (typeof frame !== "object" || frame === null) {
      diagnose("non-object IPC frame ignored");
      return;
    }
    const record = frame as Record<string, unknown>;
    switch (record["type"]) {
      case "response":
        handleResponse(record);
        break;
      case "event":
        handleEvent(record);
        break;
      default:
        diagnose(`unknown IPC frame type ${String(record["type"])}; ignoring`);
    }
  }

  function onData(chunk: Buffer | string): void {
    if (closed) return;
    buffer += chunk.toString("utf8");
    let index = buffer.indexOf("\n");
    while (index !== -1) {
      const line = buffer.slice(0, index);
      buffer = buffer.slice(index + 1);
      handleLine(line);
      index = buffer.indexOf("\n");
    }
  }

  function onEnd(): void {
    close();
  }

  function close(): void {
    if (closed) return;
    closed = true;
    stdin.off("data", onData);
    stdin.off("end", onEnd);
    stdin.off("close", onEnd);
    const error = new SDKError("IPC_CLOSED", "The IPC connection was closed.", undefined);
    for (const [requestId, entry] of pending) {
      pending.delete(requestId);
      clearTimeout(entry.timer);
      entry.reject(error);
    }
  }

  stdin.on("data", onData);
  stdin.on("end", onEnd);
  stdin.on("close", onEnd);

  const connection: HostConnection = {
    get closed() {
      return closed;
    },

    request<T>(method: string, payload: unknown = {}, requestId: string = randomUUID()): Promise<T> {
      if (closed) {
        return Promise.reject(new SDKError("IPC_CLOSED", "Cannot send request: the IPC connection is closed."));
      }
      const frame = {
        protocolVersion: SDK_PROTOCOL_VERSION,
        type: "request",
        requestId,
        method,
        payload: payload ?? {},
      };
      return new Promise<T>((resolve, reject) => {
        const timer = setTimeout(() => {
          pending.delete(requestId);
          reject(
            new SDKError(
              "IPC_TIMEOUT",
              `Request "${method}" timed out after ${REQUEST_TIMEOUT_MS / 1000} seconds.`,
              requestId,
            ),
          );
        }, REQUEST_TIMEOUT_MS);
        timer.unref?.();
        pending.set(requestId, {
          resolve: (value: unknown) => resolve(value as T),
          reject,
          timer,
        });
        stdout.write(`${JSON.stringify(frame)}\n`, (error) => {
          if (error !== null && error !== undefined) {
            failPending(requestId, new SDKError("IPC_CLOSED", `Failed to write IPC request "${method}".`, requestId));
          }
        });
      });
    },

    onEvent(listener: HostEventListener): () => void {
      eventListeners.add(listener);
      return () => {
        eventListeners.delete(listener);
      };
    },

    sendEvent(name: string, payload: unknown = {}): void {
      if (closed) return;
      if (typeof name !== "string" || name.length === 0) {
        diagnose("refusing to send event with empty name");
        return;
      }
      const frame = {
        protocolVersion: SDK_PROTOCOL_VERSION,
        type: "event",
        requestId: randomUUID(),
        event: name,
        payload: payload ?? {},
      };
      try {
        stdout.write(`${JSON.stringify(frame)}\n`);
      } catch (error) {
        diagnose(
          `failed to write event "${name}"`,
          error instanceof Error ? error.message : error,
        );
      }
    },

    close,
  };

  return connection;
}
