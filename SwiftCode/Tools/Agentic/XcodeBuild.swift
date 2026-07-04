import Foundation

public struct XcodeBuildTool {
    public static let identifier = "xcode_build"

    public func run(projectPath: String, scheme: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
            arguments: ["-project", projectPath, "-scheme", scheme, "build"]
        )
        return result.stdout + result.stderr
    }
}
