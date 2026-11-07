import Foundation

public enum SDKMessageType: String, Codable, Sendable {
    case request
    case response
    case event
}

public struct SDKRequestEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let protocolVersion: Int
    public let type: SDKMessageType
    public let requestId: String
    public let method: String
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

public struct SDKResponseEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let protocolVersion: Int
    public let type: SDKMessageType
    public let requestId: String
    public let ok: Bool
    public let payload: Payload?
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

public struct SDKEventEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let protocolVersion: Int
    public let type: SDKMessageType
    public let requestId: String
    public let event: String
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

public struct SDKErrorPayload: Codable, Sendable {
    public let code: String
    public let message: String
    public let correlationId: String

    public init(code: String, message: String, correlationId: String) {
        self.code = code
        self.message = message
        self.correlationId = correlationId
    }

    public init(from sdkError: SDKError) {
        self.code = sdkError.code.rawValue
        self.message = sdkError.message
        self.correlationId = sdkError.correlationId
    }
}

public enum SDKIPCCodec {
    public static let sdkProtocolVersion: Int = 1

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

    private struct EnvelopePeek: Decodable {
        let protocolVersion: Int
        let type: SDKMessageType
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return (try? encoder.encode(value)) ?? Data()
    }
}
