import Foundation

public struct MoveFileTool: AgentTool {
    public static let identifier = "move_file"
    public let name = "move_file"
    public let description = "Moves a file or directory."
    public let schema: [String: JSON] = [
        "type": "object",
        "properties": [
            "sourcePath": ["type": "string"],
            "destinationPath": ["type": "string"]
        ],
        "required": ["sourcePath", "destinationPath"]
    ]

    public func run(sourcePath: String, destinationPath: String) async throws {
        try FileManager.default.moveItem(atPath: sourcePath, toPath: destinationPath)
    }

    public func execute(arguments: [String: JSON]) async throws -> String {
        guard case .string(let source) = arguments["sourcePath"],
              case .string(let dest) = arguments["destinationPath"] else {
            throw AgentError.toolError("Missing sourcePath or destinationPath")
        }
        try await run(sourcePath: source, destinationPath: dest)
        return "Moved \(source) to \(dest) successfully"
    }
}
