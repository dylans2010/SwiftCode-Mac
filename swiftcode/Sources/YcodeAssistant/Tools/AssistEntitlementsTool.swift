import Foundation

public struct AssistEntitlementsTool: AssistTool {
    public let id = "entitlements_manager"
    public let name = "Entitlements Manager"
    public let description = "Inspects, adds, and removes Apple security entitlements (.entitlements) like App Sandbox and Network access."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Inspect and manage Apple entitlements files in the workspace.",
            properties: [
                "action": JSONSchema(type: "string", description: "Action: 'inspect', 'add_entitlement', 'remove_entitlement', 'list'."),
                "filePath": JSONSchema(type: "string", description: "Workspace-relative path to the .entitlements file."),
                "entitlementKey": JSONSchema(type: "string", description: "Entitlement key (e.g. 'com.apple.security.app-sandbox' or 'com.apple.security.network.client')."),
                "value": JSONSchema(type: "string", description: "Value for entitlement (default 'true').")
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
        let fileManager = FileManager.default

        switch action.lowercased() {
        case "inspect", "list":
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return .failure("Entitlements file not found at: \(filePath)")
            }
            guard let data = try? Data(contentsOf: fileURL),
                  let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
                return .failure("Invalid property list or cannot parse entitlements at: \(filePath)")
            }
            let keys = plist.keys.sorted().map { "- \($0): \(plist[$0] ?? "")" }
            return .success("Entitlements in '\(filePath)' (\(keys.count) configured):\n" + keys.joined(separator: "\n"))

        case "add_entitlement":
            guard let key = input["entitlementKey"] as? String, !key.isEmpty else {
                return .failure("entitlementKey is required for add_entitlement")
            }
            let valStr = (input["value"] as? String) ?? "true"
            let boolVal = (valStr.lowercased() == "true" || valStr == "1")

            var plistDict: [String: Any] = [:]
            var format: PropertyListSerialization.PropertyListFormat = .xml
            if fileManager.fileExists(atPath: fileURL.path),
               let data = try? Data(contentsOf: fileURL),
               let existing = (try? PropertyListSerialization.propertyList(from: data, options: [.mutableContainersAndLeaves], format: &format)) as? [String: Any] {
                plistDict = existing
            }

            plistDict[key] = boolVal

            do {
                let updatedData = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
                try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try updatedData.write(to: fileURL, options: .atomic)
                return .success("Successfully added entitlement '\(key)' = \(boolVal) in \(filePath)")
            } catch {
                return .failure("Failed to save entitlements: \(error.localizedDescription)")
            }

        case "remove_entitlement":
            guard let key = input["entitlementKey"] as? String, !key.isEmpty else {
                return .failure("entitlementKey is required for remove_entitlement")
            }
            guard fileManager.fileExists(atPath: fileURL.path),
                  let data = try? Data(contentsOf: fileURL),
                  var plistDict = (try? PropertyListSerialization.propertyList(from: data, options: [.mutableContainersAndLeaves], format: nil)) as? [String: Any] else {
                return .failure("Entitlements file does not exist at: \(filePath)")
            }

            guard plistDict.removeValue(forKey: key) != nil else {
                return .failure("Entitlement '\(key)' not found in \(filePath)")
            }

            do {
                let updatedData = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
                try updatedData.write(to: fileURL, options: .atomic)
                return .success("Successfully removed entitlement '\(key)' from \(filePath)")
            } catch {
                return .failure("Failed to update entitlements: \(error.localizedDescription)")
            }

        default:
            return .failure("Unsupported action '\(action)'. Valid: inspect, list, add_entitlement, remove_entitlement")
        }
    }
}
