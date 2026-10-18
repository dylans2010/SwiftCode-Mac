import Foundation

public struct AssistProjectCapabilitiesTool: AssistTool {
    public let id = "project_capabilities"
    public let name = "Capabilities"
    public let description = "Lists app capabilities from entitlements and pbxproj, or enables/disables one capability by editing the entitlements plist."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Lists capabilities (action=list) or enables/disables one capability (action=enable/disable).",
            properties: [
                "action": JSONSchema(type: "string", description: "list, enable, or disable. Default: list."),
                "capability": JSONSchema(type: "string", description: "Capability name for enable/disable: push, icloud, appGroups, appSandbox, keychain, network.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let action = (input["action"] as? String ?? "list").lowercased()
        guard action == "list" || action == "enable" || action == "disable" else {
            return .failure("Invalid action '\(action)'. Expected list, enable, or disable.")
        }
        if action == "list" {
            let entitlementsCaps = entitlementCapabilities(in: context.workspaceRoot)
            let pbxCaps = pbxprojCapabilities(in: context.workspaceRoot)
            let all = Array(Set(entitlementsCaps + pbxCaps)).sorted()
            let summary = all.isEmpty ? "No capabilities found." : "Capabilities: \(all.joined(separator: ", "))"
            return .success(
                summary,
                data: [
                    "capabilities": all.joined(separator: ","),
                    "count": "\(all.count)",
                    "entitlements": entitlementsCaps.joined(separator: ","),
                    "pbxproj": pbxCaps.joined(separator: ",")
                ]
            )
        }

        guard let rawCapability = (input["capability"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawCapability.isEmpty else {
            return .failure("Missing required parameter: capability for action=\(action)")
        }
        guard let mapping = capabilityMapping(for: rawCapability) else {
            return .failure("Unknown capability '\(rawCapability)'. Supported: push, icloud, appGroups, appSandbox, keychain, network.")
        }
        guard let entitlementsURL = findEntitlementsFile(in: context.workspaceRoot) else {
            return .failure("No .entitlements file found in the workspace. Cannot \(action) capability '\(rawCapability)'.")
        }
        guard var dict = readPlist(at: entitlementsURL) else {
            return .failure("Entitlements file '\(entitlementsURL.lastPathComponent)' is not a valid property list dictionary.")
        }
        if action == "enable" {
            dict[mapping.key] = mapping.defaultValue
        } else {
            guard dict[mapping.key] != nil else {
                return .failure("Capability '\(rawCapability)' (\(mapping.key)) is not enabled in entitlements.")
            }
            dict.removeValue(forKey: mapping.key)
        }
        guard writePlist(dict, to: entitlementsURL) else {
            return .failure("Failed to write entitlements file.")
        }
        guard let verify = readPlist(at: entitlementsURL) else {
            return .failure("Verification failed: could not re-read entitlements file.")
        }
        if action == "enable" {
            guard verify[mapping.key] != nil else {
                return .failure("Verification failed: '\(mapping.key)' not present after enabling '\(rawCapability)'.")
            }
            return .success(
                "Enabled capability '\(rawCapability)' (\(mapping.key)) in \(entitlementsURL.lastPathComponent).",
                data: ["capability": rawCapability, "entitlementsKey": mapping.key, "action": "enable"],
                filesChanged: [relativePath(of: entitlementsURL, workspaceRoot: context.workspaceRoot)]
            )
        } else {
            guard verify[mapping.key] == nil else {
                return .failure("Verification failed: '\(mapping.key)' still present after disabling '\(rawCapability)'.")
            }
            return .success(
                "Disabled capability '\(rawCapability)' (\(mapping.key)) in \(entitlementsURL.lastPathComponent).",
                data: ["capability": rawCapability, "entitlementsKey": mapping.key, "action": "disable"],
                filesChanged: [relativePath(of: entitlementsURL, workspaceRoot: context.workspaceRoot)]
            )
        }
    }

    private struct CapabilityMapping {
        let key: String
        let defaultValue: Any
    }

    private func capabilityMapping(for name: String) -> CapabilityMapping? {
        switch name.lowercased() {
        case "push", "aps", "aps-environment":
            return CapabilityMapping(key: "aps-environment", defaultValue: "development")
        case "icloud", "cloudkit":
            return CapabilityMapping(key: "com.apple.developer.icloud-container-identifiers", defaultValue: [] as [String])
        case "appgroups", "app-groups", "app_groups":
            return CapabilityMapping(key: "com.apple.security.application-groups", defaultValue: [] as [String])
        case "appsandbox", "app-sandbox", "app_sandbox":
            return CapabilityMapping(key: "com.apple.security.app-sandbox", defaultValue: true)
        case "keychain", "keychain-access-groups":
            return CapabilityMapping(key: "keychain-access-groups", defaultValue: [] as [String])
        case "network", "network-client":
            return CapabilityMapping(key: "com.apple.security.network.client", defaultValue: true)
        default:
            return nil
        }
    }

    private func entitlementCapabilities(in workspaceRoot: URL) -> [String] {
        guard let url = findEntitlementsFile(in: workspaceRoot),
              let dict = readPlist(at: url) else { return [] }
        var caps: [String] = []
        for key in dict.keys {
            if key == "aps-environment" { caps.append("push") }
            else if key.contains("icloud") { caps.append("icloud") }
            else if key.contains("application-groups") { caps.append("appGroups") }
            else if key.contains("app-sandbox") { caps.append("appSandbox") }
            else if key.contains("keychain") { caps.append("keychain") }
            else if key.contains("network.client") { caps.append("network") }
            else { caps.append(key) }
        }
        return caps
    }

    private func pbxprojCapabilities(in workspaceRoot: URL) -> [String] {
        guard let pbxURL = findPBXProjURL(in: workspaceRoot),
              let content = try? String(contentsOf: pbxURL, encoding: .utf8) else { return [] }
        var caps: [String] = []
        for line in content.components(separatedBy: "\n") where line.contains("SystemCapabilities") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            caps.append(trimmed)
        }
        return caps
    }

    private func findEntitlementsFile(in workspaceRoot: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: workspaceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator where url.pathExtension == "entitlements" {
            return url
        }
        return nil
    }

    private func findPBXProjURL(in workspaceRoot: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: workspaceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == "project.pbxproj" {
            return url
        }
        return nil
    }

    private func readPlist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format) else { return nil }
        return plist as? [String: Any]
    }

    private func writePlist(_ dict: [String: Any], to url: URL) -> Bool {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private func relativePath(of url: URL, workspaceRoot: URL) -> String {
        let root = workspaceRoot.path
        if url.path.hasPrefix(root + "/") { return String(url.path.dropFirst(root.count + 1)) }
        return url.lastPathComponent
    }
}
