import Foundation

public struct AssistColorUsageAuditTool: AssistTool {
    public let id = "color_usage_audit"
    public let name = "Color Usage Audit"
    public let description = "Finds hardcoded colors in SwiftUI/UIKit code (Color(red:), UIColor literals, hex strings) that should live in the asset catalog."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Audits hardcoded colors.",
            properties: [
                "limit": JSONSchema(type: "integer", description: "Maximum findings. Default 100, max 500.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let limit = max(1, min(500, (input["limit"] as? Int) ?? 100))
        let root = context.workspaceRoot
        let patterns: [(NSRegularExpression?, String)] = [
            (try? NSRegularExpression(pattern: #"Color\s*\(\s*red\s*:"#), "Color(red:...)"),
            (try? NSRegularExpression(pattern: #"UIColor\s*\(\s*red\s*:"#), "UIColor(red:...)"),
            (try? NSRegularExpression(pattern: #"NSColor\s*\(\s*red\s*:"#), "NSColor(red:...)"),
            (try? NSRegularExpression(pattern: ##""#[0-9A-Fa-f]{6}"|"#[0-9a-f]{3}"##), "hex literal"),
            (try? NSRegularExpression(pattern: #"Color\s*\(\s*hex\s*:"#), "Color(hex:)"),
            (try? NSRegularExpression(pattern: #"UIColor\s*\(\s*hex\s*:"#), "UIColor(hex:)")
        ]
        var findings: [(String, String)] = []
        for url in AssistWorkspaceScan.swiftFiles(under: root) {
            guard let lines = AssistWorkspaceScan.readLines(url) else { continue }
            let rel = AssistWorkspacePaths.relative(url, workspaceRoot: root)
            for (i, line) in lines.enumerated() {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                for (pattern, label) in patterns {
                    guard let p = pattern else { continue }
                    if p.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                        findings.append(("\(rel):\(i + 1)", label))
                        break
                    }
                }
                if findings.count >= limit { break }
            }
            if findings.count >= limit { break }
        }
        if findings.isEmpty {
            return .success("No hardcoded colors found — colors appear to use named assets.", data: ["count": "0"])
        }
        var lines = ["Hardcoded colors (\(findings.count)\(findings.count >= limit ? "+" : "")) — consider asset-catalog named colors:"]
        lines += findings.map { "- \($0.0) [\($0.1)]" }
        return .success(lines.joined(separator: "\n"), data: ["count": "\(findings.count)"])
    }
}
