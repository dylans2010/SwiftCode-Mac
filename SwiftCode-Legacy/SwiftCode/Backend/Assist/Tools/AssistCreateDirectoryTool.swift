import Foundation

public struct AssistCreateDirectoryTool: AssistTool {
    public let id = "dir_create"
    public let name = "Create Directory"
    public let description = "Creates a new directory at the specified path."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Creates a new directory, including any missing parent directories.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of the directory to create.")
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
            // containment checks in resolve() apply (never raw FileManager).
            try context.fileSystem.createDirectory(at: path)
            return .success("Successfully created directory: \(path)", data: ["path": path], filesChanged: [path])
        } catch {
            return .failure("Failed to create directory at \(path): \(error.localizedDescription)")
        }
    }
}
