import Foundation

public struct CreateDirectoryTool: AgentTool {
    public static let identifier = "create_directory"
    public let name = "create_directory"
    public let description = "Creates a new directory, including intermediate directories if necessary."
    public let schema: [String: JSON] = [
        "type": "object",
        "properties": ["path": ["type": "string"]],
        "required": ["path"]
    ]

    public func run(path: String) async throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    public func execute(arguments: [String: JSON]) async throws -> String {
        guard case .string(let path) = arguments["path"] else { throw AgentError.toolError("Missing path") }
        try await run(path: path)
        return "Directory created successfully at \(path)"
    }
}
