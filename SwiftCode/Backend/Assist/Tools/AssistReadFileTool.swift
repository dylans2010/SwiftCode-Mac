import Foundation

public struct AssistReadFileTool: AssistTool {
    public let id = "file_read"
    public let name = "Read File"
    public let description = "Reads the content of a file at the specified path."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }

        do {
            let content = try context.fileSystem.readFile(at: path)
            return .success("Successfully read file: \(path)", data: ["content": content])
        } catch {
            return .failure("Failed to read file at \(path): \(error.localizedDescription)")
        }
    }
}
