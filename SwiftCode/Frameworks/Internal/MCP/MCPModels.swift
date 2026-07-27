import Foundation

// MARK: - MCP Transport enum

public enum MCPTransport: String, Codable, Sendable, CaseIterable {
    case stdio = "stdio"
    case http = "http"
    case https = "https"
}

// MARK: - MCP Authentication Type enum

public enum MCPAuthenticationType: String, Codable, Sendable, CaseIterable {
    case none = "None"
    case apiKey = "API Key"
    case bearerToken = "Bearer Token"
    case customHeaders = "Custom HTTP Headers"
    case envVars = "Environment Variables"
    case oauth = "OAuth"
}

// MARK: - MCP Server Status enum

public enum MCPServerStatus: String, Codable, Sendable, CaseIterable {
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case connected = "Connected"
    case failed = "Failed"
}

// MARK: - MCP Error Struct

public enum MCPError: LocalizedError, Sendable {
    case invalidURL(String)
    case connectionFailed(String)
    case processLaunchFailed(String)
    case handshakeFailed(String)
    case capabilityNegotiationFailed(String)
    case toolDiscoveryFailed(String)
    case toolExecutionFailed(String)
    case decodingFailed(String)
    case authenticationFailed(String)
    case timeout(String)
    case invalidConfiguration(String)
    case keyChainError(String)
    case requestValidationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let details): return "Invalid URL: \(details)"
        case .connectionFailed(let details): return "Connection Failed: \(details)"
        case .processLaunchFailed(let details): return "Process Launch Failed: \(details)"
        case .handshakeFailed(let details): return "Handshake Failed: \(details)"
        case .capabilityNegotiationFailed(let details): return "Capability Negotiation Failed: \(details)"
        case .toolDiscoveryFailed(let details): return "Tool Discovery Failed: \(details)"
        case .toolExecutionFailed(let details): return "Tool Execution Failed: \(details)"
        case .decodingFailed(let details): return "Decoding Failed: \(details)"
        case .authenticationFailed(let details): return "Authentication Failed: \(details)"
        case .timeout(let details): return "Timeout: \(details)"
        case .invalidConfiguration(let details): return "Invalid Configuration: \(details)"
        case .keyChainError(let details): return "Keychain Error: \(details)"
        case .requestValidationFailed(let details): return "Request Validation Failed: \(details)"
        }
    }
}

// MARK: - MCP Tool Input Schema

public struct MCPToolSchema: Codable, Sendable, Hashable {
    public let type: String
    public let properties: [String: MCPToolProperty]?
    public let required: [String]?

    public init(type: String, properties: [String: MCPToolProperty]? = nil, required: [String]? = nil) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

public struct MCPToolProperty: Codable, Sendable, Hashable {
    public let type: String
    public let description: String?
    public let `enum`: [String]?

    public init(type: String, description: String? = nil, `enum`: [String]? = nil) {
        self.type = type
        self.description = description
        self.enum = `enum`
    }
}

// MARK: - MCP Tool Representation

public struct MCPTool: Codable, Sendable, Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let description: String?
    public let inputSchema: MCPToolSchema
    public var isCallable: Bool

    public init(name: String, description: String? = nil, inputSchema: MCPToolSchema, isCallable: Bool = true) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.isCallable = isCallable
    }

    enum CodingKeys: String, CodingKey {
        case name, description, inputSchema, isCallable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.inputSchema = try container.decode(MCPToolSchema.self, forKey: .inputSchema)
        self.isCallable = try container.decodeIfPresent(Bool.self, forKey: .isCallable) ?? true
    }
}

// MARK: - MCP Capability Representation

public struct MCPCapability: Codable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

// MARK: - MCP Server Metadata

public struct MCPServerMetadata: Codable, Sendable {
    public let name: String
    public let version: String
    public let protocolVersion: String

    public init(name: String, version: String, protocolVersion: String) {
        self.name = name
        self.version = version
        self.protocolVersion = protocolVersion
    }
}

// MARK: - MCPServer State and Preferences

public struct MCPServer: Codable, Sendable, Identifiable {
    public let id: UUID
    public var displayName: String
    public var transport: MCPTransport
    public var urlString: String
    public var executablePath: String?
    public var launchArguments: [String]?
    public var envVariables: [String: String]?
    public var customHeaders: [String: String]?
    public var authType: MCPAuthenticationType

    // Runtime state (non-persistent but updated inside Manager)
    public var status: MCPServerStatus
    public var lastError: String?
    public var toolCount: Int
    public var lastRefresh: Date?
    public var capabilities: [String]
    public var tools: [MCPTool]

    public init(
        id: UUID = UUID(),
        displayName: String,
        transport: MCPTransport,
        urlString: String = "",
        executablePath: String? = nil,
        launchArguments: [String]? = nil,
        envVariables: [String: String]? = nil,
        customHeaders: [String: String]? = nil,
        authType: MCPAuthenticationType = .none,
        status: MCPServerStatus = .disconnected,
        lastError: String? = nil,
        toolCount: Int = 0,
        lastRefresh: Date? = nil,
        capabilities: [String] = [],
        tools: [MCPTool] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.transport = transport
        self.urlString = urlString
        self.executablePath = executablePath
        self.launchArguments = launchArguments
        self.envVariables = envVariables
        self.customHeaders = customHeaders
        self.authType = authType
        self.status = status
        self.lastError = lastError
        self.toolCount = toolCount
        self.lastRefresh = lastRefresh
        self.capabilities = capabilities
        self.tools = tools
    }
}

// MARK: - MCP Execution Request/Response

public struct MCPExecutionRequest: Codable, Sendable {
    public let name: String
    public let arguments: [String: JSONValue]

    public init(name: String, arguments: [String: JSONValue]) {
        self.name = name
        self.arguments = arguments
    }
}

public struct MCPExecutionResponse: Codable, Sendable {
    public let content: [MCPContentBlock]
    public let isError: Bool

    public init(content: [MCPContentBlock], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }
}

public struct MCPContentBlock: Codable, Sendable {
    public let type: String
    public let text: String?

    public init(type: String, text: String?) {
        self.type = type
        self.text = text
    }
}

// MARK: - MCP Logging Subsystem

public enum MCPLogSeverity: String, Codable, Sendable, CaseIterable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

public struct MCPLogEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let severity: MCPLogSeverity
    public let serverName: String
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), severity: MCPLogSeverity, serverName: String, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.severity = severity
        self.serverName = serverName
        self.message = message
    }
}

@Observable
@MainActor
public final class MCPLoggingManager: Sendable {
    public static let shared = MCPLoggingManager()

    public private(set) var logs: [MCPLogEntry] = []

    private init() {}

    public func log(severity: MCPLogSeverity, serverName: String, message: String) {
        let entry = MCPLogEntry(severity: severity, serverName: serverName, message: message)
        logs.append(entry)

        let subsystem = "com.swiftcode.mcp"
        let logger = os.Logger(subsystem: subsystem, category: serverName)
        let logMsg = "[\(severity.rawValue)] \(message)"
        switch severity {
        case .info:
            logger.info("\(logMsg)")
        case .warning:
            logger.warning("\(logMsg)")
        case .error:
            logger.error("\(logMsg)")
        }
    }

    public func clearLogs() {
        logs.removeAll()
    }
}
