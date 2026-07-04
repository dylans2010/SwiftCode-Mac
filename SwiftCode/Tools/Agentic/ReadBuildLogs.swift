import Foundation

public struct ReadBuildLogsTool: AgentTool {
    public static let identifier = "read_build_logs"
    public let name = "read_build_logs"
    public let description = "Reads build logs from a project directory."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "projectPath": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["projectPath"]
    ]

    public func run(projectPath: String) async throws -> String {
        let url = URL(fileURLWithPath: projectPath).appendingPathComponent(".build/build.log")
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let projectPath = arguments["projectPath"] as? String else {
            throw AgentError.toolError("Missing projectPath")
        }
        return try await run(projectPath: projectPath)
    }
}
