import Foundation
import Observation
import os.log

public enum UnifiedLogSeverity: String, CaseIterable, Identifiable, Sendable {
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case system = "SYSTEM"
    case runtime = "RUNTIME"

    public var id: String { rawValue }
}

public struct UnifiedLogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp = Date()
    public let severity: UnifiedLogSeverity
    public let subsystem: String
    public let operation: String
    public let message: String
}

@Observable
@MainActor
public final class UnifiedLogger: Sendable {
    public static let shared = UnifiedLogger()

    private let systemLogger = Logger(subsystem: "com.swiftcode.app", category: "UnifiedLogger")

    public var logs: [UnifiedLogEntry] = []

    private init() {
        log("Unified Logger initialized.", severity: .system, subsystem: "Logging", operation: "Init")
    }

    public func log(_ message: String, severity: UnifiedLogSeverity = .info, subsystem: String = "App", operation: String = "General") {
        let entry = UnifiedLogEntry(
            severity: severity,
            subsystem: subsystem,
            operation: operation,
            message: message
        )
        logs.append(entry)

        if logs.count > 5000 {
            logs.removeFirst(1000)
        }

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

    public func clear() {
        logs.removeAll()
        log("Logs cleared.", severity: .system, subsystem: "Logging", operation: "Clear")
    }

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
