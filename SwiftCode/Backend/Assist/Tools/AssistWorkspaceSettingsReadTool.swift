import Foundation

public struct AssistWorkspaceSettingsReadTool: AssistTool {
    public let id = "workspace_settings_read"
    public let name = "Workspace Settings Read"
    public let description = "Reads Xcode workspace/shared settings (.xcsettings plists): build system, derived-data location, and IDE workspace checks."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(type: "object", description: "Reads workspace settings.", properties: [:], required: [])
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        let settingsFiles = AssistWorkspaceScan.files(under: root, extensions: ["xcsettings"])
        if settingsFiles.isEmpty {
            return .success("No .xcsettings files found (default Xcode workspace settings apply).", data: ["count": "0"])
        }
        var lines = ["Workspace settings files (\(settingsFiles.count)):"]
        for url in settingsFiles.sorted(by: { $0.path < $1.path }) {
            let rel = AssistWorkspacePaths.relative(url, workspaceRoot: root)
            lines.append("- \(rel):")
            if let data = try? Data(contentsOf: url),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                for (key, value) in plist.sorted(by: { $0.key < $1.key }) {
                    lines.append("    \(key) = \(String(describing: value).prefix(120))")
                }
            } else {
                lines.append("    (unreadable plist)")
            }
        }
        return .success(lines.joined(separator: "\n"), data: ["count": "\(settingsFiles.count)"])
    }
}
