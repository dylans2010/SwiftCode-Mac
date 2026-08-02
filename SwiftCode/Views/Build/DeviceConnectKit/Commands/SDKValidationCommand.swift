import Foundation
import OSLog

public struct SDKValidationCommand {
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "SDKValidationCommand")

    public init() {}

    public func execute() async throws -> [String] {
        let xcodebuildURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        let res = try await ProcessRunnerTool.shared.run(
            executableURL: xcodebuildURL,
            arguments: ["-showsdks"]
        )

        if res.exitCode == 0 {
            return res.stdout.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.hasPrefix("-") || $0.contains("SDK") }
        } else {
            return []
        }
    }
}
