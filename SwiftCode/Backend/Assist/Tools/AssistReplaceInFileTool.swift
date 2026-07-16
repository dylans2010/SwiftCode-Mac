import Foundation

public struct AssistReplaceInFileTool: AssistTool {
    public let id = "code_replace"
    public let name = "Replace in File"
    public let description = "Replaces occurrences of a string with another within a file."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }
        guard let target = input["target"] as? String else {
            return .failure("Missing required parameter: target")
        }
        guard let replacement = input["replacement"] as? String else {
            return .failure("Missing required parameter: replacement")
        }

        do {
            let original = try context.fileSystem.readFile(at: path)
            let modified = original.replacingOccurrences(of: target, with: replacement)
            try context.fileSystem.writeFile(at: path, content: modified)
            return .success("Successfully replaced in file: \(path)")
        } catch {
            return .failure("Failed to replace in file at \(path): \(error.localizedDescription)")
        }
    }
}
