import Foundation

public actor SwiftPackageBuildService {
    public static let shared = SwiftPackageBuildService()

    private var swiftURL: URL {
        get async {
            if let customPath: String = await PreferencesStore.shared.get(forKey: "swift_executable_path") {
                return URL(fileURLWithPath: customPath)
            }
            return URL(fileURLWithPath: "/usr/bin/swift")
        }
    }

    public func build(packageURL: URL, onLog: @escaping @Sendable (String) -> Void) async throws -> Bool {
        return try await ProcessRunnerTool.shared.runStreamingAsync(
            executableURL: await swiftURL,
            arguments: ["build"],
            workingDirectory: packageURL,
            onStdout: onLog,
            onStderr: onLog
        )
    }
}
