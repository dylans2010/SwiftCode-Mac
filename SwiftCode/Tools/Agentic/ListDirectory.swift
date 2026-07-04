import Foundation

public struct ListDirectoryTool: AgentTool {
    public static let identifier = "list_directory"
    public let name = "list_directory"
    public let description = "Lists the contents of a directory."
    public let schema: [String: JSON] = [
        "type": "object",
        "properties": ["path": ["type": "string"]],
        "required": ["path"]
    ]

    public func run(path: String) async throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }

    public func execute(arguments: [String: JSON]) async throws -> String {
        guard case .string(let path) = arguments["path"] else { throw AgentError.toolError("Missing path") }
        let contents = try await run(path: path)
        return contents.joined(separator: "\n")
    }
}
