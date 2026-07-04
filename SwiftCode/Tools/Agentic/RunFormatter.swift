import Foundation

public struct RunFormatterTool {
    public static let identifier = "run_formatter"

    public func run(path: String) async throws -> String {
        let url = URL(fileURLWithPath: path)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/swiftformat"),
            arguments: [path],
            workingDirectory: url
        )
        return result.stdout + result.stderr
    }
}
