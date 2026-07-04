import Foundation

public struct ReadFileTool: AgentTool {
    public static let identifier = "read_file"
    public let name = "read_file"
    public let description = "Reads the content of a file."
    public let schema: [String: JSON] = [
        "type": "object",
        "properties": ["path": ["type": "string"]],
        "required": ["path"]
    ]

    public func run(path: String) async throws -> String {
        let url = URL(fileURLWithPath: path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func execute(arguments: [String: JSON]) async throws -> String {
        guard case .string(let path) = arguments["path"] else { throw AgentError.toolError("Missing path") }
        return try await run(path: path)
    }
}
