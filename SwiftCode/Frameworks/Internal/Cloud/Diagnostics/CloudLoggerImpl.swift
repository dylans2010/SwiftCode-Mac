import Foundation
import os.log

public final class CloudLoggerImpl: CloudLogger, @unchecked Sendable {
    public static let shared = CloudLoggerImpl()

    private let systemLogger = Logger(subsystem: "com.SwiftCode.Cloud", category: "Framework")
    private var logs: [CloudLogEntry] = []

    private init() {}

    public func log(level: CloudLogLevel, message: String, subsystem: String) {
        let entry = CloudLogEntry(subsystem: subsystem, level: level, message: message)
        logs.append(entry)

        switch level {
        case .info:
            systemLogger.info("[\(subsystem)] \(message)")
        case .warning:
            systemLogger.warning("[\(subsystem)] \(message)")
        case .error:
            systemLogger.error("[\(subsystem)] \(message)")
        case .performance:
            systemLogger.debug("[Performance] [\(subsystem)] \(message)")
        }
    }

    public func fetchLogs() -> [CloudLogEntry] {
        return logs
    }

    public func clearLogs() {
        logs.removeAll()
    }
}
