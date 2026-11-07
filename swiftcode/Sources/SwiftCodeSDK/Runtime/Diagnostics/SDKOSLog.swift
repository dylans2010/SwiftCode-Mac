import Foundation
#if canImport(os)
import os
#endif

public enum SDKLog {
    public static func info(_ message: String, subsystem: String = "com.swiftcode.sdk", category: String = "sdk") {
        log(level: .info, message, subsystem: subsystem, category: category)
    }

    public static func debug(_ message: String, subsystem: String = "com.swiftcode.sdk", category: String = "sdk") {
        log(level: .debug, message, subsystem: subsystem, category: category)
    }

    public static func error(_ message: String, subsystem: String = "com.swiftcode.sdk", category: String = "sdk") {
        log(level: .error, message, subsystem: subsystem, category: category)
    }

    private enum Level { case info, debug, error }

    private static func log(level: Level, _ message: String, subsystem: String, category: String) {
        #if canImport(os)
        let logger = Logger(subsystem: subsystem, category: category)
        switch level {
        case .info: logger.info("\(message, privacy: .public)")
        case .debug: logger.debug("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
        #else
        let prefix: String
        switch level {
        case .info: prefix = "INFO"
        case .debug: prefix = "DEBUG"
        case .error: prefix = "ERROR"
        }
        let line = "[\(subsystem):\(category)] \(prefix): \(message)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
        #endif
    }
}
