import Foundation

public struct SDKBuildRequest: Codable, Sendable {
    public let target: String
    public let configuration: String?
    public let destination: String?

    public init(target: String, configuration: String? = nil, destination: String? = nil) {
        self.target = target
        self.configuration = configuration
        self.destination = destination
    }
}

public enum SDKBuildOutputKind: String, Codable, Sendable {
    case stdout
    case stderr
    case status
}

public struct SDKBuildOutputEvent: Codable, Sendable {
    public let kind: SDKBuildOutputKind
    public let text: String
    public let timestamp: Date

    public init(kind: SDKBuildOutputKind, text: String, timestamp: Date = Date()) {
        self.kind = kind
        self.text = text
        self.timestamp = timestamp
    }
}

public struct SDKBuildDiagnostic: Codable, Sendable, Equatable {
    public let file: String?
    public let line: Int?
    public let message: String

    public init(file: String? = nil, line: Int? = nil, message: String) {
        self.file = file
        self.line = line
        self.message = message
    }
}

public enum SDKBuildStatus: String, Codable, Sendable {
    case running
    case succeeded
    case failed
    case cancelled
    case timedOut
}

public struct SDKBuildResult: Codable, Sendable {
    public let status: SDKBuildStatus
    public let exitCode: Int?
    public let durationSeconds: Double
    public let errorCount: Int
    public let warningCount: Int
    public let diagnostics: [SDKBuildDiagnostic]
    public let correlationId: String

    public init(
        status: SDKBuildStatus,
        exitCode: Int? = nil,
        durationSeconds: Double,
        errorCount: Int = 0,
        warningCount: Int = 0,
        diagnostics: [SDKBuildDiagnostic] = [],
        correlationId: String = SDKError.newCorrelationId()
    ) {
        self.status = status
        self.exitCode = exitCode
        self.durationSeconds = durationSeconds
        self.errorCount = errorCount
        self.warningCount = warningCount
        self.diagnostics = diagnostics
        self.correlationId = correlationId
    }
}
