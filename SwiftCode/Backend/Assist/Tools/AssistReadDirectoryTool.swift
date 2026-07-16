import Foundation

public struct AssistReadDirectoryTool: AssistTool {
    public let id = "dir_read"
    public let name = "Read Directory"
    public let description = "Lists the contents of a directory."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }

        do {
            let contents = try context.fileSystem.listDirectory(at: path)
            return .success("Successfully read directory: \(path)", data: ["contents": contents.joined(separator: "\n")])
        } catch {
            return .failure("Failed to read directory at \(path): \(error.localizedDescription)")
        }
    }
}
