import Foundation

public struct AssistProjectEntitlementsTool: AssistTool {
    public let id = "project_entitlements"
    public let name = "Entitlements"
    public let description = "Finds and parses .entitlements files in the workspace and returns their keys and values."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Finds and parses .entitlements files in the workspace.",
            properties: [
                "path": JSONSchema(type: "string", description: "Optional workspace-relative path to a specific .entitlements file.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let explicitPath = (input["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var fileURLs: [URL] = []
        if let explicitPath, !explicitPath.isEmpty {
            guard let resolved = resolvedURL(for: explicitPath, workspaceRoot: context.workspaceRoot) else {
                return .failure("Path '\(explicitPath)' is outside the workspace or contains '..'.")
            }
            guard FileManager.default.fileExists(atPath: resolved.path) else {
                return .failure("Entitlements file not found at '\(explicitPath)'.")
            }
            fileURLs = [resolved]
        } else {
            fileURLs = findEntitlementsFiles(in: context.workspaceRoot)
            if fileURLs.isEmpty {
                return .failure("No .entitlements files found in the workspace.")
            }
        }

        var allKeys: [String] = []
        var summaries: [String] = []
        for url in fileURLs {
            guard let data = try? Data(contentsOf: url) else {
                return .failure("Failed to read entitlements file '\(url.lastPathComponent)'.")
            }
            var format = PropertyListSerialization.PropertyListFormat.xml
            guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format),
                  let dict = plist as? [String: Any] else {
                return .failure("Entitlements file '\(url.lastPathComponent)' is not a valid property list dictionary.")
            }
            let keys = dict.keys.sorted()
            allKeys += keys
            let entries = keys.map { key in "\(key) = \(stringValue(dict[key]))" }.joined(separator: "; ")
            summaries.append("\(url.lastPathComponent): \(entries.isEmpty ? "(no keys)" : entries)")
        }
        let uniqueKeys = Array(Set(allKeys)).sorted()
        return .success(
            summaries.joined(separator: "\n"),
            data: [
                "files": fileURLs.map { $0.lastPathComponent }.joined(separator: ","),
                "keys": uniqueKeys.joined(separator: ","),
                "count": "\(uniqueKeys.count)"
            ]
        )
    }

    private func resolvedURL(for path: String, workspaceRoot: URL) -> URL? {
        if path.contains("..") { return nil }
        if path.hasPrefix("/") {
            let candidate = URL(fileURLWithPath: path).standardized
            guard candidate.path == workspaceRoot.standardized.path || candidate.path.hasPrefix(workspaceRoot.standardized.path + "/") else {
                return nil
            }
            return candidate
        }
        let candidate = workspaceRoot.appendingPathComponent(path).standardized
        guard candidate.path == workspaceRoot.standardized.path || candidate.path.hasPrefix(workspaceRoot.standardized.path + "/") else {
            return nil
        }
        return candidate
    }

    private func findEntitlementsFiles(in workspaceRoot: URL) -> [URL] {
        var results: [URL] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: workspaceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return results }
        for case let url as URL in enumerator {
            if url.pathExtension == "entitlements" { results.append(url) }
        }
        return results.sorted { $0.path < $1.path }
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
}
