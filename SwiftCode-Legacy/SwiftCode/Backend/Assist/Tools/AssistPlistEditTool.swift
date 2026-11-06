import Foundation

public struct AssistPlistEditTool: AssistTool {
    public let id = "plist_edit"
    public let name = "Edit Plist"
    public let description = "Gets, sets, or deletes a key in a plist file using PropertyListSerialization."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Manages one key in a plist file.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the plist file (required)."),
                "action": JSONSchema(type: "string", description: "get, set, or delete. Default: get."),
                "key": JSONSchema(type: "string", description: "Plist key (required)."),
                "value": JSONSchema(type: "string", description: "String value for set action.")
            ],
            required: ["path", "key"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let rawPath = input["path"] as? String, !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: path")
        }
        guard let key = input["key"] as? String, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: key")
        }
        let action = ((input["action"] as? String) ?? "get").lowercased()
        guard action == "get" || action == "set" || action == "delete" else {
            return .failure("Invalid action '\(action)': must be get, set, or delete.")
        }
        if action == "set" {
            guard let value = input["value"] as? String else {
                return .failure("Missing required parameter: value for set action.")
            }
            _ = value
        }
        guard let fileURL = resolvePath(rawPath, workspaceRoot: context.workspaceRoot) else {
            return .failure("Invalid path '\(rawPath)': must be inside the workspace and must not contain '..'.")
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure("Plist file not found at '\(rawPath)'.")
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return .failure("Failed to read plist at '\(rawPath)'.")
        }
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format),
              var dict = plist as? [String: Any] else {
            return .failure("Plist at '\(rawPath)' is not a dictionary plist. Key-based edit requires a top-level dictionary.")
        }
        if action == "get" {
            guard let found = dict[key] else {
                return .failure("Key '\(key)' not found in '\(rawPath)'.")
            }
            return .success("Key '\(key)' = \(describeValue(found)) in '\(rawPath)'.", data: ["key": key, "value": describeValue(found), "path": rawPath])
        }
        if action == "set" {
            let value = (input["value"] as? String) ?? ""
            dict[key] = value
            do {
                let out = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
                try out.write(to: fileURL, options: [.atomic])
            } catch {
                return .failure("Failed to write plist: \(error.localizedDescription)")
            }
            guard let verifyData = try? Data(contentsOf: fileURL),
                  let verifyPlist = try? PropertyListSerialization.propertyList(from: verifyData, options: [], format: &format),
                  let verifyDict = verifyPlist as? [String: Any],
                  let verifyValue = verifyDict[key] as? String, verifyValue == value else {
                return .failure("Verification failed: key not present after write.")
            }
            return .success("Set key '\(key)' in '\(rawPath)'.", data: ["key": key, "value": value, "path": rawPath])
        }
        // delete
        guard dict[key] != nil else {
            return .failure("Key '\(key)' not found in '\(rawPath)'.")
        }
        dict.removeValue(forKey: key)
        do {
            let out = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            try out.write(to: fileURL, options: [.atomic])
        } catch {
            return .failure("Failed to write plist: \(error.localizedDescription)")
        }
        guard let verifyData = try? Data(contentsOf: fileURL),
              let verifyPlist = try? PropertyListSerialization.propertyList(from: verifyData, options: [], format: &format),
              let verifyDict = verifyPlist as? [String: Any],
              verifyDict[key] == nil else {
            return .failure("Verification failed: key still present after delete.")
        }
        return .success("Deleted key '\(key)' from '\(rawPath)'.", data: ["key": key, "path": rawPath])
    }

    private func describeValue(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let number = value as? NSNumber { return "\(number)" }
        if let array = value as? [Any] { return "array(\(array.count))" }
        if let dict = value as? [String: Any] { return "dictionary(\(dict.count))" }
        return "\(value)"
    }

    private func resolvePath(_ rawPath: String, workspaceRoot: URL) -> URL? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.contains("..") { return nil }
        let root = workspaceRoot.standardizedFileURL
        if trimmed.hasPrefix("/") {
            let candidate = URL(fileURLWithPath: trimmed).standardizedFileURL
            guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return nil }
            return candidate
        }
        let candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return nil }
        return candidate
    }
}
