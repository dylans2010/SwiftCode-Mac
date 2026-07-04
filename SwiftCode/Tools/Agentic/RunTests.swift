import Foundation

public struct RunTestsTool {
    public static let identifier = "run_tests"

    public func run(projectPath: String) async throws -> String {
        let url = URL(fileURLWithPath: projectPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["test"],
            workingDirectory: url
        )
        return result.stdout + result.stderr
    }
}
