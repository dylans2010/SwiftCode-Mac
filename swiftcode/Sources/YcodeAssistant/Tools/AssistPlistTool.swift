import Foundation

public struct AssistPlistTool: AssistTool {
    public let id = "plist_editor"
    public let name = "Property List Editor"
    public let description = "Inspects, sets, deletes, and validates keys in Apple Property List (.plist) files."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Read, set, or delete values in Info.plist or any property list file.",
            properties: [
                "action": JSONSchema(type: "string", description: "Action: 'read', 'set', 'delete', 'list_keys'."),
                "filePath": JSONSchema(type: "string", description: "Workspace-relative path to the .plist file."),
                "key": JSONSchema(type: "string", description: "Property list key to read, set, or delete."),
                "value": JSONSchema(type: "string", description: "Value to write (for 'set')."),
                "valueType": JSONSchema(type: "string", description: "Type of value: 'string', 'boolean', 'integer' (defaults to string).")
            ],
            required: ["action", "filePath"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let action = input["action"] as? String,
              let filePath = input["filePath"] as? String else {
            return .failure("Missing required parameters: action and filePath")
        }

        let fileURL = context.workspaceRoot.appendingPathComponent(filePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure("Plist file does not exist at path: \(filePath)")
        }

        do {
            let data = try Data(contentsOf: fileURL)
            var format: PropertyListSerialization.PropertyListFormat = .xml
            guard var plistDict = try PropertyListSerialization.propertyList(from: data, options: [.mutableContainersAndLeaves], format: &format) as? [String: Any] else {
                return .failure("File at \(filePath) is not a dictionary-rooted property list.")
            }

            switch action.lowercased() {
            case "list_keys":
                let keys = plistDict.keys.sorted()
                return .success("Plist contains \(keys.count) keys:\n" + keys.joined(separator: "\n"))

            case "read":
                guard let key = input["key"] as? String, !key.isEmpty else {
                    return .failure("key parameter is required for read")
                }
                if let val = plistDict[key] {
                    return .success("\(key) = \(String(describing: val))")
                } else {
                    return .failure("Key '\(key)' not found in \(filePath)")
                }

            case "set":
                guard let key = input["key"] as? String, !key.isEmpty else {
                    return .failure("key parameter is required for set")
                }
                let valStr = (input["value"] as? String) ?? ""
                let vType = (input["valueType"] as? String)?.lowercased() ?? "string"

                if vType == "boolean" {
                    plistDict[key] = (valStr.lowercased() == "true" || valStr == "1")
                } else if vType == "integer" {
                    plistDict[key] = Int(valStr) ?? 0
                } else {
                    plistDict[key] = valStr
                }

                let updatedData = try PropertyListSerialization.data(fromPropertyList: plistDict, format: format, options: 0)
                try updatedData.write(to: fileURL, options: .atomic)
                return .success("Successfully set '\(key)' = \(valStr) in \(filePath)")

            case "delete":
                guard let key = input["key"] as? String, !key.isEmpty else {
                    return .failure("key parameter is required for delete")
                }
                guard plistDict.removeValue(forKey: key) != nil else {
                    return .failure("Key '\(key)' not found in \(filePath)")
                }
                let updatedData = try PropertyListSerialization.data(fromPropertyList: plistDict, format: format, options: 0)
                try updatedData.write(to: fileURL, options: .atomic)
                return .success("Successfully removed key '\(key)' from \(filePath)")

            default:
                return .failure("Unsupported action '\(action)'. Valid: read, set, delete, list_keys")
            }
        } catch {
            return .failure("Error processing plist: \(error.localizedDescription)")
        }
    }
}
