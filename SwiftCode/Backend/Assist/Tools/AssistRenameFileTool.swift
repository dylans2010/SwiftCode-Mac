import Foundation

public struct AssistRenameFileTool: AssistTool {
    public let id = "file_rename"
    public let name = "Rename File"
    public let description = "Renames a file at the specified path."

    public init() {}

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
