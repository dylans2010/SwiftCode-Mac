import Foundation

public struct AndroidBuildTool: AgentTool {
    public static let identifier = "android_build"
    public let name = "android_build"
    public let description = "Builds an Android project."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "path": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["path"]
    ]

    public func run(path: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/gradle"),
            arguments: ["assembleDebug"],
            workingDirectory: URL(fileURLWithPath: path)
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
