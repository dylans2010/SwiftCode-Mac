import Foundation

public struct OpenBrowserTool: AgentTool {
    public static let identifier = "open_browser"
    public let name = "open_browser"
    public let description = "Opens a URL in the default browser."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "url": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["url"]
    ]

    public func run(url: String) async throws {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: [url]
        )
        if result.exitCode != 0 { throw AppError.commonError(result.stderr) }
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let url = arguments["url"] as? String else {
            throw AgentError.toolError("Missing url")
        }
        try await run(url: url)
        return "Opened \(url)"
    }
}
