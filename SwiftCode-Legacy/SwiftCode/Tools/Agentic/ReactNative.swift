import Foundation

public struct ReactNativeTool: AgentTool {
    public static let identifier = "react_native"
    public let name = "react_native"
    public let description = "Runs React Native commands."
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
            executableURL: URL(fileURLWithPath: "/usr/bin/npx"),
            arguments: ["react-native", action],
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
