import Foundation
import Observation
import os.log

/// Unified severity levels for logs across all systems
public enum UnifiedLogSeverity: String, CaseIterable, Identifiable, Sendable {
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case system = "SYSTEM"
    case runtime = "RUNTIME"

    public var id: String { rawValue }
}

/// Strongly typed model representing a single log entry in the unified log framework
public struct UnifiedLogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp = Date()
    public let severity: UnifiedLogSeverity
    public let subsystem: String
    public let operation: String
    public let message: String
}

/// Global unified logging manager, supporting standard, formatted real-time logs across Preview, Build, and Simulator
@Observable
@MainActor
public final class UnifiedLogger: Sendable {
    public static let shared = UnifiedLogger()

    private let systemLogger = Logger(subsystem: "com.swiftcode.app", category: "UnifiedLogger")

    public var logs: [UnifiedLogEntry] = []

    private init() {
        // Log initialization
        log("Unified Logger initialized.", severity: .system, subsystem: "Logging", operation: "Init")
    }

    /// Appends a new message to the global unified logs
    public func log(_ message: String, severity: UnifiedLogSeverity = .info, subsystem: String = "App", operation: String = "General") {
        let entry = UnifiedLogEntry(
            severity: severity,
            subsystem: subsystem,
            operation: operation,
            message: message
        )
        logs.append(entry)

        // Ensure we don't leak memory indefinitely with infinite logs
        if logs.count > 5000 {
            logs.removeFirst(1000)
        }

        // Mirror to the actual macOS console logger
        switch severity {
        case .info:
            systemLogger.info("[\(subsystem)] [\(operation)] \(message)")
        case .warning:
            systemLogger.warning("[\(subsystem)] [\(operation)] \(message)")
        case .error:
            systemLogger.error("[\(subsystem)] [\(operation)] \(message)")
        case .system, .runtime:
            systemLogger.log("[\(subsystem)] [\(operation)] \(message)")
        }
    }

    /// Clears all existing logs in the system
    public func clear() {
        logs.removeAll()
        log("Logs cleared.", severity: .system, subsystem: "Logging", operation: "Clear")
    }

    /// Exposes all current logs filtered by search query, severity, and subsystem
    public func filteredLogs(query: String = "", severity: UnifiedLogSeverity? = nil, subsystem: String? = nil) -> [UnifiedLogEntry] {
        var result = logs

        if let severity = severity {
            result = result.filter { $0.severity == severity }
        }

        if let subsystem = subsystem, !subsystem.isEmpty {
            result = result.filter { $0.subsystem.lowercased() == subsystem.lowercased() }
        }

        if !query.isEmpty {
            let q = query.lowercased()
            result = result.filter {
                $0.message.lowercased().contains(q) ||
                $0.operation.lowercased().contains(q) ||
                $0.subsystem.lowercased().contains(q)
            }
        }

        return result
    }

    /// Returns a structured, formatted string containing all current logs
    public func formatLogsForExport(_ entries: [UnifiedLogEntry]? = nil) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        let targetEntries = entries ?? logs
        return targetEntries.map { entry in
            let dateStr = formatter.string(from: entry.timestamp)
            return "[\(dateStr)] [\(entry.severity.rawValue)] [\(entry.subsystem)] [\(entry.operation)] \(entry.message)"
        }.joined(separator: "\n")
    }
}
