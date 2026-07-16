import Foundation

public struct AssistRuntimeDiagnosticsEngine: AssistTool {
    public let id = "runtime_diagnostics_engine"
    public let name = "Runtime Diagnostics Engine"
    public let description = "Analyzes runtime logs for crashes/anomalies and suggests concrete fixes."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let logPath = input["logPath"] as? String else { return .failure("Missing logPath") }
        let log = try context.fileSystem.readFile(at: logPath)
        let lines = log.components(separatedBy: .newlines)
        let crashes = lines.filter { $0.localizedCaseInsensitiveContains("fatal error") || $0.localizedCaseInsensitiveContains("crash") }
        let threads = lines.filter { $0.localizedCaseInsensitiveContains("thread") && $0.localizedCaseInsensitiveContains("queue") }

        var suggestions: [String] = []
        if !crashes.isEmpty { suggestions.append("Add guards around nil-sensitive code paths and inspect crashing stack frame symbols.") }
        if !threads.isEmpty { suggestions.append("Validate actor/queue confinement for shared mutable state to avoid race conditions.") }
        if suggestions.isEmpty { suggestions.append("No critical anomalies detected; enable verbose logging for deeper tracing.") }

        return .success(
            "Runtime diagnostics complete.",
            data: [
                "crash_count": "\(crashes.count)",
                "thread_anomaly_count": "\(threads.count)",
                "suggestions": suggestions.joined(separator: "\n"),
                "crashes": crashes.prefix(100).joined(separator: "\n")
            ]
        )
    }
}
