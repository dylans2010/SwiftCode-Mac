import Foundation

// MARK: - SDKMessageType
//
// Discriminator for every IPC frame on the stdio NDJSON transport
// (spec §10.4, architecture doc §4).

public enum SDKMessageType: String, Codable, Sendable {
    /// Host → extension or extension → host call expecting a response.
    case request
    /// Reply to a `request`, correlated by `requestId`.
    case response
    /// Unsolicited host → extension notification (e.g. build output).
    case event
}

// MARK: - SDKRequestEnvelope
//
// Versioned request frame. `method` names a capability operation
// (e.g. `"sourceControl.getStatus"`); `payload` is validated against the
// method's schema. Extension identity is NEVER taken from the payload —
// the host binds it to the runtime session (spec §10.4).

public struct SDKRequestEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    /// Host/runtime protocol version. Must equal the negotiated version (1).
    public let protocolVersion: Int
    /// Always `.request`.
    public let type: SDKMessageType
    /// Caller-generated correlation ID, echoed in the response.
    public let requestId: String
    /// Capability operation, e.g. `"sourceControl.getStatus"`.
    public let method: String
    /// Method-specific arguments.
    public let payload: Payload

    public init(
        protocolVersion: Int = SDKIPCCodec.sdkProtocolVersion,
        requestId: String = UUID().uuidString,
        method: String,
        payload: Payload
    ) {
        self.protocolVersion = protocolVersion
        self.type = .request
        self.requestId = requestId
        self.method = method
        self.payload = payload
    }
}

// MARK: - SDKResponseEnvelope
//
// Versioned response frame. Exactly one of `payload` / `error` is set:
// `ok == true` carries `payload`, `ok == false` carries `error`.

public struct SDKResponseEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    /// Host/runtime protocol version.
    public let protocolVersion: Int
    /// Always `.response`.
    public let type: SDKMessageType
    /// Echoes the request's `requestId`.
    public let requestId: String
    /// True on success; false when `error` is set.
    public let ok: Bool
    /// Result payload on success; nil on failure.
    public let payload: Payload?
    /// Typed error on failure; nil on success.
    public let error: SDKErrorPayload?

    public init(
        protocolVersion: Int = SDKIPCCodec.sdkProtocolVersion,
        requestId: String,
        payload: Payload
    ) {
        self.protocolVersion = protocolVersion
        self.type = .response
        self.requestId = requestId
        self.ok = true
        self.payload = payload
        self.error = nil
    }

    public init(
        protocolVersion: Int = SDKIPCCodec.sdkProtocolVersion,
        requestId: String,
        error: SDKErrorPayload
    ) {
        self.protocolVersion = protocolVersion
        self.type = .response
        self.requestId = requestId
        self.ok = false
        self.payload = nil
        self.error = error
    }
}

// MARK: - SDKEventEnvelope
//
// Versioned unsolicited event frame (host → extension), e.g. streamed
// build output. `requestId` correlates the event with the originating
// request/subscription.

public struct SDKEventEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    /// Host/runtime protocol version.
    public let protocolVersion: Int
    /// Always `.event`.
    public let type: SDKMessageType
    /// Correlation ID of the originating request/subscription.
    public let requestId: String
    /// Event name, e.g. `"build.output"`.
    public let event: String
    /// Event-specific data.
    public let payload: Payload

    public init(
        protocolVersion: Int = SDKIPCCodec.sdkProtocolVersion,
        requestId: String,
        event: String,
        payload: Payload
    ) {
        self.protocolVersion = protocolVersion
        self.type = .event
        self.requestId = requestId
        self.event = event
        self.payload = payload
    }
}

// MARK: - SDKErrorPayload
//
// Wire representation of an `SDKError`. Only the stable code, the
// user-safe message, and the correlation ID cross the IPC boundary.
// The actionable suggestion stays host-side (shown in host UI), and
// structured diagnostics stay in the developer log, mapped by
// `correlationId` — neither is rendered to extensions verbatim.

public struct SDKErrorPayload: Codable, Sendable {
    /// Stable error code, e.g. `"PERMISSION_DENIED"`.
    public let code: String
    /// User-safe message (no paths, tokens, or internal identifiers).
    public let message: String
    /// ID shared with the host-side developer log entry.
    public let correlationId: String

    public init(code: String, message: String, correlationId: String) {
        self.code = code
        self.message = message
        self.correlationId = correlationId
    }

    /// Projects an `SDKError` onto the wire. `code` is the raw string of
    /// `SDKErrorCode` so both sides share the fixed taxonomy
    /// (architecture doc §8).
    public init(from sdkError: SDKError) {
        self.code = sdkError.code.rawValue
        self.message = sdkError.message
        self.correlationId = sdkError.correlationId
    }
}

// MARK: - SDKIPCCodec
//
// Encode/decode entry point for the stdio NDJSON transport. Encoded frames
// are compact JSON with no literal newline characters, so each `Data` value
// is exactly one NDJSON line.

public enum SDKIPCCodec {
    /// Current host/runtime protocol version (spec §18, ADR §10).
    public static let sdkProtocolVersion: Int = 1

    /// Maximum accepted IPC frame size: 1 MiB (architecture doc §4).
    /// Oversized frames are rejected with `RESOURCE_LIMIT_EXCEEDED`.
    public static let maxMessageBytes: Int = 1_048_576

    public static func encodeRequest<Payload: Codable & Sendable>(
        _ envelope: SDKRequestEnvelope<Payload>
    ) -> Data {
        encode(envelope)
    }

    public static func encodeResponse<Payload: Codable & Sendable>(
        _ envelope: SDKResponseEnvelope<Payload>
    ) -> Data {
        encode(envelope)
    }

    public static func encodeEvent<Payload: Codable & Sendable>(
        _ envelope: SDKEventEnvelope<Payload>
    ) -> Data {
        encode(envelope)
    }

    /// Peeks at a frame's `type` without decoding its payload, so the
    /// dispatcher can route before paying for full validation.
    /// - Throws: `SDKError` with code `.ipcMalformed` when the frame is not
    ///   a valid envelope, or `.resourceLimitExceeded` when it exceeds
    ///   `maxMessageBytes`.
    public static func decodeEnvelopeType(from data: Data) throws -> SDKMessageType {
        guard data.count <= maxMessageBytes else {
            throw SDKError(
                code: .resourceLimitExceeded,
                message: "IPC message exceeds the \(maxMessageBytes)-byte limit.",
                suggestion: "Reduce the payload size (e.g. request a bounded diff) and retry."
            )
        }
        do {
            return try JSONDecoder().decode(EnvelopePeek.self, from: data).type
        } catch {
            throw SDKError(
                code: .ipcMalformed,
                message: "Message is not a valid SDK IPC envelope.",
                suggestion: "Send a JSON object with protocolVersion, type, and requestId fields.",
                diagnostics: ["underlyingError": error.localizedDescription]
            )
        }
    }

    // MARK: - Private

    /// Minimal shape used only to peek at `type` (and confirm the frame
    /// carries a protocol version) without decoding the payload.
    private struct EnvelopePeek: Decodable {
        let protocolVersion: Int
        let type: SDKMessageType
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // JSONEncoder escapes control characters, so compact output never
        // contains a literal newline: each result is one NDJSON line.
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        // These are Codable value types; encoding cannot fail with the
        // strategies above. The empty-Data fallback is unreachable by
        // construction and exists only to keep this API infallible.
        return (try? encoder.encode(value)) ?? Data()
    }
}
