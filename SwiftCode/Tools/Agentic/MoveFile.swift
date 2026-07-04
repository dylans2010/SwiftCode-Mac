import Foundation

public struct MoveFileTool: AgentTool {
    public static let identifier = "move_file"
    public let name = "move_file"
    public let description = "Moves a file or directory."
    public let schema: [String: any Sendable] = [
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

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let source = arguments["sourcePath"] as? String,
              let dest = arguments["destinationPath"] as? String else {
            throw AgentError.toolError("Missing sourcePath or destinationPath")
        }
        try await run(sourcePath: source, destinationPath: dest)
        return "Moved \(source) to \(dest) successfully"
    }
}
