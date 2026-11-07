import Foundation

public struct AssistDeprecationUsageScanTool: AssistTool {
    public let id = "deprecation_usage_scan"
    public let name = "Deprecation Usage Scan"
    public let description = "Finds declarations marked @available(*, deprecated) in workspace Swift sources and reports where those deprecated symbols are used."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Scans for deprecated declarations and their usages.",
            properties: [
                "limit": JSONSchema(type: "integer", description: "Maximum usage sites. Default 100, max 500.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let limit = max(1, min(500, (input["limit"] as? Int) ?? 100))
        let root = context.workspaceRoot
        let deprecatedNames = NSMutableSet()
        var declarations: [String] = []
        let declPattern = try? NSRegularExpression(pattern: #"@available\([^)]*deprecated[^)]*\)"#)
        let namePattern = try? NSRegularExpression(pattern: #"(?:func|class|struct|enum|var|let|typealias)\s+([A-Za-z_][\w]*)"#)
        var files: [(URL, [String])] = []
        for url in AssistWorkspaceScan.swiftFiles(under: root) {
            guard let lines = AssistWorkspaceScan.readLines(url) else { continue }
            files.append((url, lines))
            for (i, line) in lines.enumerated() {
                guard let dp = declPattern, dp.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil else { continue }
                let next = lines.dropFirst(i + 1).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
                if let m = namePattern?.firstMatch(in: next, range: NSRange(next.startIndex..., in: next)),
                   let r = Range(m.range(at: 1), in: next) {
                    let name = String(next[r])
                    deprecatedNames.add(name)
                    declarations.append("\(name) — \(AssistWorkspacePaths.relative(url, workspaceRoot: root)):\(i + 1)")
                }
            }
        }
        if declarations.isEmpty {
            return .success("No @available(*, deprecated) declarations found in workspace Swift sources.", data: ["declarationCount": "0"])
        }
        var usages: [String] = []
        for (url, lines) in files {
            let rel = AssistWorkspacePaths.relative(url, workspaceRoot: root)
            for (i, line) in lines.enumerated() {
                for name in deprecatedNames {
                    guard let n = name as? String else { continue }
                    let pattern = try? NSRegularExpression(pattern: #"(?<![\w.])"# + NSRegularExpression.escapedPattern(for: n) + #"\b"#)
                    if pattern?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil,
                       !(declPattern?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil) {
                        usages.append("\(rel):\(i + 1): uses deprecated '\(n)'")
                        if usages.count >= limit { break }
                    }
                }
                if usages.count >= limit { break }
            }
            if usages.count >= limit { break }
        }
        var lines = ["Deprecated declarations (\(declarations.count)):"]
        lines += declarations.sorted().map { "- \($0)" }
        lines.append("Usage sites (\(usages.count)\(usages.count >= limit ? "+" : "")):")
        lines += usages.map { "- \($0)" }
        return .success(lines.joined(separator: "\n"), data: [
            "declarationCount": "\(declarations.count)", "usageCount": "\(usages.count)"
        ])
    }
}
