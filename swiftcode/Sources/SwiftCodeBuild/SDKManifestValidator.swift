// Ported from Legacy `SwiftCode/SDK/Host/ExtensionRegistry/SDKManifestValidator.swift` (Audit E §5 partial entry; H-E5).
// Types ported here: SDKManifestDiagnostic.

import Foundation

public struct SDKManifestDiagnostic: Identifiable, Equatable, Hashable, Sendable {
    public enum Severity: String, Codable, Sendable {
        case error
        case warning
        case info
    }

    public let id: String
    public let severity: Severity
    public let field: String
    public let message: String
    public let suggestion: String
    public let line: Int?

    public init(
        id: String? = nil,
        severity: Severity,
        field: String,
        message: String,
        suggestion: String,
        line: Int? = nil
    ) {
        self.id = id ?? "\(severity.rawValue):\(field):\(message)"
        self.severity = severity
        self.field = field
        self.message = message
        self.suggestion = suggestion
        self.line = line
    }
}
