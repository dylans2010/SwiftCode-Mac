import Foundation

public struct DeleteFileTool: AgentTool {
    public static let identifier = "delete_file"
    public let name = "delete_file"
    public let description = "Deletes a file."
    public let schema: [String: Any] = [
        "type": "object",
        "properties": ["path": ["type": "string"]],
        "required": ["path"]
    ]

    public func run(path: String) async throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.removeItem(at: url)
    }

    public func execute(arguments: [String: Any]) async throws -> String {
        guard let path = arguments["path"] as? String else { throw AgentError.toolError("Missing path") }
        try await run(path: path)
        return "File deleted successfully at \(path)"
    }
}
