import Foundation
import Observation

public struct PreviewDiagnosticsRecord: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp = Date()
    public let category: String // "compile", "render", "cache", "error"
    public let message: String
}

@Observable
@MainActor
public final class PreviewDiagnostics {
    public static let shared = PreviewDiagnostics()

    public var logs: [PreviewDiagnosticsRecord] = []

    private init() {}

    public func addLog(category: String, message: String) {
        let record = PreviewDiagnosticsRecord(category: category, message: message)
        logs.append(record)
    }

    public func clearLogs() {
        logs.removeAll()
    }
}
