import Foundation

public struct DeleteDirectoryTool: AgentTool {
    public static let identifier = "delete_directory"
    public let name = "delete_directory"
    public let description = "Deletes a directory and all its contents."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": ["path": ["type": "string"]],
        "required": ["path"]
    ]

    public func run(path: String) async throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.removeItem(at: url)
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let path = arguments["path"] as? String else { throw AgentError.toolError("Missing path") }
        try await run(path: path)
        return "Directory deleted successfully at \(path)"
    }
}
