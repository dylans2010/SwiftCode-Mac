import Foundation

public struct AssistDeleteDirectoryTool: AssistTool {
    public let id = "dir_delete"
    public let name = "Delete Directory"
    public let description = "Deletes a directory and all its contents."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .potentiallyDestructive }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Deletes a directory and all of its contents. Destructive and irreversible.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of the directory to delete.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }

        do {
            // Route through the filesystem layer so traversal / symlink /
            // containment checks apply. The workspace root itself is refused.
            // Missing directories are a failure, not a silent success.
            guard context.fileSystem.exists(at: path) else {
                return .failure("No directory at \(path) — nothing to delete.")
            }
            try context.fileSystem.deleteDirectory(at: path)
            return .success("Successfully deleted directory: \(path)", data: ["path": path], filesChanged: [path])
        } catch {
            return .failure("Failed to delete directory at \(path): \(error.localizedDescription)")
        }
    }
}
