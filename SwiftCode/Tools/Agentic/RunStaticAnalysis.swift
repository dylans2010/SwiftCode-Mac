import Foundation

public struct RunStaticAnalysisTool {
    public static let identifier = "run_static_analysis"

    public func run(projectPath: String) async throws -> String {
        let url = URL(fileURLWithPath: projectPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["build", "--build-tests", "-Xswiftc", "-analyze"],
            workingDirectory: url
        )
        return result.stdout + result.stderr
    }
}
