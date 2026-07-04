import Foundation

public struct DeleteFileTool: AgentTool {
    public static let identifier = "delete_file"
    public let name = "delete_file"
    public let description = "Deletes a file."
    public let schema: [String: JSON] = [
        "type": "object",
        "properties": ["path": ["type": "string"]],
        "required": ["path"]
    ]

    public func run(path: String) async throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.removeItem(at: url)
    }

    public func execute(arguments: [String: JSON]) async throws -> String {
        guard case .string(let path) = arguments["path"] else { throw AgentError.toolError("Missing path") }
        try await run(path: path)
        return "File deleted successfully at \(path)"
    }
}
