import Foundation

@MainActor
public final class AssistLogger: ObservableObject, AssistLoggerProtocol {
    @Published public var logs: [AssistLogEntry] = []

    public init() {}

    public func info(_ message: String, toolId: String? = nil) async {
        log(message, level: .info, toolId: toolId)
    }

    public func warning(_ message: String, toolId: String? = nil) async {
        log(message, level: .warning, toolId: toolId)
    }

    public func error(_ message: String, toolId: String? = nil) async {
        log(message, level: .error, toolId: toolId)
    }

    public func debug(_ message: String, toolId: String? = nil) async {
        log(message, level: .debug, toolId: toolId)
    }

    private func log(_ message: String, level: AssistLogLevel, toolId: String?) {
        let entry = AssistLogEntry(message: message, level: level, toolId: toolId)
        logs.append(entry)
        print("[Assist][\(level.rawValue)]\(toolId.map { " [\($0)]" } ?? "") \(message)")
    }

    public func clear() {
        logs.removeAll()
    }
}

extension AssistLoggerProtocol {
    public func info(_ message: String) async { await info(message, toolId: nil) }
    public func warning(_ message: String) async { await warning(message, toolId: nil) }
    public func error(_ message: String) async { await error(message, toolId: nil) }
    public func debug(_ message: String) async { await debug(message, toolId: nil) }
}

public struct AssistLogEntry: Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let message: String
    public let level: AssistLogLevel
    public let toolId: String?

    public init(message: String, level: AssistLogLevel, toolId: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.message = message
        self.level = level
        self.toolId = toolId
    }
}

public enum AssistLogLevel: String, Codable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
    case debug = "DEBUG"
}
