import Foundation

public struct CrashAnalyzerTool {
    public static let identifier = "crash_analyzer"

    public func run(logPath: String) async throws -> String {
        return "Analysis of crash log at \(logPath)"
    }
}
