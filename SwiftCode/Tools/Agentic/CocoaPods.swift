import Foundation

public struct CocoaPodsTool: AgentTool {
    public static let identifier = "cocoapods"
    public let name = "cocoapods"
    public let description = "Runs CocoaPods commands."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "action": ["type": "string"] as [String: any Sendable],
            "path": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["action", "path"]
    ]

    public func run(action: String, path: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/local/bin/pod"),
            arguments: [action],
            workingDirectory: URL(fileURLWithPath: path)
        )
        return result.stdout + result.stderr
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let action = arguments["action"] as? String,
              let path = arguments["path"] as? String else {
            throw AgentError.toolError("Missing action or path")
        }
        return try await run(action: action, path: path)
    }
}
