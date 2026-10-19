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

        let derivedData = URL(fileURLWithPath: projectPath).deletingLastPathComponent().appendingPathComponent("build/DerivedData").path
        var args = [
            "-project", projectPath,
            "-scheme", scheme,
            "-configuration", configuration,
            "-destination", destination,
            "-derivedDataPath", derivedData,
            "build"
        ]

        if destination.lowercased().contains("simulator") || destination.hasPrefix("id=") {
            args.append(contentsOf: [
                "CODE_SIGN_IDENTITY=",
                "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGNING_ALLOWED=NO"
            ])
        }

        if let activeProj = await ProjectSessionStore.shared.activeProject,
           let savedDests = activeProj.destinations,
           let firstSDK = savedDests.first {
            args.append(contentsOf: ["-sdk", firstSDK])
        }

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
