import Foundation

public struct TakeScreenshotTool {
    public static let identifier = "take_screenshot"

    public func run(path: String) async throws {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/sbin/screencapture"),
            arguments: [path]
        )
        if result.exitCode != 0 { throw AppError.commonError(result.stderr) }
    }
}
