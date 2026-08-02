import Foundation
import OSLog

public struct BuildProjectCommand {
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "BuildProjectCommand")

    public init() {}

    public func execute(
        projectPath: String,
        scheme: String,
        configuration: String = "Debug",
        destination: String,
        onLog: @escaping @Sendable (String) -> Void
    ) async throws -> Bool {
        let xcodebuildURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")

        let args = [
            "-project", projectPath,
            "-scheme", scheme,
            "-configuration", configuration,
            "-destination", destination,
            "build"
        ]

        Self.logger.info("Starting xcodebuild with arguments: \(args.joined(separator: " "))")

        do {
            let success = try await ProcessRunnerTool.shared.runStreamingAsync(
                executableURL: xcodebuildURL,
                arguments: args,
                onStdout: { line in
                    onLog(line)
                },
                onStderr: { errorLine in
                    onLog("[stderr] " + errorLine)
                }
            )
            return success
        } catch {
            Self.logger.error("xcodebuild failed to start: \(error.localizedDescription)")
            onLog("Error starting build: \(error.localizedDescription)")
            return false
        }
    }
}
