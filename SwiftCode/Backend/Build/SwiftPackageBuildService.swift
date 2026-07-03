import Foundation

public actor SwiftPackageBuildService {
    public static let shared = SwiftPackageBuildService()

    private let swiftURL = URL(fileURLWithPath: "/usr/bin/swift")

    public func build(packageURL: URL, onLog: @escaping @Sendable (String) -> Void) async throws -> Bool {
        let process = try ProcessRunnerTool.shared.runStreaming(
            executableURL: swiftURL,
            arguments: ["build"],
            workingDirectory: packageURL,
            onStdout: onLog,
            onStderr: onLog
        )

        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
