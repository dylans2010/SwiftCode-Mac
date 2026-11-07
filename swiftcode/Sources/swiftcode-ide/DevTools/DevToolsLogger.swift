import Foundation
#if canImport(os)
import os
#endif

struct DevToolsLogger {
    private let subsystem: String
    private let category: String

    init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
    }

    func info(_ message: String) { log(level: "INFO", message) }
    func debug(_ message: String) { log(level: "DEBUG", message) }
    func warning(_ message: String) { log(level: "WARNING", message) }
    func error(_ message: String) { log(level: "ERROR", message) }

    private func log(level: String, _ message: String) {
        #if canImport(os)
        Logger(subsystem: subsystem, category: category).info("\(level): \(message)")
        #else
        FileHandle.standardError.write(Data("[\(subsystem):\(category)] \(level): \(message)\n".utf8))
        #endif
    }
}
