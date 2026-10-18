//
//  AssistGitConflictResolverTool.swift
//  SwiftCode
//

import Foundation

public struct AssistGitConflictResolverTool: AssistTool {
    public let id = "git_conflict_resolver"
    public let name = "Git Conflict Resolver"
    public let description = "Detects, inspects, and helps resolve Git merge conflict markers in workspace source files."

    public init() {}

    public var capability: ToolCapability { .gitOperations }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Scans for and resolves merge conflict markers (<<<<<<< HEAD ... ======= ... >>>>>>>).",
            properties: [
                "path": JSONSchema(type: "string", description: "Relative path to file with merge conflicts."),
                "resolution": JSONSchema(type: "string", description: "Optional resolution strategy: 'inspect', 'take_ours', 'take_theirs'. Defaults to 'inspect'.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }
        let resolution = (input["resolution"] as? String)?.lowercased() ?? "inspect"

        let fileURL = path.hasPrefix("/") ? URL(fileURLWithPath: path) : context.workspaceRoot.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure("File not found at path: \(path)")
        }

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return .failure("Unable to read content of file at \(path)")
        }

        guard content.contains("<<<<<<<") && content.contains("=======") && content.contains(">>>>>>>") else {
            return .success("No active Git conflict markers (<<<<<<< / ======= / >>>>>>>) found in \(path).")
        }

        if resolution == "inspect" {
            var conflicts: [String] = []
            let lines = content.components(separatedBy: .newlines)
            var inConflict = false
            var currentBlock: [String] = []

            for line in lines {
                if line.hasPrefix("<<<<<<<") {
                    inConflict = true
                    currentBlock = [line]
                } else if line.hasPrefix(">>>>>>>") && inConflict {
                    currentBlock.append(line)
                    conflicts.append(currentBlock.joined(separator: "\n"))
                    inConflict = false
                    currentBlock = []
                } else if inConflict {
                    currentBlock.append(line)
                }
            }

            var report = "### Detected \(conflicts.count) Merge Conflict(s) in `\(path)`:\n\n"
            for (idx, c) in conflicts.enumerated() {
                report += "#### Conflict #\(idx + 1):\n```\n\(c)\n```\n\n"
            }
            report += "Use resolution: 'take_ours' or 'take_theirs', or code_replace to resolve precisely."
            return .success(report)
        }

        if resolution == "take_ours" || resolution == "take_theirs" {
            let lines = content.components(separatedBy: .newlines)
            var resolvedLines: [String] = []
            var state: ConflictState = .normal

            enum ConflictState {
                case normal
                case inOurs
                case inTheirs
            }

            for line in lines {
                if line.hasPrefix("<<<<<<<") {
                    state = .inOurs
                } else if line.hasPrefix("=======") && state == .inOurs {
                    state = .inTheirs
                } else if line.hasPrefix(">>>>>>>") && (state == .inTheirs || state == .inOurs) {
                    state = .normal
                } else {
                    switch state {
                    case .normal:
                        resolvedLines.append(line)
                    case .inOurs:
                        if resolution == "take_ours" {
                            resolvedLines.append(line)
                        }
                    case .inTheirs:
                        if resolution == "take_theirs" {
                            resolvedLines.append(line)
                        }
                    }
                }
            }

            let resolvedText = resolvedLines.joined(separator: "\n")
            do {
                try resolvedText.write(to: fileURL, atomically: true, encoding: .utf8)
                return .success("Successfully resolved all conflict markers in `\(path)` using '\(resolution)'.")
            } catch {
                return .failure("Failed to write resolved file: \(error.localizedDescription)")
            }
        }

        return .failure("Unknown resolution '\(resolution)'. Use 'inspect', 'take_ours', or 'take_theirs'.")
    }
}
