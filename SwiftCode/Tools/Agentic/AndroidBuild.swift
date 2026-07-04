import Foundation

public struct AndroidBuildTool {
    public static let identifier = "android_build"

    public func run(path: String) async throws -> String {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/gradle"),
            arguments: ["assembleDebug"],
            workingDirectory: URL(fileURLWithPath: path)
        )
        return result.stdout + result.stderr
    }
}
