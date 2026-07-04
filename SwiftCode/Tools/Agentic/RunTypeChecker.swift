import Foundation

public struct RunTypeCheckerTool: AgentTool {
    public static let identifier = "run_type_checker"
    public let name = "run_type_checker"
    public let description = "Runs the Swift type checker on a project."
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
            arguments: ["build", "--build-tests"],
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
