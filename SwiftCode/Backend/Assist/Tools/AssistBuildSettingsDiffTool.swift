import Foundation

public struct AssistBuildSettingsDiffTool: AssistTool {
    public let id = "build_settings_diff"
    public let name = "Build Settings Diff"
    public let description = "Diffs two .xcconfig files key-by-key, reporting added, removed, and changed build settings."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Diffs two .xcconfig files.",
            properties: [
                "oldPath": JSONSchema(type: "string", description: "Workspace-relative path to the baseline .xcconfig."),
                "newPath": JSONSchema(type: "string", description: "Workspace-relative path to the new .xcconfig.")
            ],
            required: ["oldPath", "newPath"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let oldRaw = (input["oldPath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !oldRaw.isEmpty,
              let newRaw = (input["newPath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !newRaw.isEmpty else {
            return .failure("Missing required parameters: oldPath and newPath")
        }
        func parse(_ raw: String) -> [String: String]? {
            guard let url = AssistWorkspacePaths.resolve(raw, workspaceRoot: context.workspaceRoot),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            var dict: [String: String] = [:]
            for line in text.components(separatedBy: .newlines) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("//") || t.hasPrefix("#") { continue }
                let parts = t.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    dict[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
            return dict
        }
        guard let old = parse(oldRaw) else { return .failure("Cannot parse xcconfig at: \(oldRaw)") }
        guard let new = parse(newRaw) else { return .failure("Cannot parse xcconfig at: \(newRaw)") }
        let added = Set(new.keys).subtracting(old.keys).sorted()
        let removed = Set(old.keys).subtracting(new.keys).sorted()
        let changed = Set(old.keys).intersection(new.keys).filter { old[$0] != new[$0] }.sorted()
        if added.isEmpty && removed.isEmpty && changed.isEmpty {
            return .success("Build settings are identical.", data: ["added": "0", "removed": "0", "changed": "0"])
        }
        var lines = ["Build settings diff (\(oldRaw) -> \(newRaw)):"]
        lines += added.map { "- ADDED: \($0) = \(new[$0] ?? "")" }
        lines += removed.map { "- REMOVED: \($0) (was: \(old[$0] ?? ""))" }
        lines += changed.map { "- CHANGED: \($0): '\(old[$0] ?? "")' -> '\(new[$0] ?? "")'" }
        return .success(lines.joined(separator: "\n"), data: [
            "added": "\(added.count)", "removed": "\(removed.count)", "changed": "\(changed.count)"
        ])
    }
}
