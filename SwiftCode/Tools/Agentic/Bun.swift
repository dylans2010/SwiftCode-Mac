import Foundation

public struct BunTool {
    public static let identifier = "bun"

    public func run(action: String, path: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/bun"),
            arguments: [action],
            workingDirectory: URL(fileURLWithPath: path)
        )
        return result.stdout + result.stderr
    }
}
