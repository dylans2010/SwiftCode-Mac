import Foundation
import os

public actor SimulatorLoggingService {
    private var logsBuffer: [String] = []
    private let maxLines: Int
    private let logger = Logger(subsystem: "com.swiftcode.simulator", category: "LoggingService")

    public init(maxLines: Int = 1000) {
        self.maxLines = maxLines
    }

    public func log(_ message: String, type: OSLogType = .default) {
        let timestamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withTime, .withFractionalSeconds])
        let prefixed = "[\(timestamp)] \(message)"

        logsBuffer.append(prefixed)
        if logsBuffer.count > maxLines {
            logsBuffer.removeFirst()
        }

        switch type {
        case .error, .fault:
            logger.error("\(message)")
        case .info, .debug:
            logger.info("\(message)")
        default:
            logger.default("\(message)")
        }
    }

    public func getLogs() -> [String] {
        logsBuffer
    }

    public func clear() {
        logsBuffer.removeAll()
    }
}
