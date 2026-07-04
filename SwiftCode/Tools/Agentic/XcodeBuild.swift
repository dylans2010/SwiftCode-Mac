import Foundation

public struct XcodeBuildTool: AgentTool {
    public static let identifier = "xcode_build"
    public let name = "xcode_build"
    public let description = "Executes xcodebuild to build a project."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "projectPath": ["type": "string"],
            "scheme": ["type": "string"]
        ],
        "required": ["projectPath", "scheme"]
    ]

    public func run(projectPath: String, scheme: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
            arguments: ["-project", projectPath, "-scheme", scheme, "build"]
        )
        return result.stdout + result.stderr
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let path = arguments["projectPath"] as? String,
              let scheme = arguments["scheme"] as? String else {
            throw AgentError.toolError("Missing projectPath or scheme")
        }
        return try await run(projectPath: path, scheme: scheme)
    }
}
