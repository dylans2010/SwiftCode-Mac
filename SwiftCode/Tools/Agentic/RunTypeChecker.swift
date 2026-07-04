import Foundation

public struct RunTypeCheckerTool {
    public static let identifier = "run_type_checker"

    public func run(projectPath: String) async throws -> String {
        let url = URL(fileURLWithPath: projectPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["build", "--build-tests"],
            workingDirectory: url
        )
        return result.stdout + result.stderr
    }
}
