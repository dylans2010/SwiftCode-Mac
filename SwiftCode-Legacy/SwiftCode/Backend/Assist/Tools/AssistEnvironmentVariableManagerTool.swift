//
//  AssistEnvironmentVariableManagerTool.swift
//  SwiftCode
//

import Foundation

public struct AssistEnvironmentVariableManagerTool: AssistTool {
    public let id = "environment_variable_manager"
    public let name = "Environment Variable Manager"
    public let description = "Inspects, checks, or updates workspace .env configuration files and environment keys."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Reads or updates environment keys in workspace .env files (e.g. API endpoints, feature flags).",
            properties: [
                "action": JSONSchema(type: "string", description: "Action: 'list_keys', 'get', 'set'."),
                "key": JSONSchema(type: "string", description: "Variable name when action is 'get' or 'set'."),
                "value": JSONSchema(type: "string", description: "Value to write when action is 'set'."),
                "envFilePath": JSONSchema(type: "string", description: "Optional path to .env file. Defaults to '.env'.")
            ],
            required: ["action"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let action = input["action"] as? String else {
            return .failure("Missing required parameter: action")
        }
        let envFileName = (input["envFilePath"] as? String) ?? ".env"
        let envURL = envFileName.hasPrefix("/") ? URL(fileURLWithPath: envFileName) : context.workspaceRoot.appendingPathComponent(envFileName)

        switch action.lowercased() {
        case "list_keys", "list":
            guard FileManager.default.fileExists(atPath: envURL.path),
                  let text = try? String(contentsOf: envURL, encoding: .utf8) else {
                return .success("No \(envFileName) file found in workspace.")
            }
            var keys: [String] = []
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                if let eq = trimmed.firstIndex(of: "=") {
                    keys.append(String(trimmed[..<eq]))
                }
            }
            return .success("Found \(keys.count) environment keys in `\(envFileName)`:\n\n" + keys.map { "- `\($0)`" }.joined(separator: "\n"))

        case "get":
            guard let key = input["key"] as? String, !key.isEmpty else {
                return .failure("Action 'get' requires 'key'.")
            }
            guard FileManager.default.fileExists(atPath: envURL.path),
                  let text = try? String(contentsOf: envURL, encoding: .utf8) else {
                return .failure("No \(envFileName) file found in workspace.")
            }
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("\(key)=") {
                    let val = String(trimmed.dropFirst(key.count + 1))
                    return .success("\(key)=\(val)")
                }
            }
            return .failure("Key '\(key)' not found in \(envFileName).")

        case "set":
            guard let key = input["key"] as? String, !key.isEmpty else {
                return .failure("Action 'set' requires 'key'.")
            }
            let val = (input["value"] as? String) ?? ""
            var existing = (try? String(contentsOf: envURL, encoding: .utf8)) ?? ""
            var lines = existing.components(separatedBy: .newlines)
            var replaced = false

            for (i, line) in lines.enumerated() {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("\(key)=") {
                    lines[i] = "\(key)=\(val)"
                    replaced = true
                    break
                }
            }
            if !replaced {
                lines.append("\(key)=\(val)")
            }
            let updated = lines.joined(separator: "\n")
            do {
                try updated.write(to: envURL, atomically: true, encoding: .utf8)
                return .success("Successfully set `\(key)` in `\(envFileName)`.")
            } catch {
                return .failure("Failed to write to \(envFileName): \(error.localizedDescription)")
            }

        default:
            return .failure("Unsupported action '\(action)'. Supported: list_keys, get, set.")
        }
    }
}
