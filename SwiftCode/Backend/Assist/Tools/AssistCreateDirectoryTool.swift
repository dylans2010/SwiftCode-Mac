import Foundation

public struct AssistCreateDirectoryTool: AssistTool {
    public let id = "dir_create"
    public let name = "Create Directory"
    public let description = "Creates a new directory at the specified path."

    public init() {}

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
