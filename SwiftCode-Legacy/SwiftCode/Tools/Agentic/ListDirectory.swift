import Foundation

public struct ListDirectoryTool: AgentTool {
    public static let identifier = "list_directory"
    public let name = "list_directory"
    public let description = "Lists the contents of a directory."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": ["path": ["type": "string"]],
        "required": ["path"]
    ]

    public func run(path: String) async throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let path = arguments["path"] as? String else { throw AgentError.toolError("Missing path") }
        let contents = try await run(path: path)
        return contents.joined(separator: "\n")
    }
}
