/**
 * IPC client for the SwiftCode extension host (Docs/Intro-to-SDK.md §10.4).
 *
 * NDJSON transport: one JSON object per line, UTF-8, over the stdio pipe.
 * Requests correlate to responses by `requestId` with a 60 s timeout;
 * incoming `type: "event"` frames are routed to registered listeners.
 *
 * Wire format (must match the Swift host exactly):
 *   request:  {"protocolVersion":1,"type":"request","requestId":"<uuid>","method":"<m>","payload":{...}}
 *   response: {"protocolVersion":1,"type":"response","requestId":"<same>","ok":true,"payload":{...}}
 *             or {"ok":false,"error":{"code":"...","message":"...","correlationId":"..."}}
 *   event:    {"protocolVersion":1,"type":"event","requestId":"<uuid>","event":"<name>","payload":{...}}
 */
import type { Readable } from "node:stream";
import type { SDKErrorShape } from "./types.js";
/** Protocol version this SDK speaks. Matches `SDKIPCCodec.sdkProtocolVersion`. */
export declare const SDK_PROTOCOL_VERSION = 1;
/** Wall-clock budget per request (matches the host dispatcher's 60 s). */
export declare const REQUEST_TIMEOUT_MS = 60000;
/** Typed error raised for `ok: false` responses and IPC failures. */
export declare class SDKError extends Error implements SDKErrorShape {
    readonly code: string;
    readonly correlationId: string;
    constructor(code: string, message: string, correlationId?: string);
}
/** A host→extension event frame, decoded. */
export interface HostEvent {
    /** Event name, e.g. "build.output", "build.finished", "shutdown". */
    readonly name: string;
    readonly payload: unknown;
    /** Correlation ID of the originating request/subscription. */
    readonly requestId: string;
}
export type HostEventListener = (event: HostEvent) => void;
/** Low-level duplex connection to the SwiftCode host. */
export interface HostConnection {
    /**
     * Sends a request and resolves with the response payload.
     * Rejects with {@link SDKError} on `ok: false`, protocol mismatch, or timeout.
     */
    request<T>(method: string, payload?: unknown, requestId?: string): Promise<T>;
    /** Subscribes to unsolicited host→extension events. Returns an unsubscribe fn. */
    onEvent(listener: HostEventListener): () => void;
    /**
     * Sends an unsolicited extension→host event frame (NDJSON `type: "event"`).
     * Fire-and-forget: a closed connection is a no-op and write failures are
     * reported to stderr; it never throws, so lifecycle code can call it from
     * any state (activation success/failure, command results, crash paths).
     */
    sendEvent(name: string, payload?: unknown): void;
    /** Rejects all pending requests and stops processing. Idempotent. */
    close(): void;
    /** True once `close()` has run (also set when stdin ends). */
    readonly closed: boolean;
}
/**
 * Creates a {@link HostConnection} over stdio (NDJSON).
 *
 * Malformed inbound frames are ignored with a stderr diagnostic and never
 * crash the connection. A response whose `protocolVersion` is not 1 rejects
 * with an `SDKError` of code `IPC_PROTOCOL_MISMATCH`.
 */
export declare function createStdioConnection(stdin?: Readable, stdout?: NodeJS.WritableStream): HostConnection;
