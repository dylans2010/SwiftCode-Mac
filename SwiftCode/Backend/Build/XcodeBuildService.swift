import Foundation

public actor XcodeBuildService {
    public static let shared = XcodeBuildService()

    private var xcodebuildURL: URL {
        get async {
            if let customPath = await PreferencesStore.shared.get(forKey: "xcodebuild_executable_path") as? String {
                return URL(fileURLWithPath: customPath)
            }
            return URL(fileURLWithPath: "/usr/bin/xcodebuild")
        }
    }

    public func build(projectURL: URL, scheme: String, configuration: BuildConfiguration, onLog: @escaping @Sendable (String) -> Void) async throws -> Bool {
        return try await ProcessRunnerTool.shared.runStreamingAsync(
            executableURL: await xcodebuildURL,
            arguments: [
                "-project", projectURL.path,
                "-scheme", scheme,
                "-configuration", configuration.rawValue,
                "build"
            ],
            onStdout: onLog,
            onStderr: onLog
        )
    }
}
