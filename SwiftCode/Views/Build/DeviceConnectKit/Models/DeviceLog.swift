import Foundation

public struct DeviceLog: Identifiable, Codable, Sendable, Hashable {
    public enum LogType: String, Codable, Sendable {
        case build
        case runtime
        case system
        case diagnostics
    }

    public enum Severity: String, Codable, Sendable {
        case info
        case warning
        case error
        case debug
    }

    public let id: UUID
    public let timestamp: Date
    public let type: LogType
    public let severity: Severity
    public let message: String
    public let subsystem: String
    public let category: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: LogType,
        severity: Severity = .info,
        message: String,
        subsystem: String = "com.swiftcode.deviceconnect",
        category: String = "General"
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.severity = severity
        self.message = message
        self.subsystem = subsystem
        self.category = category
    }
}
