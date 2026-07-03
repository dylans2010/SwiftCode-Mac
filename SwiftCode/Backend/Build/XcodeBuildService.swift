import Foundation

public actor XcodeBuildService {
    public static let shared = XcodeBuildService()

    private let xcodebuildURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")

    public func build(projectURL: URL, scheme: String, configuration: BuildConfiguration, onLog: @escaping @Sendable (String) -> Void) async throws -> Bool {
        let process = try ProcessRunnerTool.shared.runStreaming(
            executableURL: xcodebuildURL,
            arguments: [
                "-project", projectURL.path,
                "-scheme", scheme,
                "-configuration", configuration.rawValue,
                "build"
            ],
            onStdout: onLog,
            onStderr: onLog
        )

        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
