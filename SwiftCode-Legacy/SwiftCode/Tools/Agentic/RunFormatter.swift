import Foundation

public struct RunFormatterTool: AgentTool {
    public static let identifier = "run_formatter"
    public let name = "run_formatter"
    public let description = "Runs a formatter (SwiftFormat) on a given path."
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
            executableURL: URL(fileURLWithPath: "/usr/bin/swiftformat"),
            arguments: [path],
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
