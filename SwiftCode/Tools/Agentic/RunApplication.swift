import Foundation

public struct RunApplicationTool: AgentTool {
    public static let identifier = "run_application"
    public let name = "run_application"
    public let description = "Runs a Swift application target."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "projectPath": ["type": "string"] as [String: any Sendable],
            "target": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["projectPath", "target"]
    ]

    public func run(projectPath: String, target: String) async throws -> String {
        let url = URL(fileURLWithPath: projectPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["run", target],
            workingDirectory: url
        )
        return result.stdout + result.stderr
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let projectPath = arguments["projectPath"] as? String,
              let target = arguments["target"] as? String else {
            throw AgentError.toolError("Missing projectPath or target")
        }
        return try await run(projectPath: projectPath, target: target)
    }
}
