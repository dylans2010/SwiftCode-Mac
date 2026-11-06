import Foundation

public struct PythonPipTool: AgentTool {
    public static let identifier = "python_pip"
    public let name = "python_pip"
    public let description = "Runs pip commands."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "action": ["type": "string"] as [String: any Sendable],
            "package": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["action", "package"]
    ]

    public func run(action: String, package: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/pip"),
            arguments: [action, package]
        )
        return result.stdout + result.stderr
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let action = arguments["action"] as? String,
              let package = arguments["package"] as? String else {
            throw AgentError.toolError("Missing action or package")
        }
        return try await run(action: action, package: package)
    }
}
