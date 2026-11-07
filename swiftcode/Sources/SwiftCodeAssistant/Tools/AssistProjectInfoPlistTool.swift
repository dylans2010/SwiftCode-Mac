import Foundation

public struct AssistProjectInfoPlistTool: AssistTool {
    public let id = "project_info_plist"
    public let name = "Info.plist Editor"
    public let description = "Reads and edits Info.plist keys using PropertyListSerialization with atomic writes and verification."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Gets, sets, or deletes an Info.plist key.",
            properties: [
                "action": JSONSchema(type: "string", description: "get, set, or delete. Default: get."),
                "key": JSONSchema(type: "string", description: "Plist key. Required for set and delete."),
                "value": JSONSchema(type: "string", description: "New value for set. Interpreted as Bool for true/false, Int for integers, otherwise String."),
                "path": JSONSchema(type: "string", description: "Optional workspace-relative path to a specific Info.plist. Defaults to the first Info.plist found.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let action = (input["action"] as? String ?? "get").lowercased()
        guard action == "get" || action == "set" || action == "delete" else {
            return .failure("Invalid action '\(action)'. Expected get, set, or delete.")
        }
        let key = (input["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = input["value"] as? String
        let explicitPath = (input["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let plistURL: URL
        if let explicitPath, !explicitPath.isEmpty {
            guard let resolved = resolvedURL(for: explicitPath, workspaceRoot: context.workspaceRoot) else {
                return .failure("Path '\(explicitPath)' is outside the workspace or contains '..'.")
            }
            plistURL = resolved
        } else {
            guard let found = findInfoPlist(in: context.workspaceRoot) else {
                return .failure("No Info.plist found in the workspace.")
            }
            plistURL = found
        }
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            return .failure("Info.plist not found at '\(plistURL.lastPathComponent)'.")
        }
        guard var dict = readPlist(at: plistURL) else {
            return .failure("Info.plist at '\(plistURL.lastPathComponent)' is not a valid property list dictionary.")
        }

        switch action {
        case "get":
            if let key, !key.isEmpty {
                guard let found = dict[key] else {
                    return .failure("Key '\(key)' not found in Info.plist.")
                }
                return .success("Info.plist \(key) = \(stringValue(found))", data: ["key": key, "value": stringValue(found), "file": plistURL.lastPathComponent])
            }
            let keys = dict.keys.sorted()
            let entries = keys.map { "\($0) = \(stringValue(dict[$0]))" }.joined(separator: "\n")
            return .success(
                "Info.plist has \(keys.count) key(s):\n\(entries)",
                data: ["keys": keys.joined(separator: ","), "count": "\(keys.count)", "file": plistURL.lastPathComponent]
            )
        case "set":
            guard let key, !key.isEmpty else { return .failure("Missing required parameter: key for action=set") }
            guard let value else { return .failure("Missing required parameter: value for action=set") }
            let before = dict[key]
            dict[key] = plistValue(from: value)
            guard writePlist(dict, to: plistURL) else {
                return .failure("Failed to write Info.plist.")
            }
            guard let verify = readPlist(at: plistURL),
                  let written = verify[key],
                  stringValue(written) == stringValue(plistValue(from: value)) else {
                return .failure("Verification failed: key '\(key)' was not written to Info.plist.")
            }
            return .success(
                "Set Info.plist \(key) = \(value) (was: \(stringValue(before))).",
                data: ["key": key, "value": value, "file": plistURL.lastPathComponent],
                filesChanged: [relativePath(of: plistURL, workspaceRoot: context.workspaceRoot)]
            )
        case "delete":
            guard let key, !key.isEmpty else { return .failure("Missing required parameter: key for action=delete") }
            guard dict[key] != nil else { return .failure("Key '\(key)' not found in Info.plist.") }
            dict.removeValue(forKey: key)
            guard writePlist(dict, to: plistURL) else {
                return .failure("Failed to write Info.plist.")
            }
            guard let verify = readPlist(at: plistURL), verify[key] == nil else {
                return .failure("Verification failed: key '\(key)' still present in Info.plist.")
            }
            return .success(
                "Deleted Info.plist key '\(key)'.",
                data: ["key": key, "file": plistURL.lastPathComponent],
                filesChanged: [relativePath(of: plistURL, workspaceRoot: context.workspaceRoot)]
            )
        default:
            return .failure("Invalid action '\(action)'.")
        }
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

    private func plistValue(from string: String) -> Any {
        let lower = string.lowercased()
        if lower == "true" { return true }
        if lower == "false" { return false }
        if let intValue = Int(string) { return intValue }
        if let doubleValue = Double(string) { return doubleValue }
        return string
    }

    private func stringValue(_ value: Any?) -> String {
        guard let value else { return "null" }
        if let boolValue = value as? Bool { return boolValue ? "true" : "false" }
        if let array = value as? [Any] { return "[" + array.map { stringValue($0) }.joined(separator: ", ") + "]" }
        if let dict = value as? [String: Any] {
            return "{" + dict.keys.sorted().map { "\($0) = \(stringValue(dict[$0]))" }.joined(separator: ", ") + "}"
        }
        return "\(value)"
    }

    private func findInfoPlist(in workspaceRoot: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: workspaceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        var candidates: [URL] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "Info.plist" else { continue }
            let path = url.path
            if path.contains("/build/") || path.contains("/DerivedData/") || path.contains("/.build/") { continue }
            candidates.append(url)
        }
        return candidates.sorted { $0.path < $1.path }.first
    }

    private func resolvedURL(for path: String, workspaceRoot: URL) -> URL? {
        if path.contains("..") { return nil }
        if path.hasPrefix("/") {
            let candidate = URL(fileURLWithPath: path).standardized
            guard candidate.path == workspaceRoot.standardized.path || candidate.path.hasPrefix(workspaceRoot.standardized.path + "/") else { return nil }
            return candidate
        }
        let candidate = workspaceRoot.appendingPathComponent(path).standardized
        guard candidate.path == workspaceRoot.standardized.path || candidate.path.hasPrefix(workspaceRoot.standardized.path + "/") else { return nil }
        return candidate
    }

    private func relativePath(of url: URL, workspaceRoot: URL) -> String {
        let root = workspaceRoot.path
        if url.path.hasPrefix(root + "/") { return String(url.path.dropFirst(root.count + 1)) }
        return url.lastPathComponent
    }
}
