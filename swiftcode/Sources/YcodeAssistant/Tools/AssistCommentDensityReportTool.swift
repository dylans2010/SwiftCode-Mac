import Foundation

public struct AssistCommentDensityReportTool: AssistTool {
    public let id = "comment_density_report"
    public let name = "Comment Density Report"
    public let description = "Reports comment-to-code ratios per Swift file, flagging the least-documented files."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Reports comment density per file.",
            properties: [
                "limit": JSONSchema(type: "integer", description: "Maximum files to report. Default 30.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let limit = max(1, min(500, (input["limit"] as? Int) ?? 30))
        let root = context.workspaceRoot
        var rows: [(String, Double, Int, Int)] = []
        for url in AssistWorkspaceScan.swiftFiles(under: root) {
            guard let lines = AssistWorkspaceScan.readLines(url) else { continue }
            var comment = 0, code = 0
            var inBlock = false
            for line in lines {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { continue }
                if inBlock {
                    comment += 1
                    if t.contains("*/") { inBlock = false }
                    continue
                }
                if t.hasPrefix("//") { comment += 1 }
                else if t.hasPrefix("/*") {
                    comment += 1
                    if !t.contains("*/") { inBlock = true }
                }
                else { code += 1 }
            }
            let total = comment + code
            guard total > 0 else { continue }
            rows.append((AssistWorkspacePaths.relative(url, workspaceRoot: root), Double(comment) / Double(total), comment, code))
        }
        rows.sort { $0.1 < $1.1 }
        var lines = ["Comment density (lowest first, \(rows.count) files):"]
        for (path, ratio, comment, code) in rows.prefix(limit) {
            lines.append(String(format: "- %.1f%% — %@ (%d comment / %d code lines)", ratio * 100, path, comment, code))
        }
        return .success(lines.joined(separator: "\n"), data: ["fileCount": "\(rows.count)"])
    }
}
