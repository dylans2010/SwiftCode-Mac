import Foundation

// MARK: - JSON value (arbitrary JSON for RPC params/results)

public enum ExtV2JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([ExtV2JSONValue])
    case object([String: ExtV2JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Int.self) { self = .int(value); return }
        if let value = try? container.decode(Double.self) { self = .double(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([ExtV2JSONValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: ExtV2JSONValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: ExtV2JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    public var arrayValue: [ExtV2JSONValue]? {
        if case .array(let values) = self { return values }
        return nil
    }

    public static func stringDictionary(_ dict: [String: String]) -> ExtV2JSONValue {
        .object(dict.mapValues(ExtV2JSONValue.string))
    }
}

// MARK: - Versioned NDJSON RPC

/// One NDJSON line per message, JSON-RPC 2.0 shaped, protocol version 1.
/// The method allowlist is the security boundary: an extension host that
/// sends any other method gets a fault, not a dispatch.
public struct ExtV2RPCRequest: Codable, Sendable {
    public static let protocolVersion = 1
    public let jsonrpc = "2.0"
    public let protocolVersion: Int
    public let id: String
    public let method: String
    public let params: ExtV2JSONValue?

    public init(id: String, method: String, params: ExtV2JSONValue? = nil) {
        self.protocolVersion = Self.protocolVersion
        self.id = id
        self.method = method
        self.params = params
    }

    enum CodingKeys: String, CodingKey {
        case jsonrpc, protocolVersion, id, method, params
    }
}

public struct ExtV2RPCResponse: Codable, Sendable {
    public let jsonrpc = "2.0"
    public let id: String
    public let result: ExtV2JSONValue?
    public let error: ExtV2RPCErrorPayload?

    public init(id: String, result: ExtV2JSONValue? = nil, error: ExtV2RPCErrorPayload? = nil) {
        self.id = id; self.result = result; self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, result, error
    }
}

public struct ExtV2RPCErrorPayload: Codable, Sendable {
    public let code: Int
    public let message: String
}

public enum ExtV2RPC {
    /// Methods SwiftCode will ever accept from an extension host.
    public static let allowedHostMethods: Set<String> = [
        "host.log", "host.showMessage", "host.registerCommand",
        "host.registerTreeData", "host.setStatusBar", "host.appendOutput",
        "host.readFile", "host.writeFile", "host.applyEdit",
        "host.registerCompletionProvider", "host.registerHoverProvider",
        "host.registerDefinitionProvider", "host.registerReferenceProvider",
        "host.registerFormattingProvider", "host.registerCodeActionProvider",
        "host.publishDiagnostics", "host.requestPermission",
        "host.getConfiguration", "host.showQuickPick", "host.showInputBox",
    ]

    /// Methods SwiftCode sends to a host.
    public static let allowedSwiftCodeMethods: Set<String> = [
        "activate", "deactivate", "executeCommand", "shutdown",
        "didChangeTextDocument", "didChangeConfiguration",
    ]

    /// Validates and decodes one NDJSON line. Throws on oversize lines,
    /// unknown protocol versions, and disallowed methods — all three are
    /// treated as host faults, not as data to be lenient about.
    public static func decodeRequest(from line: Data, fromHost: Bool) throws -> ExtV2RPCRequest {
        guard line.count <= ExtV2ResourceLimits.maxIPCMessageBytes else {
            throw ExtV2Error.invalidRequest("IPC message exceeds the size limit and was dropped.")
        }
        let request = try JSONDecoder().decode(ExtV2RPCRequest.self, from: line)
        guard request.protocolVersion == ExtV2RPCRequest.protocolVersion else {
            throw ExtV2Error.invalidRequest("Unsupported extension-host protocol version \(request.protocolVersion).")
        }
        let allowed = fromHost ? allowedHostMethods : allowedSwiftCodeMethods
        guard allowed.contains(request.method) else {
            throw ExtV2Error.invalidRequest("Disallowed IPC method '\(request.method)'.")
        }
        return request
    }

    public static func encodeRequest(_ request: ExtV2RPCRequest) throws -> Data {
        var data = try JSONEncoder().encode(request)
        data.append(0x0A) // NDJSON line terminator
        return data
    }

    public static func encodeResponse(_ response: ExtV2RPCResponse) throws -> Data {
        var data = try JSONEncoder().encode(response)
        data.append(0x0A)
        return data
    }
}
