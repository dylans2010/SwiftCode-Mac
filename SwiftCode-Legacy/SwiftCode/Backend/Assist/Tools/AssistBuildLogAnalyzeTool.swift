import Foundation

public struct AssistBuildLogAnalyzeTool: AssistTool {
    public let id = "build_log_analyze"
    public let name = "Build Log Analyze"
    public let description = "Parses an xcodebuild/swift-build log file: extracts errors, warnings, build result, and timing summary."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Analyzes a build log file.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the build log file.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let raw = (input["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .failure("Missing required parameter: path")
        }
        guard let url = AssistWorkspacePaths.resolve(raw, workspaceRoot: context.workspaceRoot),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return .failure("Cannot read build log at: \(raw)")
        }
        let lines = text.components(separatedBy: .newlines)
        var errors: [String] = []
        var warnings: [String] = []
        var result = "unknown"
        for line in lines {
            if line.contains("** BUILD FAILED **") { result = "failed" }
            if line.contains("** BUILD SUCCEEDED **") { result = "succeeded" }
            if line.contains(": error:") { errors.append(String(line.trimmingCharacters(in: .whitespaces).prefix(300))) }
            else if line.contains(": warning:") { warnings.append(String(line.trimmingCharacters(in: .whitespaces).prefix(300))) }
        }
        errors = Array(NSOrderedSet(array: errors)).compactMap { $0 as? String }
        warnings = Array(NSOrderedSet(array: warnings)).compactMap { $0 as? String }
        var out = ["Build log analysis for \(raw):", "- Result: \(result)", "- Errors: \(errors.count)", "- Warnings: \(warnings.count)"]
        for e in errors.prefix(20) { out.append("  ERROR: \(e)") }
        if errors.count > 20 { out.append("  … [truncated: showing 20 of \(errors.count)]") }
        for w in warnings.prefix(10) { out.append("  WARNING: \(w)") }
        if warnings.count > 10 { out.append("  … [truncated: showing 10 of \(warnings.count)]") }
        return .success(out.joined(separator: "\n"), data: [
            "result": result, "errorCount": "\(errors.count)", "warningCount": "\(warnings.count)"
        ])
    }
}
