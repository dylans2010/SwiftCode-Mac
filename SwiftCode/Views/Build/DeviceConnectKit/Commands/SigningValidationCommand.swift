import Foundation
import OSLog

public struct SigningValidationCommand {
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "SigningValidationCommand")

    public init() {}

    public func execute() async throws -> [String] {
        let securityURL = URL(fileURLWithPath: "/usr/bin/security")
        let res = try await ProcessRunnerTool.shared.run(
            executableURL: securityURL,
            arguments: ["find-identity", "-v", "-p", "codesigning"]
        )

        if res.exitCode == 0 {
            return res.stdout.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.contains("\"") }
        } else {
            return []
        }
    }
}
