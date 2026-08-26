import Foundation

/// Canonical message envelope used by SwiftCode Connect V1 protocol.
public struct MessageEnvelope: Codable, Sendable {
    public let protocolVersion: Int
    public let messageID: String
    public let correlationID: String?
    public let type: ConnectMessageType
    public let timestamp: Date
    public let payload: Data

    public init(
        protocolVersion: Int = ConnectProtocolVersion.current,
        messageID: String = UUID().uuidString,
        correlationID: String? = nil,
        type: ConnectMessageType,
        timestamp: Date = Date(),
        payload: Data
    ) {
        self.protocolVersion = protocolVersion
        self.messageID = messageID
        self.correlationID = correlationID
        self.type = type
        self.timestamp = timestamp
        self.payload = payload
    }

    public static func encode<T: Encodable>(
        payload: T,
        type: ConnectMessageType,
        correlationID: String? = nil,
        messageID: String = UUID().uuidString
    ) throws -> MessageEnvelope {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return MessageEnvelope(
            protocolVersion: ConnectProtocolVersion.current,
            messageID: messageID,
            correlationID: correlationID,
            type: type,
            timestamp: Date(),
            payload: data
        )
    }

    public func decodePayload<T: Decodable>(_ type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: payload)
    }
}

// MARK: - Specific Payload Structures

// Handshake & Auth
public struct ConnectPairingRequestPayload: Codable, Sendable {
    public let deviceID: String
    public let deviceName: String
    public let deviceModel: String
    public let clientVersion: String
    public let publicKeyPem: String
    public let verificationCode: String

    public init(deviceID: String, deviceName: String, deviceModel: String, clientVersion: String, publicKeyPem: String, verificationCode: String) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.deviceModel = deviceModel
        self.clientVersion = clientVersion
        self.publicKeyPem = publicKeyPem
        self.verificationCode = verificationCode
    }
}

public struct ConnectPairingResponsePayload: Codable, Sendable {
    public let approved: Bool
    public let macName: String
    public let sessionToken: String?
    public let verificationCode: String?
    public let capabilities: [ConnectCapability]
    public let grantedPermissions: [ConnectPermission]

    public init(approved: Bool, macName: String, sessionToken: String?, verificationCode: String?, capabilities: [ConnectCapability], grantedPermissions: [ConnectPermission]) {
        self.approved = approved
        self.macName = macName
        self.sessionToken = sessionToken
        self.verificationCode = verificationCode
        self.capabilities = capabilities
        self.grantedPermissions = grantedPermissions
    }
}

public struct ConnectAuthRequestPayload: Codable, Sendable {
    public let deviceID: String
    public let sessionToken: String

    public init(deviceID: String, sessionToken: String) {
        self.deviceID = deviceID
        self.sessionToken = sessionToken
    }
}

public struct ConnectAuthResponsePayload: Codable, Sendable {
    public let authenticated: Bool
    public let sessionID: String?
    public let serverVersion: String
    public let capabilities: [ConnectCapability]
    public let permissions: [ConnectPermission]

    public init(authenticated: Bool, sessionID: String?, serverVersion: String, capabilities: [ConnectCapability], permissions: [ConnectPermission]) {
        self.authenticated = authenticated
        self.sessionID = sessionID
        self.serverVersion = serverVersion
        self.capabilities = capabilities
        self.permissions = permissions
    }
}

// Project & Git
public struct ConnectProjectInfo: Codable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let activeScheme: String?
    public let activeTarget: String?
    public let destinations: [String]
    public let swiftVersion: String?

    public init(id: String, name: String, path: String, activeScheme: String? = nil, activeTarget: String? = nil, destinations: [String] = [], swiftVersion: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.activeScheme = activeScheme
        self.activeTarget = activeTarget
        self.destinations = destinations
        self.swiftVersion = swiftVersion
    }
}

public struct ConnectProjectResponsePayload: Codable, Sendable {
    public let activeProject: ConnectProjectInfo?
    public let availableProjects: [ConnectProjectInfo]

    public init(activeProject: ConnectProjectInfo?, availableProjects: [ConnectProjectInfo]) {
        self.activeProject = activeProject
        self.availableProjects = availableProjects
    }
}

public struct ConnectGitStatusResponsePayload: Codable, Sendable {
    public let branch: String
    public let isClean: Bool
    public let ahead: Int
    public let behind: Int
    public let modifiedFiles: [String]
    public let stagedFiles: [String]
    public let untrackedFiles: [String]

    public init(branch: String, isClean: Bool, ahead: Int, behind: Int, modifiedFiles: [String], stagedFiles: [String], untrackedFiles: [String]) {
        self.branch = branch
        self.isClean = isClean
        self.ahead = ahead
        self.behind = behind
        self.modifiedFiles = modifiedFiles
        self.stagedFiles = stagedFiles
        self.untrackedFiles = untrackedFiles
    }
}

// Build & Test
public struct ConnectBuildRequestPayload: Codable, Sendable {
    public let projectID: String?
    public let scheme: String?
    public let configuration: String?
    public let destinationSDK: String?

    public init(projectID: String? = nil, scheme: String? = nil, configuration: String? = nil, destinationSDK: String? = nil) {
        self.projectID = projectID
        self.scheme = scheme
        self.configuration = configuration
        self.destinationSDK = destinationSDK
    }
}

public struct ConnectBuildProgressPayload: Codable, Sendable {
    public let phase: String
    public let completedSteps: Int
    public let totalSteps: Int
    public let message: String

    public init(phase: String, completedSteps: Int, totalSteps: Int, message: String) {
        self.phase = phase
        self.completedSteps = completedSteps
        self.totalSteps = totalSteps
        self.message = message
    }
}

public struct ConnectBuildDiagnosticPayload: Codable, Sendable {
    public let severity: String // error, warning, note
    public let message: String
    public let file: String?
    public let line: Int?
    public let column: Int?

    public init(severity: String, message: String, file: String? = nil, line: Int? = nil, column: Int? = nil) {
        self.severity = severity
        self.message = message
        self.file = file
        self.line = line
        self.column = column
    }
}

public struct ConnectBuildCompletedPayload: Codable, Sendable {
    public let success: Bool
    public let duration: Double
    public let errorCount: Int
    public let warningCount: Int

    public init(success: Bool, duration: Double, errorCount: Int, warningCount: Int) {
        self.success = success
        self.duration = duration
        self.errorCount = errorCount
        self.warningCount = warningCount
    }
}

// Log & Terminal & Assist
public struct ConnectLogEventPayload: Codable, Sendable {
    public let timestamp: Date
    public let level: String
    public let category: String
    public let message: String

    public init(timestamp: Date = Date(), level: String, category: String, message: String) {
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
    }
}

public struct ConnectTerminalExecuteRequestPayload: Codable, Sendable {
    public let command: String
    public let workingDirectory: String?

    public init(command: String, workingDirectory: String? = nil) {
        self.command = command
        self.workingDirectory = workingDirectory
    }
}

public struct ConnectTerminalOutputPayload: Codable, Sendable {
    public let output: String
    public let isError: Bool

    public init(output: String, isError: Bool = false) {
        self.output = output
        self.isError = isError
    }
}

public struct ConnectAssistQueryRequestPayload: Codable, Sendable {
    public let prompt: String
    public let contextFiles: [String]?

    public init(prompt: String, contextFiles: [String]? = nil) {
        self.prompt = prompt
        self.contextFiles = contextFiles
    }
}

public struct ConnectAssistResponsePayload: Codable, Sendable {
    public let answer: String
    public let suggestedActions: [String]?

    public init(answer: String, suggestedActions: [String]? = nil) {
        self.answer = answer
        self.suggestedActions = suggestedActions
    }
}

// Files
public struct ConnectFileItem: Codable, Sendable {
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let size: Int64?

    public init(path: String, name: String, isDirectory: Bool, size: Int64? = nil) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
    }
}

public struct ConnectFileListResponsePayload: Codable, Sendable {
    public let files: [ConnectFileItem]

    public init(files: [ConnectFileItem]) {
        self.files = files
    }
}
