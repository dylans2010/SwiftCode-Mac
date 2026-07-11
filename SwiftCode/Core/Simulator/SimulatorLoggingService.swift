import Foundation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.app", category: "SimulatorLoggingService")

/// Structure representing a log entry.
public struct SimulatorLogEntry: Identifiable, Sendable, Codable, Hashable {
    public let id = UUID()
    public let timestamp: Date
    public let level: String
    public let message: String
}

/// Actor that aggregates command execution logs, boot activity, and console streams.
public actor SimulatorLoggingService: Sendable {
    public static let shared = SimulatorLoggingService()
    private init() {}

    private var logs: [SimulatorLogEntry] = []

    /// Appends a new message to the simulator logger.
    public func log(_ message: String, level: String = "INFO") {
        let entry = SimulatorLogEntry(timestamp: Date(), level: level, message: message)
        logs.append(entry)
        logger.info("[\(level, privacy: .public)] \(message, privacy: .public)")
    }

    /// Fetches all collected logs.
    public func getLogs() -> [SimulatorLogEntry] {
        return logs
    }

    /// Clears all logs.
    public func clear() {
        logs.removeAll()
    }

    /// Exports all logs to a unified text format.
    public func export() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return logs.map { "[\(formatter.string(from: $0.timestamp))] [\($0.level)] \($0.message)" }.joined(separator: "\n")
    }
}
