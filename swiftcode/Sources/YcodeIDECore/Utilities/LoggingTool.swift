import Foundation
import os.log

public enum LoggingTool {
    private static let logger = Logger(subsystem: "com.swiftcode.app", category: "General")

    public static func info(_ message: String) {
        logger.info("\(message)")
    }

    public static func error(_ message: String) {
        logger.error("\(message)")
    }

    public static func debug(_ message: String) {
        logger.debug("\(message)")
    }
}
