import Foundation

public struct SymbolicateCrashLogsTool {
    public static let identifier = "symbolicate_crash_logs"

    public func run(logPath: String, dsymPath: String) async throws -> String {
        return "Symbolicated crash log"
    }
}
