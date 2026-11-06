import Foundation

public struct AssistSessionProgressReportTool: AssistTool {
    public let id = "session_progress_report"
    public let name = "Session Progress Report"
    public let description = "Summarizes the active agent session: engineering phases by status, failures, and the last agent-notes save time."

    public init() {}

    public var capability: ToolCapability { .planning }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(type: "object", description: "Reports session progress.", properties: [:], required: [])
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let phases = AgentPhaseCoordinator.shared.phases
        if phases.isEmpty {
            return .success("No engineering phases are registered for this session.", data: ["phaseCount": "0"])
        }
        let completed = phases.filter { $0.status == .completed }
        let inProgress = phases.filter { $0.status == .inProgress }
        let failed = phases.filter { $0.status == .failed }
        let pending = phases.filter { $0.status == .pending }
        let skipped = phases.filter { $0.status == .skipped }
        var lines = ["Session progress: \(completed.count) of \(phases.count) phases completed."]
        if !inProgress.isEmpty {
            lines.append("In progress (\(inProgress.count)):")
            lines += inProgress.map { "- \($0.name)" }
        }
        if !failed.isEmpty {
            lines.append("Failed (\(failed.count)):")
            for p in failed {
                lines.append("- \(p.name): \(p.failures.prefix(3).joined(separator: "; ").prefix(200))")
            }
        }
        if !pending.isEmpty { lines.append("Pending: \(pending.map { $0.name }.joined(separator: ", ").prefix(200))") }
        if !skipped.isEmpty { lines.append("Skipped: \(skipped.count)") }
        if let ts = AgentNotesManager.shared.lastSavedTimestamp {
            lines.append("Agent notes last saved: \(AssistWorkspacePaths.iso8601(ts))")
        } else {
            lines.append("Agent notes: never saved this session.")
        }
        return .success(lines.joined(separator: "\n"), data: [
            "phaseCount": "\(phases.count)", "completed": "\(completed.count)",
            "inProgress": "\(inProgress.count)", "failed": "\(failed.count)",
            "pending": "\(pending.count)"
        ])
    }
}
