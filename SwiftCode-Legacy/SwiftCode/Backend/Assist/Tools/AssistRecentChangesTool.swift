import Foundation

public struct AssistRecentChangesTool: AssistTool {
    public let id = "recent_changes"
    public let name = "Recent Changes"
    public let description = "Lists workspace files modified within the last N hours, newest first. Catches local edits regardless of git state."

    public init() {}

    public var capability: ToolCapability { .repositoryDiscovery }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Lists files modified within a recent time window.",
            properties: [
                "hours": JSONSchema(type: "integer", description: "Look-back window in hours. Default 24, max 720."),
                "limit": JSONSchema(type: "integer", description: "Maximum files to return. Default 50, max 500.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        let hours = max(1, min(720, (input["hours"] as? Int) ?? 24))
        let limit = max(1, min(500, (input["limit"] as? Int) ?? 50))
        let cutoff = Date().addingTimeInterval(TimeInterval(-hours * 3600))
        var changed: [(String, Date)] = []
        for url in AssistWorkspaceScan.files(under: root) {
            if let date = AssistWorkspaceScan.modificationDate(of: url), date >= cutoff {
                changed.append((AssistWorkspacePaths.relative(url, workspaceRoot: root), date))
            }
        }
        changed.sort { $0.1 > $1.1 }
        if changed.isEmpty {
            return .success("No files modified in the last \(hours)h.", data: ["count": "0"])
        }
        var lines = ["Files modified in the last \(hours)h (\(changed.count) total):"]
        for (path, date) in changed.prefix(limit) {
            lines.append("- \(path) — \(AssistWorkspacePaths.iso8601(date))")
        }
        if changed.count > limit {
            lines.append("… [truncated: showing \(limit) of \(changed.count)]")
        }
        return .success(lines.joined(separator: "\n"), data: ["count": "\(changed.count)", "hours": "\(hours)"])
    }
}
