import Foundation

public struct BuildDiagnostic: Identifiable, Sendable, Codable {
    public let id: UUID
    public let severity: Severity
    public let filePath: String
    public let line: Int
    public let column: Int
    public let message: String

    public enum Severity: String, Sendable, Codable {
        case error
        case warning
        case note
    }

    public init(severity: Severity, filePath: String, line: Int, column: Int, message: String) {
        self.id = UUID()
        self.severity = severity
        self.filePath = filePath
        self.line = line
        self.column = column
        self.message = message
    }
}
