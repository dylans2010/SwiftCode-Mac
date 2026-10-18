import Foundation

public struct AssistForceUnwrapScanTool: AssistTool {
    public let id = "force_unwrap_scan"
    public let name = "Force Unwrap Scan"
    public let description = "Scans Swift sources for force unwraps (!), try!, and as! — crash-prone constructs worth reviewing."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Scans for force-unwrap constructs.",
            properties: [
                "limit": JSONSchema(type: "integer", description: "Maximum findings. Default 100, max 1000.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let limit = max(1, min(1000, (input["limit"] as? Int) ?? 100))
        let root = context.workspaceRoot
        let patterns: [(NSRegularExpression?, String)] = [
            (try? NSRegularExpression(pattern: #"(?<![=!])!(?!=)"#), "force unwrap (!)"),
            (try? NSRegularExpression(pattern: #"\btry!\b"#), "try!"),
            (try? NSRegularExpression(pattern: #"\bas! "#), "as!")
        ]
        var findings: [(String, String)] = []
        for url in AssistWorkspaceScan.swiftFiles(under: root) {
            guard let lines = AssistWorkspaceScan.readLines(url) else { continue }
            let rel = AssistWorkspacePaths.relative(url, workspaceRoot: root)
            for (i, line) in lines.enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("//") { continue }
                for (pattern, label) in patterns {
                    guard let p = pattern else { continue }
                    if p.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                        if label == "force unwrap (!)" && t.contains("@IBOutlet") { continue }
                        findings.append(("\(rel):\(i + 1)", label))
                        break
                    }
                }
                if findings.count >= limit { break }
            }
            if findings.count >= limit { break }
        }
        if findings.isEmpty {
            return .success("No force-unwrap constructs found.", data: ["count": "0"])
        }
        var lines = ["Force-unwrap constructs (\(findings.count)\(findings.count >= limit ? "+" : "")):"]
        lines += findings.map { "- \($0.0) [\($0.1)]" }
        return .success(lines.joined(separator: "\n"), data: ["count": "\(findings.count)"])
    }
}
