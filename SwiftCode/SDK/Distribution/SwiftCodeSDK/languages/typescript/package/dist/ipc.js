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
import { randomUUID } from "node:crypto";
/** Protocol version this SDK speaks. Matches `SDKIPCCodec.sdkProtocolVersion`. */
export const SDK_PROTOCOL_VERSION = 1;
/** Wall-clock budget per request (matches the host dispatcher's 60 s). */
export const REQUEST_TIMEOUT_MS = 60_000;
/** Typed error raised for `ok: false` responses and IPC failures. */
export class SDKError extends Error {
    code;
    correlationId;
    constructor(code, message, correlationId) {
        super(message);
        this.name = "SDKError";
        this.code = code;
        this.correlationId = correlationId ?? randomUUID();
    }
}
/**
 * Creates a {@link HostConnection} over stdio (NDJSON).
 *
 * Malformed inbound frames are ignored with a stderr diagnostic and never
 * crash the connection. A response whose `protocolVersion` is not 1 rejects
 * with an `SDKError` of code `IPC_PROTOCOL_MISMATCH`.
 */
export function createStdioConnection(stdin = process.stdin, stdout = process.stdout) {
    const pending = new Map();
    const eventListeners = new Set();
    let closed = false;
    let buffer = "";
    function diagnose(message, detail) {
        const suffix = detail === undefined ? "" : ` ${String(detail)}`;
        process.stderr.write(`[@swiftcode/sdk ipc] ${message}${suffix}\n`);
    }
    function failPending(requestId, error) {
        const entry = pending.get(requestId);
        if (entry === undefined)
            return;
        pending.delete(requestId);
        clearTimeout(entry.timer);
        entry.reject(error);
    }
    function handleResponse(frame) {
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
            entry.reject(new SDKError("IPC_PROTOCOL_MISMATCH", `Unsupported IPC protocol version ${String(frame["protocolVersion"])}; this SDK speaks version ${SDK_PROTOCOL_VERSION}.`, requestId));
            return;
        }
        if (frame["ok"] === false) {
            const raw = frame["error"];
            const code = typeof raw === "object" && raw !== null && "code" in raw ? String(raw["code"]) : "UNKNOWN_ERROR";
            const message = typeof raw === "object" && raw !== null && "message" in raw ? String(raw["message"]) : "The host rejected the request.";
            const correlationId = typeof raw === "object" && raw !== null && "correlationId" in raw ? String(raw["correlationId"]) : requestId;
            entry.reject(new SDKError(code, message, correlationId));
            return;
        }
        entry.resolve(frame["payload"]);
    }
    function handleEvent(frame) {
        if (frame["protocolVersion"] !== SDK_PROTOCOL_VERSION) {
            diagnose(`event frame with unsupported protocolVersion ${String(frame["protocolVersion"])}; ignoring (this SDK speaks version ${SDK_PROTOCOL_VERSION})`);
            return;
        }
        const name = frame["event"];
        if (typeof name !== "string" || name.length === 0) {
            diagnose("event frame missing event name; ignoring");
            return;
        }
        const event = {
            name,
            payload: frame["payload"],
            requestId: typeof frame["requestId"] === "string" ? frame["requestId"] : "",
        };
        for (const listener of eventListeners) {
            try {
                listener(event);
            }
            catch (error) {
                diagnose(`event listener threw for "${name}"`, error instanceof Error ? error.message : error);
            }
        }
    }
    function handleLine(line) {
        if (line.trim().length === 0)
            return;
        let frame;
        try {
            frame = JSON.parse(line);
        }
        catch {
            diagnose("malformed IPC frame ignored", line.slice(0, 160));
            return;
        }
        if (typeof frame !== "object" || frame === null) {
            diagnose("non-object IPC frame ignored");
            return;
        }
        const record = frame;
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
    function onData(chunk) {
        if (closed)
            return;
        buffer += chunk.toString("utf8");
        let index = buffer.indexOf("\n");
        while (index !== -1) {
            const line = buffer.slice(0, index);
            buffer = buffer.slice(index + 1);
            handleLine(line);
            index = buffer.indexOf("\n");
        }
    }
    function onEnd() {
        close();
    }
    function close() {
        if (closed)
            return;
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
    const connection = {
        get closed() {
            return closed;
        },
        request(method, payload = {}, requestId = randomUUID()) {
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
            return new Promise((resolve, reject) => {
                const timer = setTimeout(() => {
                    pending.delete(requestId);
                    reject(new SDKError("IPC_TIMEOUT", `Request "${method}" timed out after ${REQUEST_TIMEOUT_MS / 1000} seconds.`, requestId));
                }, REQUEST_TIMEOUT_MS);
                timer.unref?.();
                pending.set(requestId, {
                    resolve: (value) => resolve(value),
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
        onEvent(listener) {
            eventListeners.add(listener);
            return () => {
                eventListeners.delete(listener);
            };
        },
        sendEvent(name, payload = {}) {
            if (closed)
                return;
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
            }
            catch (error) {
                diagnose(`failed to write event "${name}"`, error instanceof Error ? error.message : error);
            }
        },
        close,
    };
    return connection;
}
//# sourceMappingURL=ipc.js.map