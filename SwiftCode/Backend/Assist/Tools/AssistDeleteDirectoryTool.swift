import Foundation

public struct AssistDeleteDirectoryTool: AssistTool {
    public let id = "dir_delete"
    public let name = "Delete Directory"
    public let description = "Deletes a directory and all its contents."

    public init() {}

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Deletes a directory and all its contents.",
            properties: [
                "path": JSONSchema(type: "string", description: "The relative path of the directory to delete.")
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
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return .success("Successfully deleted directory: \(path)")
        } catch {
            return .failure("Failed to delete directory at \(path): \(error.localizedDescription)")
        }
    }
}
