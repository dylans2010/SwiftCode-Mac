import Foundation

public struct SwiftPackageManagerTool {
    public static let identifier = "swift_package_manager"

    public func run(action: String, path: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["package", action],
            workingDirectory: URL(fileURLWithPath: path)
        )
        return result.stdout + result.stderr
    }
}
