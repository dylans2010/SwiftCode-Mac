//
//  AssistJSONValidatorTool.swift
//  SwiftCode
//

import Foundation

public struct AssistJSONValidatorTool: AssistTool {
    public let id = "json_validator_tool"
    public let name = "JSON Validator & Formatter"
    public let description = "Validates JSON syntax, highlights line errors, and beautifies JSON configuration files."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Validates and optionally beautifies JSON content or JSON files in workspace.",
            properties: [
                "path": JSONSchema(type: "string", description: "Relative path to JSON file in workspace."),
                "formatInPlace": JSONSchema(type: "boolean", description: "If true, reformats and writes pretty-printed JSON back to disk. Defaults to false.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }
        let formatInPlace = (input["formatInPlace"] as? Bool) ?? false

        let fileURL = path.hasPrefix("/") ? URL(fileURLWithPath: path) : context.workspaceRoot.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure("File not found at: \(path)")
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return .failure("Unable to read data from: \(path)")
        }

        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            if formatInPlace {
                let pretty = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
                try pretty.write(to: fileURL)
                return .success("JSON is valid! Successfully reformatted and saved `\(path)` with standard 2-space pretty-printing.")
            } else {
                return .success("✅ JSON syntax valid for `\(path)` (\(data.count) bytes). Top-level type: \(type(of: jsonObject)).")
            }
        } catch let err as NSError {
            return .failure("JSON Validation Error in `\(path)`: \(err.localizedDescription)")
        }
    }
}
