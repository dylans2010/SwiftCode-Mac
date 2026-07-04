import Foundation

public struct RenameFileTool: AgentTool {
    public static let identifier = "rename_file"
    public let name = "rename_file"
    public let description = "Renames a file or directory."
    public let schema: [String: JSON] = [
        "type": "object",
        "properties": [
            "oldPath": ["type": "string"],
            "newPath": ["type": "string"]
        ],
        "required": ["oldPath", "newPath"]
    ]

    public func run(oldPath: String, newPath: String) async throws {
        try FileManager.default.moveItem(atPath: oldPath, toPath: newPath)
    }

    public func execute(arguments: [String: JSON]) async throws -> String {
        guard case .string(let oldPath) = arguments["oldPath"],
              case .string(let newPath) = arguments["newPath"] else {
            throw AgentError.toolError("Missing oldPath or newPath")
        }
        try await run(oldPath: oldPath, newPath: newPath)
        return "Renamed \(oldPath) to \(newPath) successfully"
    }
}
