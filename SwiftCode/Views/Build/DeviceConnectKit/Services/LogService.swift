import Foundation

public struct LogService {
    public init() {}

    public func streamLogs(
        deviceUDID: String,
        pid: Int32,
        onLog: @escaping @Sendable (String) -> Void
    ) throws -> Process {
        return try RuntimeLogsCommand().execute(
            deviceUDID: deviceUDID,
            pid: pid,
            onLog: onLog
        )
    }
}
