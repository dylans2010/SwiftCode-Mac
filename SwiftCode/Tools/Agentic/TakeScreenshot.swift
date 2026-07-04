import Foundation

public struct TakeScreenshotTool: AgentTool {
    public static let identifier = "take_screenshot"
    public let name = "take_screenshot"
    public let description = "Takes a screenshot and saves it to a path."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "path": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["path"]
    ]

    public func run(path: String) async throws {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/sbin/screencapture"),
            arguments: [path]
        )
        if result.exitCode != 0 { throw AppError.commonError(result.stderr) }
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let path = arguments["path"] as? String else {
            throw AgentError.toolError("Missing path")
        }
        try await run(path: path)
        return "Screenshot saved to \(path)"
    }
}
