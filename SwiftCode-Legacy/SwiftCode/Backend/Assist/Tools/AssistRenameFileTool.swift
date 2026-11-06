import Foundation

public struct AssistRenameFileTool: AssistTool {
    public let id = "file_rename"
    public let name = "Rename File"
    public let description = "Renames a file at the specified path."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Renames a file within its current directory.",
            properties: [
                "oldPath": JSONSchema(type: "string", description: "Workspace-relative path of the existing file."),
                "newName": JSONSchema(type: "string", description: "New file name (a single path component, not a path) within the same directory.")
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
        // newName must be a single path component: it must not escape the
        // directory via "/", "..", an empty name, or a NUL byte.
        if newName.isEmpty || newName.contains("/") || newName.contains("..") || newName.contains("\0") || newName == "." {
            return .failure("Invalid newName '\(newName)': must be a single file name, not a path.")
        }

        do {
            let oldURL = URL(fileURLWithPath: oldPath)
            let newPath = oldURL.deletingLastPathComponent().appendingPathComponent(newName).path
            guard newPath != oldPath else {
                return .failure("Rename is a no-op: newName matches the current file name.")
            }

            try context.fileSystem.moveFile(from: oldPath, to: newPath)

            return .success("Successfully renamed file to: \(newName)", data: ["path": newPath], filesChanged: [newPath])
        } catch {
            return .failure("Failed to rename file: \(error.localizedDescription)")
        }
    }
}
