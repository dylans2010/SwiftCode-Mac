import Foundation

public struct CopyFileTool: AgentTool {
    public static let identifier = "copy_file"
    public let name = "copy_file"
    public let description = "Copies a file or directory."
    public let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "sourcePath": ["type": "string"],
            "destinationPath": ["type": "string"]
        ],
        "required": ["sourcePath", "destinationPath"]
    ]

    public func run(sourcePath: String, destinationPath: String) async throws {
        try FileManager.default.copyItem(atPath: sourcePath, toPath: destinationPath)
    }

    public func execute(arguments: [String: Any]) async throws -> String {
        guard let source = arguments["sourcePath"] as? String,
              let dest = arguments["destinationPath"] as? String else {
            throw AgentError.toolError("Missing sourcePath or destinationPath")
        }
        try await run(sourcePath: source, destinationPath: dest)
        return "Copied \(source) to \(dest) successfully"
    }
}
