import Foundation

public enum DiagnosticSeverity: String, Codable, Sendable, Comparable, CaseIterable {
    case suggestion = "suggestion"
    case note = "note"
    case warning = "warning"
    case error = "error"

    private var priority: Int {
        switch self {
        case .suggestion: return 0
        case .note: return 1
        case .warning: return 2
        case .error: return 3
        }
    }

    public static func < (lhs: DiagnosticSeverity, rhs: DiagnosticSeverity) -> Bool {
        lhs.priority < rhs.priority
    }

    public var symbol: String {
        switch self {
        case .suggestion: return "💡"
        case .note: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }
}

public struct DiagnosticLocation: Codable, Sendable, Equatable {
    public let filePath: String
    public let line: Int?
    public let column: Int?
    public let endLine: Int?
    public let endColumn: Int?

    public init(
        filePath: String,
        line: Int? = nil,
        column: Int? = nil,
        endLine: Int? = nil,
        endColumn: Int? = nil
    ) {
        self.filePath = filePath
        self.line = line
        self.column = column
        self.endLine = endLine
        self.endColumn = endColumn
    }

    public var formattedDescription: String {
        var result = filePath
        if let line = line {
            result += ":\(line)"
            if let col = column {
                result += ":\(col)"
            }
        }
        return result
    }
}

public struct DiagnosticCode: Codable, Sendable, Hashable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    // Standard SDK diagnostic codes
    public static let manifestNotFound = DiagnosticCode("SC-M001")
    public static let manifestInvalidJSON = DiagnosticCode("SC-M002")
    public static let manifestMissingRequiredField = DiagnosticCode("SC-M003")
    public static let manifestInvalidVersion = DiagnosticCode("SC-M004")
    public static let manifestInvalidEntrypoint = DiagnosticCode("SC-M005")
    public static let manifestUnsupportedProtocol = DiagnosticCode("SC-M006")
    public static let manifestUnauthorizedCapability = DiagnosticCode("SC-M007")
    public static let manifestInvalidCapabilityReason = DiagnosticCode("SC-M008")

    public static let projectNotFound = DiagnosticCode("SC-P001")
    public static let projectMalformedStructure = DiagnosticCode("SC-P002")
    public static let projectMissingSource = DiagnosticCode("SC-P003")
    public static let projectInvalidIdentifier = DiagnosticCode("SC-P004")
    public static let projectMissingTarget = DiagnosticCode("SC-P005")

    public static let buildToolMissing = DiagnosticCode("SC-B001")
    public static let buildConfigurationInvalid = DiagnosticCode("SC-B002")
    public static let buildProcessFailed = DiagnosticCode("SC-B003")
    public static let buildCancelled = DiagnosticCode("SC-B004")
    public static let buildCompilerError = DiagnosticCode("SC-B005")
    public static let buildLinkerError = DiagnosticCode("SC-B006")

    public static let gitNotRepository = DiagnosticCode("SC-S001")
    public static let gitCommandFailed = DiagnosticCode("SC-S002")
    public static let gitUncommittedChanges = DiagnosticCode("SC-S003")
    public static let gitDetachedHead = DiagnosticCode("SC-S004")

    public static let workspaceTraversalDetected = DiagnosticCode("SC-W001")
    public static let workspacePermissionDenied = DiagnosticCode("SC-W002")
    public static let workspacePathNotFound = DiagnosticCode("SC-W003")

    public static let integrityChecksumMismatch = DiagnosticCode("SC-I001")
    public static let integrityMissingSignature = DiagnosticCode("SC-I002")
}

public struct Diagnostic: Codable, Sendable, Identifiable {
    public var id: String { "\(code.rawValue)-\(location?.formattedDescription ?? "global")-\(message)" }
    public let code: DiagnosticCode
    public let severity: DiagnosticSeverity
    public let message: String
    public let location: DiagnosticLocation?
    public let remediation: String?
    public let metadata: [String: String]
    public let timestamp: Date

    public init(
        code: DiagnosticCode,
        severity: DiagnosticSeverity,
        message: String,
        location: DiagnosticLocation? = nil,
        remediation: String? = nil,
        metadata: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.code = code
        self.severity = severity
        self.message = message
        self.location = location
        self.remediation = remediation
        self.metadata = metadata
        self.timestamp = timestamp
    }
}
