import Foundation

public struct StopRunningProcessTool {
    public static let identifier = "stop_running_process"

    public func run(pid: Int32) async throws {
        kill(pid, SIGTERM)
    }
}
