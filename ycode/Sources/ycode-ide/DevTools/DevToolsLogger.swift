import Foundation
#if canImport(os)
import os
#endif

/// Cross-platform logging shim for the ported developer tools.
///
/// Legacy used `os.Logger` throughout (`import os.log`), which is
/// Darwin-only. Ycode targets macOS and Linux, and no Ycode file uses
/// `import os`. On Apple platforms this forwards to `os.Logger` with the
/// same subsystem/category discipline; elsewhere it writes to stderr so
/// diagnostics are never silently dropped. (Same pattern as
/// `YcodeSDK/Runtime/Diagnostics/SDKOSLog.swift`.)
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
