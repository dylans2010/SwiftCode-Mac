import Foundation
import os

public enum SDKUserLogLevel: String, Sendable, Codable {
    case info
    case warning
    case error
}

public struct SDKUserLogEntry: Sendable, Equatable {
    public let timestamp: Date
    public let level: SDKUserLogLevel
    public let title: String
    public let message: String
    public let correlationId: String?

    public init(timestamp: Date = Date(), level: SDKUserLogLevel, title: String, message: String, correlationId: String? = nil) {
        self.timestamp = timestamp
        self.level = level
        self.title = title
        self.message = message
        self.correlationId = correlationId
    }
}

public final class SDKUserLogger: @unchecked Sendable {
    public static let shared = SDKUserLogger()

    public static let maxEntries = 200

    private let lock = NSLock()
    private var entries: [SDKUserLogEntry] = []

    private init() {}

    public func log(_ error: SDKError, title: String? = nil) {
        append(level: .error, title: title ?? error.code.userFacingTitle, message: error.message, correlationId: error.correlationId)
    }

    public func log(error: Error, title: String, correlationId: String? = nil) {
        let message = (error as? SDKError)?.message ?? error.localizedDescription
        append(level: .error, title: title, message: message, correlationId: correlationId)
    }

    public func logInfo(_ message: String, title: String, correlationId: String? = nil) {
        append(level: .info, title: title, message: message, correlationId: correlationId)
    }

    public func logWarning(_ message: String, title: String, correlationId: String? = nil) {
        append(level: .warning, title: title, message: message, correlationId: correlationId)
    }

    public func logError(_ message: String, title: String, correlationId: String? = nil) {
        append(level: .error, title: title, message: message, correlationId: correlationId)
    }

    public func recentEntries(limit: Int) -> [SDKUserLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return Array(entries.suffix(max(0, limit)))
    }

    public func entries(matching query: String) -> [SDKUserLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        let lowered = query.lowercased()
        return entries.filter { $0.title.lowercased().contains(lowered) || $0.message.lowercased().contains(lowered) }
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries = []
    }

    private func append(level: SDKUserLogLevel, title: String, message: String, correlationId: String?) {
        let entry = SDKUserLogEntry(
            level: level,
            title: title,
            message: SDKLogRedaction.sanitizeForUser(message),
            correlationId: correlationId
        )
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        switch level {
        case .info:
            SDKLog.info("[\(title)] \(entry.message)", subsystem: "com.swiftcode.sdk", category: "sdk-user")
        case .warning:
            SDKLog.info("[\(title)] \(entry.message)", subsystem: "com.swiftcode.sdk", category: "sdk-user")
        case .error:
            SDKLog.error("[\(title)] \(entry.message)", subsystem: "com.swiftcode.sdk", category: "sdk-user")
        }
    }
}

private final class RingBuffer: @unchecked Sendable {
    private var entries: [SDKUserLogEntry] = []
    private let lock = NSLock()

    func append(_ entry: SDKUserLogEntry) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
        if entries.count > SDKUserLogger.maxBufferedEntries {
            entries.removeFirst(entries.count - SDKUserLogger.maxBufferedEntries)
        }
    }

    func snapshot() -> [SDKUserLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}
