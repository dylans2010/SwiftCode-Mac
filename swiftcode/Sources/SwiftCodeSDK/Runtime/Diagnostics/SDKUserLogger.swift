import Foundation
import os

// MARK: - SDKUserLogger
//
// Ported from Legacy `SwiftCode/SDK/Runtime/Diagnostics/SDKUserLogger.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// The user-facing log: short, sanitized entries the host UI can show.
// Ring buffer, max 200 entries. Messages are sanitized through
// `SDKLogRedaction` — secrets never reach the user log.

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

/// User-facing log (ring buffer, max 200 entries). Thread-safe.
public final class SDKUserLogger: @unchecked Sendable {
    public static let shared = SDKUserLogger()

    public static let maxEntries = 200

    private let lock = NSLock()
    private var entries: [SDKUserLogEntry] = []

    private init() {}

    /// Logs an `SDKError` as an error entry (user-safe message only).
    public func log(_ error: SDKError, title: String? = nil) {
        append(level: .error, title: title ?? error.code.userFacingTitle, message: error.message, correlationId: error.correlationId)
    }

    /// Logs a generic error with a sanitized message.
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

    /// The most recent `limit` entries, oldest first.
    public func recentEntries(limit: Int) -> [SDKUserLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return Array(entries.suffix(max(0, limit)))
    }

    /// Entries whose title or message contains `query` (case-insensitive).
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


// Ported from Legacy `SwiftCode/SDK/Runtime/Diagnostics/SDKUserLogger.swift` (Audit E §5 partial entry; H-E5).
// Types ported here: RingBuffer.

/// Lock-guarded fixed-capacity buffer. Kept in a dedicated `@unchecked
/// Sendable` box so `SDKUserLogger` itself can conform to `Sendable` with
/// only immutable (`let`) stored properties under Swift 6 strict concurrency.
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
