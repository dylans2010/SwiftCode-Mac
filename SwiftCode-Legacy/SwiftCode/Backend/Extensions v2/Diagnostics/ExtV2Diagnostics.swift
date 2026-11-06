import Foundation

// MARK: - Structured diagnostics

public enum ExtV2DiagnosticLevel: String, Codable, Sendable {
    case info, warning, error
}

public struct ExtV2DiagnosticEntry: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let extensionId: String?
    public let level: ExtV2DiagnosticLevel
    public let message: String

    public init(extensionId: String?, level: ExtV2DiagnosticLevel, message: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.extensionId = extensionId
        self.level = level
        self.message = message
    }
}

/// Append-only in-memory log plus a JSONL file, so a crash does not take
/// the explanation of the crash with it. Never logs secrets or file
/// contents — messages only.
public final class ExtV2DiagnosticsService: @unchecked Sendable {
    public static let shared = ExtV2DiagnosticsService()

    private let storage = ExtV2Storage()
    private let lock = NSLock()
    private var entries: [ExtV2DiagnosticEntry] = []

    public init() {}

    public func log(extensionId: String? = nil, level: ExtV2DiagnosticLevel, message: String) {
        let entry = ExtV2DiagnosticEntry(extensionId: extensionId, level: level, message: message)
        lock.lock()
        entries.append(entry)
        if entries.count > 2000 { entries.removeFirst(entries.count - 2000) }
        lock.unlock()
        if let data = try? JSONEncoder().encode(entry), let line = String(data: data, encoding: .utf8) {
            storage.appendDiagnosticsLine(line)
        }
        #if DEBUG
        print("[ExtV2][\(level.rawValue)] \(extensionId ?? "-"): \(message)")
        #endif
    }

    public func info(_ message: String, extensionId: String? = nil) { log(extensionId: extensionId, level: .info, message: message) }
    public func warning(_ message: String, extensionId: String? = nil) { log(extensionId: extensionId, level: .warning, message: message) }
    public func error(_ message: String, extensionId: String? = nil) { log(extensionId: extensionId, level: .error, message: message) }

    public func allEntries() -> [ExtV2DiagnosticEntry] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    public func entries(for extensionId: String) -> [ExtV2DiagnosticEntry] {
        allEntries().filter { $0.extensionId == extensionId }
    }

    public func clear() {
        lock.lock(); entries.removeAll(); lock.unlock()
    }

    public func exportReport() -> String {
        let formatter = ISO8601DateFormatter()
        return allEntries().map { entry in
            "[\(formatter.string(from: entry.timestamp))] [\(entry.level.rawValue)] \(entry.extensionId ?? "-"): \(entry.message)"
        }.joined(separator: "\n")
    }
}
