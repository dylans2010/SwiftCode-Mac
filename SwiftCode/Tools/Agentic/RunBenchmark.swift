import Foundation

public struct RunBenchmarkTool {
    public static let identifier = "run_benchmark"

    public func run(projectPath: String) async throws -> String {
        let url = URL(fileURLWithPath: projectPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["run", "-c", "release", "benchmark"],
            workingDirectory: url
        )
        return result.stdout + result.stderr
    }
}
