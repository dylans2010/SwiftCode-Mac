import Foundation

public struct RunApplicationTool {
    public static let identifier = "run_application"

    public func run(projectPath: String, target: String) async throws -> String {
        let url = URL(fileURLWithPath: projectPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["run", target],
            workingDirectory: url
        )
        return result.stdout + result.stderr
    }
}
