import Foundation

public struct AssistDeleteFileTool: AssistTool {
    public let id = "file_delete"
    public let name = "Delete File"
    public let description = "Deletes a file at the specified path."

    public init() {}

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Deletes a file at the specified path.",
            properties: [
                "path": JSONSchema(type: "string", description: "The relative path to the file to delete.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }

        do {
            try context.fileSystem.deleteFile(at: path)
            return .success("Successfully deleted file: \(path)")
        } catch {
            return .failure("Failed to delete file at \(path): \(error.localizedDescription)")
        }
    }
}
