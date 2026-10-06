import Foundation

public struct AssistRenameFileTool: AssistTool {
    public let id = "file_rename"
    public let name = "Rename File"
    public let description = "Renames a file at the specified path."

    public init() {}

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Renames a file at the specified path.",
            properties: [
                "oldPath": JSONSchema(type: "string", description: "The relative path of the file to rename."),
                "newName": JSONSchema(type: "string", description: "The new filename or relative path.")
            ],
            required: ["oldPath", "newName"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let oldPath = input["oldPath"] as? String else {
            return .failure("Missing required parameter: oldPath")
        }
        guard let newName = input["newName"] as? String else {
            return .failure("Missing required parameter: newName")
        }

        do {
            let oldURL = URL(fileURLWithPath: oldPath)
            let newPath = oldURL.deletingLastPathComponent().appendingPathComponent(newName).path

            try context.fileSystem.moveFile(from: oldPath, to: newPath)

            return .success("Successfully renamed file to: \(newName)")
        } catch {
            return .failure("Failed to rename file: \(error.localizedDescription)")
        }
    }
}
