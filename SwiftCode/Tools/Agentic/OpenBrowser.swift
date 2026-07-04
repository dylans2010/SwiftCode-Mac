import Foundation

public struct OpenBrowserTool {
    public static let identifier = "open_browser"

    public func run(url: String) async throws {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: [url]
        )
        if result.exitCode != 0 { throw AppError.commonError(result.stderr) }
    }
}
