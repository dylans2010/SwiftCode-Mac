import Foundation

public struct ReadBuildLogsTool {
    public static let identifier = "read_build_logs"

    public func run(projectPath: String) async throws -> String {
        let url = URL(fileURLWithPath: projectPath).appendingPathComponent(".build/build.log")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
