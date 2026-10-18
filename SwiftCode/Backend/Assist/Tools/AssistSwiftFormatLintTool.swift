//
//  AssistSwiftFormatLintTool.swift
//  SwiftCode
//

import Foundation

public struct AssistSwiftFormatLintTool: AssistTool {
    public let id = "swift_format_lint"
    public let name = "Swift Format Linter"
    public let description = "Lints Swift source files for code style, line length, indentation, and formatting violations."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Scans Swift source code for formatting anomalies and style rules.",
            properties: [
                "path": JSONSchema(type: "string", description: "Relative path to Swift file in workspace.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }

        let fileURL = path.hasPrefix("/") ? URL(fileURLWithPath: path) : context.workspaceRoot.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure("File not found at path: \(path)")
        }

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return .failure("Unable to read content of \(path)")
        }

        var issues: [String] = []
        let lines = content.components(separatedBy: .newlines)

        var consecutiveEmptyLines = 0
        for (i, line) in lines.enumerated() {
            let lineNum = i + 1

            // 1. Line length
            if line.count > 140 {
                issues.append("Line \(lineNum): Line exceeds 140 characters (\(line.count) chars).")
            }

            // 2. Trailing whitespace
            if line.hasSuffix(" ") || line.hasSuffix("\t") {
                issues.append("Line \(lineNum): Trailing whitespace detected.")
            }

            // 3. Tab indentation instead of spaces
            if line.hasPrefix("\t") {
                issues.append("Line \(lineNum): Hard tab indentation used instead of spaces.")
            }

            // 4. Trailing semicolon
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(";") && !trimmed.contains("/*") {
                issues.append("Line \(lineNum): Redundant trailing semicolon.")
            }

            // 5. Multiple consecutive empty lines
            if trimmed.isEmpty {
                consecutiveEmptyLines += 1
                if consecutiveEmptyLines > 2 {
                    issues.append("Line \(lineNum): More than two consecutive blank lines.")
                }
            } else {
                consecutiveEmptyLines = 0
            }
        }

        if issues.isEmpty {
            return .success("Formatting check passed! No style or whitespace issues found in `\(path)`.")
        } else {
            let summary = "### Swift Formatting Violations in `\(path)` (\(issues.count) issues):\n\n" +
                issues.prefix(30).map { "- \($0)" }.joined(separator: "\n")
            return .success(summary)
        }
    }
}
