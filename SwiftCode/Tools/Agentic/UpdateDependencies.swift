import Foundation

public struct UpdateDependenciesTool: AgentTool {
    public static let identifier = "update_dependencies"
    public let name = "update_dependencies"
    public let description = "Updates project dependencies."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "projectPath": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["projectPath"]
    ]

    public func run(projectPath: String) async throws -> String {
        let url = URL(fileURLWithPath: projectPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["package", "update"],
            workingDirectory: url
        )
        return result.stdout + result.stderr
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let projectPath = arguments["projectPath"] as? String else {
            throw AgentError.toolError("Missing projectPath")
        }
        return try await run(projectPath: projectPath)
    }
}
