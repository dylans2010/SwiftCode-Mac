import Foundation
import OSLog

public struct DeveloperDirectoryCommand {
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "DeveloperDirectoryCommand")

    public init() {}

    public func execute() async throws -> String {
        let xcodeSelectURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        let res = try await ProcessRunnerTool.shared.run(
            executableURL: xcodeSelectURL,
            arguments: ["-p"]
        )
        if res.exitCode == 0 {
            return res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw NSError(domain: "com.swiftcode.deviceconnect", code: Int(res.exitCode), userInfo: [NSLocalizedDescriptionKey: res.stderr])
        }
    }
}
