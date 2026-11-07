import Foundation

public struct AssistJsonValidateTool: AssistTool {
    public let id = "json_validate"
    public let name = "Validate JSON"
    public let description = "Validates a JSON file, and optionally formats it as pretty-printed sorted-keys JSON, writing the result back only when write is true."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Validates a JSON file, and optionally formats it.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of the JSON file."),
                "action": JSONSchema(type: "string", description: "Action: validate or format. Default: validate."),
                "write": JSONSchema(type: "string", description: "Pass \"true\" to write the formatted JSON back to the file on format. Default: false.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let rawPath = (input["path"] as? String), !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: path")
        }
        guard let url = resolveWorkspacePath(rawPath, workspaceRoot: context.workspaceRoot) else {
            return .failure("Refusing to access path outside the workspace: \(rawPath)")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return .failure("JSON validation requires an existing file: \(rawPath)")
        }

        let action = ((input["action"] as? String) ?? "validate").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard action == "validate" || action == "format" else {
            return .failure("Invalid action '\(action)'. Allowed: validate, format.")
        }
        let shouldWrite = boolValue(input["write"])
        let relative = relativePath(url, workspaceRoot: context.workspaceRoot)

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .failure("Failed to read \(relative): \(error.localizedDescription)")
        }

        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
        } catch {
            return .failure("Invalid JSON in \(relative): \(error.localizedDescription)")
        }

        if action == "validate" {
            return .success("Valid JSON in \(relative).", data: ["path": relative, "valid": "true", "written": "false"])
        }

        let formattedData: Data
        do {
            formattedData = try JSONSerialization.data(withJSONObject: parsed, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
        } catch {
            return .failure("Could not format JSON in \(relative): \(error.localizedDescription)")
        }
        guard let formatted = String(data: formattedData, encoding: .utf8) else {
            return .failure("Could not encode formatted JSON for \(relative) as UTF-8.")
        }

        if shouldWrite {
            do {
                try formattedData.write(to: url, options: [.atomic])
            } catch {
                return .failure("Failed to write formatted JSON to \(relative): \(error.localizedDescription)")
            }
            return .success("Valid JSON in \(relative). Formatted JSON written back to the file.", data: ["path": relative, "valid": "true", "written": "true", "formatted": formatted])
        }
        return .success("Valid JSON in \(relative). Formatted preview returned without writing.", data: ["path": relative, "valid": "true", "written": "false", "formatted": formatted])
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let s = value as? String {
            let lowered = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return lowered == "true" || lowered == "1" || lowered == "yes"
        }
        return false
    }

    private func resolveWorkspacePath(_ raw: String, workspaceRoot: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0"), !trimmed.hasPrefix("~"), !trimmed.contains("..") else {
            return nil
        }
        let rootPath = workspaceRoot.standardized.path
        let candidate: URL
        if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed).standardized
        } else {
            candidate = workspaceRoot.appendingPathComponent(trimmed).standardized
        }
        let candidatePath = candidate.path
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            return nil
        }
        return candidate
    }

    private func relativePath(_ url: URL, workspaceRoot: URL) -> String {
        let rootPath = workspaceRoot.standardized.path
        let path = url.standardized.path
        if path == rootPath { return "." }
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return path
    }
}
