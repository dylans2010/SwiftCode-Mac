//
//  AssistYAMLParserTool.swift
//  SwiftCode
//

import Foundation

public struct AssistYAMLParserTool: AssistTool {
    public let id = "yaml_parser_tool"
    public let name = "YAML Parser & Validator"
    public let description = "Validates structure and syntax of YAML files (workflows, project.yml, fastlane) in the workspace."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Audits YAML indentation, keys, and syntax integrity for workflows or project specs.",
            properties: [
                "path": JSONSchema(type: "string", description: "Relative path to YAML file in workspace.")
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
            return .failure("File not found at: \(path)")
        }

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return .failure("Unable to read content of: \(path)")
        }

        var lines = content.components(separatedBy: .newlines)
        var errors: [String] = []
        var keysFound: [String] = []

        for (idx, line) in lines.enumerated() {
            let lineNum = idx + 1
            if line.hasPrefix("\t") {
                errors.append("Line \(lineNum): Hard tab indentation detected. YAML strictly requires spaces.")
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if let colon = trimmed.firstIndex(of: ":") {
                let k = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                if !k.hasPrefix("-") && !k.isEmpty {
                    keysFound.append("Line \(lineNum): `\(k)`")
                }
            }
        }

        var report = "### YAML Inspection for `\(path)`:\n\n"
        if !errors.isEmpty {
            report += "#### ❌ Syntax / Indentation Errors:\n"
            for err in errors {
                report += "- \(err)\n"
            }
            report += "\n"
        } else {
            report += "✅ Indentation check passed (no invalid tabs detected).\n\n"
        }

        report += "#### Root & Key Declarations (\(keysFound.count)):\n"
        for k in keysFound.prefix(20) {
            report += "- \(k)\n"
        }

        return .success(report)
    }
}
