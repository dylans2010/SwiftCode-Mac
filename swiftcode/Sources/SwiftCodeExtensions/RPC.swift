import Foundation

public struct RPCRequest: Codable, Sendable {
    public static let protocolVersion: Int = 1
    public let jsonrpc: String
    public let protocolVersion: Int
    public let id: String
    public let method: String
    public let params: JSONValue?

    public init(id: String, method: String, params: JSONValue? = nil) {
        self.jsonrpc = "2.0"
        self.protocolVersion = Self.protocolVersion
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct RPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: String
    public let result: JSONValue?
    public let error: RPCErrorPayload?

    public init(id: String, result: JSONValue? = nil, error: RPCErrorPayload? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }
}

public struct RPCErrorPayload: Codable, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

public enum ExtensionRPC {
    public static let allowedHostMethods: Set<String> = [
        "host.log", "host.showMessage", "host.registerCommand", "host.registerTreeData",
        "host.setStatusBar", "host.appendOutput", "host.readFile", "host.writeFile",
        "host.applyEdit", "host.registerCompletionProvider", "host.registerHoverProvider",
        "host.registerDefinitionProvider", "host.registerReferenceProvider",
        "host.registerFormattingProvider", "host.registerCodeActionProvider",
        "host.publishDiagnostics", "host.requestPermission", "host.getConfiguration",
        "host.showQuickPick", "host.showInputBox",
    ]

    public static let allowedHostMethodsSwiftCode: Set<String> = [
        "activate", "deactivate", "executeCommand", "shutdown",
        "didChangeTextDocument", "didChangeConfiguration",
    ]

    public static let replyErrorCode = -32000
    public static let fatalErrorCode = -32001

    public static func decodeRequest(from line: Data, fromHost: Bool) throws -> RPCRequest {
        guard line.count <= ResourceLimits.maxIPCMessageBytes else {
            throw SwiftCodeExtensionError.host("IPC message exceeds the 1 MiB limit.")
        }
        let request: RPCRequest
        do {
            request = try JSONDecoder().decode(RPCRequest.self, from: line)
        } catch {
            throw SwiftCodeExtensionError.host("Unparseable IPC line: \(error.localizedDescription)")
        }
        guard request.protocolVersion == 1 else {
            throw SwiftCodeExtensionError.host("Unsupported IPC protocol version \(request.protocolVersion).")
        }
        let allowed = fromHost ? allowedHostMethods : allowedHostMethodsSwiftCode
        guard allowed.contains(request.method) else {
            throw SwiftCodeExtensionError.host("Method '\(request.method)' is not allowed in this direction.")
        }
        return request
    }

    public static func encodeRequest(_ request: RPCRequest) throws -> Data {
        var data = try JSONEncoder().encode(request)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    public static func encodeResponse(_ response: RPCResponse) throws -> Data {
        var data = try JSONEncoder().encode(response)
        data.append(UInt8(ascii: "\n"))
        return data
    }
}

public enum ResourceLimits {
    public static let maxVSIXBytes: Int = 64 * 1024 * 1024
    public static let maxExtractedBytes: Int = 512 * 1024 * 1024
    public static let maxArchiveEntries: Int = 20_000
    public static let maxIPCMessageBytes: Int = 1 * 1024 * 1024
    public static let hostActivationTimeout: TimeInterval = 30
    public static let hostCommandTimeout: TimeInterval = 60
    public static let registryTimeout: TimeInterval = 30
    public static let maxConsecutiveHostCrashes: Int = 3
}
