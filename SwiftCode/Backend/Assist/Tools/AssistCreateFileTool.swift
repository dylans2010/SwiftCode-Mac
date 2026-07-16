import Foundation

public struct AssistCreateFileTool: AssistTool {
    public let id = "file_create"
    public let name = "Create File"
    public let description = "Creates a new file with full content and intermediate directories when needed."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: path")
        }

        let content = input["content"] as? String ?? ""
        let overwrite = input["overwrite"] as? Bool ?? false

        if context.fileSystem.exists(at: path) && !overwrite {
            return .failure("File already exists at \(path). Set overwrite=true to replace it.")
        }

        do {
            let fileURL = URL(fileURLWithPath: path)
            let dirPath = fileURL.deletingLastPathComponent().path
            if !dirPath.isEmpty, dirPath != ".", !context.fileSystem.exists(at: dirPath) {
                try context.fileSystem.createDirectory(at: dirPath)
            }

            try context.fileSystem.writeFile(at: path, content: content)
            return .success("Created file at \(path)", data: ["path": path, "bytes": String(content.utf8.count)])
        } catch {
            return .failure("Failed to create file at \(path): \(error.localizedDescription)")
        }
    }
}
