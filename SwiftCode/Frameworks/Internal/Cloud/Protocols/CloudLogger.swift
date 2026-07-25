import Foundation

public enum CloudLogLevel: String, Codable, Sendable {
    case info
    case warning
    case error
    case performance
}

public struct CloudLogEntry: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let subsystem: String
    public let level: CloudLogLevel
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), subsystem: String, level: CloudLogLevel, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.subsystem = subsystem
        self.level = level
        self.message = message
    }
}

public protocol CloudLogger: AnyObject, Sendable {
    func log(level: CloudLogLevel, message: String, subsystem: String)
    func fetchLogs() -> [CloudLogEntry]
    func clearLogs()
}
