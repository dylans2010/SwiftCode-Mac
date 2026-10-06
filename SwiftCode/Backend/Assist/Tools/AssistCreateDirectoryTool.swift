import Foundation

public struct AssistCreateDirectoryTool: AssistTool {
    public let id = "dir_create"
    public let name = "Create Directory"
    public let description = "Creates a new directory at the specified path."

    public init() {}

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Creates a new directory at the specified path.",
            properties: [
                "path": JSONSchema(type: "string", description: "The relative path of the directory to create.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }

        do {
            let url = context.workspaceRoot.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return .success("Successfully created directory: \(path)")
        } catch {
            return .failure("Failed to create directory at \(path): \(error.localizedDescription)")
        }
    }
}
