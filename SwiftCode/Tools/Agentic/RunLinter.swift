import Foundation

public struct RunLinterTool {
    public static let identifier = "run_linter"

    public func run(path: String) async throws -> String {
        let url = URL(fileURLWithPath: path)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/swiftlint"),
            arguments: ["lint", path],
            workingDirectory: url
        )
        return result.stdout + result.stderr
    }
}
