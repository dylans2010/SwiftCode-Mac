import Foundation

public struct AssistStringLiteralAuditTool: AssistTool {
    public let id = "string_literal_audit"
    public let name = "String Literal Audit"
    public let description = "Finds hardcoded user-facing string literals that are not routed through localization (NSLocalizedString / String(localized:))."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Audits hardcoded string literals.",
            properties: [
                "limit": JSONSchema(type: "integer", description: "Maximum findings. Default 100, max 1000.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let limit = max(1, min(1000, (input["limit"] as? Int) ?? 100))
        let root = context.workspaceRoot
        let literalPattern = try? NSRegularExpression(pattern: #""([^"\\]|\\.){3,}""#)
        var findings: [String] = []
        for url in AssistWorkspaceScan.swiftFiles(under: root) {
            guard let lines = AssistWorkspaceScan.readLines(url) else { continue }
            let rel = AssistWorkspacePaths.relative(url, workspaceRoot: root)
            for (i, line) in lines.enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("//") { continue }
                let lower = t.lowercased()
                if lower.contains("localizedstring") || lower.contains("string(localized") || lower.contains("localized:") { continue }
                if lower.contains("http") || lower.contains("bundle id") || lower.contains("identifier") { continue }
                guard let m = literalPattern?.matches(in: line, range: NSRange(line.startIndex..., in: line)), !m.isEmpty else { continue }
                let uiHints = ["text(", "title", "message", "placeholder", "label", "button(", "alert(", "navigationtitle"]
                if uiHints.contains(where: { lower.contains($0) }), let first = m.first, let r = Range(first.range, in: line) {
                    findings.append("\(rel):\(i + 1): \(String(line[r]).prefix(80))")
                    if findings.count >= limit { break }
                }
            }
            if findings.count >= limit { break }
        }
        if findings.isEmpty {
            return .success("No hardcoded user-facing string literals detected.", data: ["count": "0"])
        }
        var lines = ["Possibly unlocalized user-facing strings (\(findings.count)\(findings.count >= limit ? "+" : "")):"]
        lines += findings.map { "- \($0)" }
        return .success(lines.joined(separator: "\n"), data: ["count": "\(findings.count)"])
    }
}
