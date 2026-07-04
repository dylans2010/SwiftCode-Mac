import Foundation

public struct RunLinterTool: AgentTool {
    public static let identifier = "run_linter"
    public let name = "run_linter"
    public let description = "Runs a linter (SwiftLint) on a given path."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "path": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["path"]
    ]

    public func run(path: String) async throws -> String {
        let url = URL(fileURLWithPath: path)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/swiftlint"),
            arguments: ["lint", path],
            workingDirectory: url
        )
        return result.stdout + result.stderr
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let path = arguments["path"] as? String else {
            throw AgentError.toolError("Missing path")
        }
        return try await run(path: path)
    }
}
