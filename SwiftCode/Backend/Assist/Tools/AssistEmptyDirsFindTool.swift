import Foundation

public struct AssistEmptyDirsFindTool: AssistTool {
    public let id = "empty_dirs_find"
    public let name = "Find Empty Directories"
    public let description = "Finds empty directories under a path — candidates for cleanup."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Finds empty directories.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative directory. Default: workspace root (.).")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let raw = (input["path"] as? String) ?? "."
        guard let url = AssistWorkspacePaths.resolve(raw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Refusing to access path outside the workspace: \(raw)")
        }
        var empties: [String] = []
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return .failure("Cannot enumerate directory: \(raw)")
        }
        while let child = enumerator.nextObject() as? URL {
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDir { continue }
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: child.path)) ?? []
            if contents.isEmpty {
                empties.append(AssistWorkspacePaths.relative(child, workspaceRoot: context.workspaceRoot))
            }
        }
        if empties.isEmpty {
            return .success("No empty directories under \(raw).", data: ["count": "0"])
        }
        return .success("Empty directories (\(empties.count)):\n" + empties.sorted().map { "- \($0)/" }.joined(separator: "\n"),
                        data: ["count": "\(empties.count)"])
    }
}
