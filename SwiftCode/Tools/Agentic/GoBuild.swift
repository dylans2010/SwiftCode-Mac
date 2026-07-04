import Foundation

public struct GoBuildTool {
    public static let identifier = "go_build"

    public func run(path: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/go"),
            arguments: ["build"],
            workingDirectory: URL(fileURLWithPath: path)
        )
        return result.stdout + result.stderr
    }
}
