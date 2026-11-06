import Foundation

public struct AssistLintTool: AssistTool {
    public let id = "code_lint"
    public let name = "Lint Code"
    public let description = "Runs a linter on the specified file or directory."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Runs basic lint checks (line length, TODO/FIXME markers) on a file.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative file path to lint. Default: \".\".")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let path = input["path"] as? String ?? "."

        do {
            let content = try context.fileSystem.readFile(at: path)
            let lines = content.components(separatedBy: .newlines)
            var issues: [String] = []

            for (index, line) in lines.enumerated() {
                if line.count > 120 {
                    issues.append("Line \(index + 1) is too long (\(line.count) chars)")
                }
                if line.contains("TODO") || line.contains("FIXME") {
                    issues.append("Line \(index + 1) contains a marker: \(line.trimmingCharacters(in: .whitespaces))")
                }
            }

            if issues.isEmpty {
                return .success("No basic linting issues found in \(path)")
            } else {
                return .success("Basic linting found \(issues.count) issues in \(path)", data: ["issues": issues.joined(separator: "\n")])
            }
        } catch {
            return .failure("Failed to lint \(path): \(error.localizedDescription)")
        }
    }
}
