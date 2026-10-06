import Foundation

public struct AssistAppendFileTool: AssistTool {
    public let id = "file_append"
    public let name = "Append to File"
    public let description = "Appends content to the end of a file."

    public init() {}

        public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Appends content to the end of a file.",
            properties: [
                "path": JSONSchema(type: "string", description: "The relative path to the file from the workspace root."),
                "content": JSONSchema(type: "string", description: "The text content to append to the file.")
            ],
            required: ["path", "content"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }
        guard let content = input["content"] as? String else {
            return .failure("Missing required parameter: content")
        }

        do {
            let original = try context.fileSystem.readFile(at: path)
            try context.fileSystem.writeFile(at: path, content: original + content)
            return .success("Successfully appended to file: \(path)")
        } catch {
            return .failure("Failed to append to file at \(path): \(error.localizedDescription)")
        }
    }
}
