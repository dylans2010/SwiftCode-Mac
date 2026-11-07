import Foundation

public struct AssistCrashLogParseTool: AssistTool {
    public let id = "crash_log_parse"
    public let name = "Crash Log Parse"
    public let description = "Parses .crash/.ips crash logs: exception type, termination reason, faulting thread, and top blamed frames."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Parses a crash log.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the .crash or .ips file.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let raw = (input["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .failure("Missing required parameter: path")
        }
        guard let url = AssistWorkspacePaths.resolve(raw, workspaceRoot: context.workspaceRoot),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return .failure("Cannot read crash log at: \(raw)")
        }
        var exception = "", terminationReason = "", crashedThread = ""
        var frames: [String] = []
        var inCrashedThread = false
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("Exception Type:") { exception = t }
            else if t.hasPrefix("Termination Reason:") { terminationReason = t }
            else if t.hasPrefix("Triggered by Thread:") || t.hasPrefix("Crashed Thread:") {
                crashedThread = t
                inCrashedThread = true
            } else if inCrashedThread {
                if t.isEmpty || (t.hasPrefix("Thread ") && !t.contains("Crashed")) { inCrashedThread = false }
                else if t.range(of: #"^\d+\s+\S+"#, options: .regularExpression) != nil {
                    frames.append(String(t.prefix(160)))
                    if frames.count >= 12 { inCrashedThread = false }
                }
            }
        }
        if exception.isEmpty, let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            exception = "Exception Type: \((json["exception"] as? [String: Any])?["type"] as? String ?? "unknown")"
            terminationReason = "Termination Reason: \((json["termination"] as? [String: Any])?["reason"] as? String ?? "unknown")"
        }
        if exception.isEmpty && terminationReason.isEmpty && frames.isEmpty {
            return .failure("No crash metadata recognized in \(raw). Expected .crash or .ips format.")
        }
        var lines = ["Crash log summary for \(raw):"]
        if !exception.isEmpty { lines.append("- \(exception)") }
        if !terminationReason.isEmpty { lines.append("- \(terminationReason)") }
        if !crashedThread.isEmpty { lines.append("- \(crashedThread)") }
        if !frames.isEmpty {
            lines.append("Top blamed frames:")
            lines += frames.map { "  \($0)" }
        }
        return .success(lines.joined(separator: "\n"), data: [
            "hasException": exception.isEmpty ? "false" : "true",
            "frameCount": "\(frames.count)"
        ])
    }
}
