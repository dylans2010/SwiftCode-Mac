import Foundation

public struct AssistChangeImpactEstimateTool: AssistTool {
    public let id = "change_impact_estimate"
    public let name = "Change Impact Estimate"
    public let description = "Estimates the blast radius of changing a file: finds Swift files that reference its base symbol name."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Estimates change impact of a file.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of the file to change."),
                "limit": JSONSchema(type: "integer", description: "Maximum referencing files. Default 50.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let raw = (input["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .failure("Missing required parameter: path")
        }
        let limit = max(1, min(500, (input["limit"] as? Int) ?? 50))
        guard let url = AssistWorkspacePaths.resolve(raw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Refusing to access path outside the workspace: \(raw)")
        }
        let symbol = url.deletingPathExtension().lastPathComponent
        guard !symbol.isEmpty else { return .failure("Could not derive a symbol name from: \(raw)") }
        let pattern = try? NSRegularExpression(pattern: #"(?<![\w.])"# + NSRegularExpression.escapedPattern(for: symbol) + #"\b"#)
        var referencing: [String] = []
        for candidate in AssistWorkspaceScan.swiftFiles(under: context.workspaceRoot) {
            if candidate.standardized.path == url.standardized.path { continue }
            guard let lines = AssistWorkspaceScan.readLines(candidate) else { continue }
            let hit = lines.contains { line in
                pattern?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
            }
            if hit {
                referencing.append(AssistWorkspacePaths.relative(candidate, workspaceRoot: context.workspaceRoot))
                if referencing.count >= limit { break }
            }
        }
        let level: String
        switch referencing.count {
        case 0: level = "LOW"
        case 1...10: level = "MEDIUM"
        default: level = "HIGH"
        }
        var lines = ["Change impact estimate for \(raw) (symbol '\(symbol)'):", "- Blast radius: \(level) — referenced by \(referencing.count) file(s)"]
        lines += referencing.sorted().map { "- \($0)" }
        return .success(lines.joined(separator: "\n"), data: [
            "symbol": symbol, "referencingFileCount": "\(referencing.count)", "blastRadius": level
        ])
    }
}
