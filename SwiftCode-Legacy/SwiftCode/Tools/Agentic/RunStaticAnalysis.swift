import Foundation

public struct RunStaticAnalysisTool: AgentTool {
    public static let identifier = "run_static_analysis"
    public let name = "run_static_analysis"
    public let description = "Runs static analysis on a Swift project."
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
            arguments: ["build", "--build-tests", "-Xswiftc", "-analyze"],
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
