import Foundation

public struct InstallDependenciesTool {
    public static let identifier = "install_dependencies"

    public func run(projectPath: String) async throws -> String {
        let url = URL(fileURLWithPath: projectPath)
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["package", "resolve"],
            workingDirectory: url
        )
        return result.stdout + result.stderr
    }
}
