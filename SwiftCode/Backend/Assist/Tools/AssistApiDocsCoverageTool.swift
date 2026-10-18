import Foundation

public struct AssistApiDocsCoverageTool: AssistTool {
    public let id = "api_docs_coverage"
    public let name = "API Docs Coverage"
    public let description = "Measures the share of public/open Swift declarations that carry documentation comments."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Measures doc-comment coverage of public API.",
            properties: [
                "limit": JSONSchema(type: "integer", description: "Maximum undocumented symbols to list. Default 50.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let limit = max(1, min(500, (input["limit"] as? Int) ?? 50))
        let root = context.workspaceRoot
        let declPattern = try? NSRegularExpression(pattern: #"^\s*(public|open)\s+(?:final\s+|static\s+)*(class|struct|enum|protocol|func|var|let|typealias|init)\b"#)
        var documented = 0
        var undocumented: [String] = []
        var total = 0
        for url in AssistWorkspaceScan.swiftFiles(under: root) {
            guard let lines = AssistWorkspaceScan.readLines(url) else { continue }
            let rel = AssistWorkspacePaths.relative(url, workspaceRoot: root)
            for (i, line) in lines.enumerated() {
                guard let p = declPattern, p.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil else { continue }
                total += 1
                // Look back up to 3 lines for /// or /**.
                let back = max(0, i - 3)
                let hasDoc = lines[back..<i].contains { l in
                    let t = l.trimmingCharacters(in: .whitespaces)
                    return t.hasPrefix("///") || t.hasPrefix("/**")
                }
                if hasDoc { documented += 1 }
                else if undocumented.count < limit {
                    undocumented.append("\(rel):\(i + 1): \(line.trimmingCharacters(in: .whitespaces).prefix(90))")
                }
            }
        }
        let pct = total == 0 ? 0.0 : Double(documented) / Double(total) * 100
        var lines = [String(format: "API docs coverage: %.1f%% (%d of %d public declarations documented)", pct, documented, total)]
        if !undocumented.isEmpty {
            lines.append("Undocumented (showing \(undocumented.count)):")
            lines += undocumented.map { "- \($0)" }
        }
        return .success(lines.joined(separator: "\n"), data: [
            "total": "\(total)", "documented": "\(documented)",
            "coverage": String(format: "%.1f", pct)
        ])
    }
}
