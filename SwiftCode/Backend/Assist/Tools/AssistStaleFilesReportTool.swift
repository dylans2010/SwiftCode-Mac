import Foundation

public struct AssistStaleFilesReportTool: AssistTool {
    public let id = "stale_files_report"
    public let name = "Stale Files Report"
    public let description = "Reports source files not modified in a long time, surfacing potentially abandoned or legacy code."

    public init() {}

    public var capability: ToolCapability { .repositoryDiscovery }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Reports stale source files.",
            properties: [
                "days": JSONSchema(type: "integer", description: "Staleness threshold in days. Default 180."),
                "limit": JSONSchema(type: "integer", description: "Maximum files to return. Default 50, max 500.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        let days = max(1, (input["days"] as? Int) ?? 180)
        let limit = max(1, min(500, (input["limit"] as? Int) ?? 50))
        let cutoff = Date().addingTimeInterval(TimeInterval(-days * 86400))
        let exts: Set<String> = ["swift", "m", "mm", "h", "c", "cpp", "hpp", "ts", "js", "py", "rs"]
        var stale: [(String, Date, Int64)] = []
        for url in AssistWorkspaceScan.files(under: root, extensions: exts) {
            if let date = AssistWorkspaceScan.modificationDate(of: url), date < cutoff {
                stale.append((AssistWorkspacePaths.relative(url, workspaceRoot: root), date, AssistWorkspaceScan.fileSize(of: url)))
            }
        }
        stale.sort { $0.1 < $1.1 }
        if stale.isEmpty {
            return .success("No source files older than \(days) days.", data: ["count": "0"])
        }
        var lines = ["Stale source files (not modified in \(days)+ days, \(stale.count) total):"]
        for (path, date, size) in stale.prefix(limit) {
            lines.append("- \(path) — modified \(AssistWorkspacePaths.iso8601(date)), \(size) bytes")
        }
        return .success(lines.joined(separator: "\n"), data: ["count": "\(stale.count)", "days": "\(days)"])
    }
}
