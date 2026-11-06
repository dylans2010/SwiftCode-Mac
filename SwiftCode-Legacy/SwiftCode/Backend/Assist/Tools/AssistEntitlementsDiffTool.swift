import Foundation

public struct AssistEntitlementsDiffTool: AssistTool {
    public let id = "entitlements_diff"
    public let name = "Entitlements Diff"
    public let description = "Compares two .entitlements plist files, reporting added, removed, and changed keys."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Diffs two entitlements files.",
            properties: [
                "oldPath": JSONSchema(type: "string", description: "Workspace-relative path to the baseline .entitlements file."),
                "newPath": JSONSchema(type: "string", description: "Workspace-relative path to the new .entitlements file.")
            ],
            required: ["oldPath", "newPath"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let oldRaw = (input["oldPath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !oldRaw.isEmpty,
              let newRaw = (input["newPath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !newRaw.isEmpty else {
            return .failure("Missing required parameters: oldPath and newPath")
        }
        func load(_ raw: String) -> [String: Any]? {
            guard let url = AssistWorkspacePaths.resolve(raw, workspaceRoot: context.workspaceRoot),
                  let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
            return plist
        }
        guard let old = load(oldRaw) else { return .failure("Cannot parse entitlements plist at: \(oldRaw)") }
        guard let new = load(newRaw) else { return .failure("Cannot parse entitlements plist at: \(newRaw)") }
        let oldKeys = Set(old.keys), newKeys = Set(new.keys)
        let added = newKeys.subtracting(oldKeys).sorted()
        let removed = oldKeys.subtracting(newKeys).sorted()
        var changed: [String] = []
        for key in oldKeys.intersection(newKeys).sorted() {
            let a = "\(old[key] ?? "")", b = "\(new[key] ?? "")"
            if a != b { changed.append("\(key): '\(a.prefix(60))' -> '\(b.prefix(60))'") }
        }
        if added.isEmpty && removed.isEmpty && changed.isEmpty {
            return .success("Entitlements are identical.", data: ["added": "0", "removed": "0", "changed": "0"])
        }
        var lines = ["Entitlements diff (\(oldRaw) -> \(newRaw)):"]
        lines += added.map { "- ADDED: \($0)" }
        lines += removed.map { "- REMOVED: \($0)" }
        lines += changed.map { "- CHANGED: \($0)" }
        return .success(lines.joined(separator: "\n"), data: [
            "added": "\(added.count)", "removed": "\(removed.count)", "changed": "\(changed.count)"
        ])
    }
}
