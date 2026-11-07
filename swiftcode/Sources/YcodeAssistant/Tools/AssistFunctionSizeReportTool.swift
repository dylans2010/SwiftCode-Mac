import Foundation

public struct AssistFunctionSizeReportTool: AssistTool {
    public let id = "function_size_report"
    public let name = "Function Size Report"
    public let description = "Finds the longest functions by line count, highlighting decomposition candidates."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Reports longest functions.",
            properties: [
                "threshold": JSONSchema(type: "integer", description: "Only report functions at or above this many lines. Default 60."),
                "limit": JSONSchema(type: "integer", description: "Maximum functions to report. Default 30.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let threshold = max(5, (input["threshold"] as? Int) ?? 60)
        let limit = max(1, min(300, (input["limit"] as? Int) ?? 30))
        let root = context.workspaceRoot
        var rows: [(String, String, Int)] = []
        for url in AssistWorkspaceScan.swiftFiles(under: root) {
            guard let lines = AssistWorkspaceScan.readLines(url) else { continue }
            let rel = AssistWorkspacePaths.relative(url, workspaceRoot: root)
            var i = 0
            while i < lines.count {
                guard let name = AssistWorkspaceScan.declaredFuncName(lines[i]) else { i += 1; continue }
                var depth = 0
                var started = false
                var j = i
                while j < lines.count {
                    let opens = lines[j].filter { $0 == "{" }.count
                    let closes = lines[j].filter { $0 == "}" }.count
                    if opens > 0 { started = true }
                    depth += opens - closes
                    if started && depth <= 0 { break }
                    j += 1
                }
                let length = j - i + 1
                if started && length >= threshold {
                    rows.append((name, "\(rel):\(i + 1)", length))
                }
                i = max(i + 1, j)
            }
        }
        rows.sort { $0.2 > $1.2 }
        if rows.isEmpty {
            return .success("No functions with \(threshold)+ lines found.", data: ["count": "0"])
        }
        var lines = ["Longest functions (≥\(threshold) lines, \(rows.count) total):"]
        lines += rows.prefix(limit).map { "- \($0.0) — \($0.1) (\($0.2) lines)" }
        return .success(lines.joined(separator: "\n"), data: ["count": "\(rows.count)"])
    }
}
