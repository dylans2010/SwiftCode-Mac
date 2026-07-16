import Foundation

public struct AssistCopyFileTool: AssistTool {
    public let id = "file_copy"
    public let name = "Copy File"
    public let description = "Copies a file from source to destination path."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let source = input["source"] as? String else {
            return .failure("Missing required parameter: source")
        }
        guard let destination = input["destination"] as? String else {
            return .failure("Missing required parameter: destination")
        }

        do {
            try context.fileSystem.copyFile(from: source, to: destination)
            return .success("Successfully copied file from \(source) to \(destination)")
        } catch {
            return .failure("Failed to copy file: \(error.localizedDescription)")
        }
    }
}
