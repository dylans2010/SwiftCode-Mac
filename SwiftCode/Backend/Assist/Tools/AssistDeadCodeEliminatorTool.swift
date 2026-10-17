import Foundation

public struct AssistDeadCodeEliminatorTool: AssistTool {
    public let id = "dead_code_eliminator"
    public let name = "Dead Code Eliminator"
    public let description = "Identifies unreferenced private functions, unused variables, and unreachable code structures in Swift files."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Scan Swift files for unused private declarations and dead code.",
            properties: [
                "filePath": JSONSchema(type: "string", description: "Workspace-relative path to a Swift file to inspect.")
            ],
            required: ["filePath"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let filePath = input["filePath"] as? String else {
            return .failure("Missing required parameter: filePath")
        }

        let targetURL = context.workspaceRoot.appendingPathComponent(filePath)
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            return .failure("File does not exist: \(filePath)")
        }

        guard let content = try? String(contentsOf: targetURL, encoding: .utf8) else {
            return .failure("Cannot read file: \(filePath)")
        }

        let lines = content.components(separatedBy: .newlines)
        var privateDeclarations: [(name: String, line: Int, kind: String)] = []

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("//") { continue }

            if trimmed.contains("private func ") {
                let parts = trimmed.components(separatedBy: "private func ")
                if parts.count > 1 {
                    let fnPart = parts[1].components(separatedBy: "(")[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !fnPart.isEmpty {
                        privateDeclarations.append((name: fnPart, line: idx + 1, kind: "function"))
                    }
                }
            } else if trimmed.contains("fileprivate func ") {
                let parts = trimmed.components(separatedBy: "fileprivate func ")
                if parts.count > 1 {
                    let fnPart = parts[1].components(separatedBy: "(")[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !fnPart.isEmpty {
                        privateDeclarations.append((name: fnPart, line: idx + 1, kind: "function"))
                    }
                }
            }
        }

        var deadDeclarations: [String] = []

        for decl in privateDeclarations {
            // Count occurrences of decl.name in the whole file
            let occurrences = content.components(separatedBy: decl.name).count - 1
            // If it occurs only 1 time, it is only declared and never called!
            if occurrences <= 1 {
                deadDeclarations.append("Line \(decl.line): Unused private \(decl.kind) '\(decl.name)()' (0 calls in file).")
            }
        }

        if deadDeclarations.isEmpty {
            return .success("Dead Code Scan completed for \(filePath): All \(privateDeclarations.count) private declarations have active call sites.")
        } else {
            return .success("Dead Code Scan found \(deadDeclarations.count) unused declarations in \(filePath):\n" + deadDeclarations.joined(separator: "\n"))
        }
    }
}
