import Foundation

public struct RunBuildTool: AgentTool {
    public static let identifier = "run_build"
    public let name = "run_build"
    public let description = "Runs the build command for a Swift project."
    public let schema: [String: JSON] = [
        "type": "object",
        "properties": ["projectPath": ["type": "string"]],
        "required": ["projectPath"]
    ]

    public func run(projectPath: String) async throws -> String {
        let url = URL(fileURLWithPath: projectPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["build"],
            workingDirectory: url
        )
        return result.stdout + result.stderr
    }

    public func execute(arguments: [String: JSON]) async throws -> String {
        guard case .string(let path) = arguments["projectPath"] else { throw AgentError.toolError("Missing projectPath") }
        return try await run(projectPath: path)
    }
}
