import Foundation
import os

// MARK: - SDKUserLogLevel

/// Severity of a user-facing log entry. Rendered in the Activity Console
/// and Studio notification popovers.
public enum SDKUserLogLevel: String, Sendable, Codable, CaseIterable {
    case info
    case warning
    case error
}

// MARK: - SDKUserLogEntry

/// One sanitized, user-safe log entry. Never contains stack traces, memory
/// addresses, absolute filesystem paths, or secret material — see
/// `SDKLogRedaction.sanitizeForUser(_:)`.
public struct SDKUserLogEntry: Sendable, Codable {
    public let timestamp: Date
    public let level: SDKUserLogLevel
    public let title: String
    public let message: String
    /// The `ERR-XXXXXX` correlation ID shared with the developer log, so a
    /// user can quote it in a support ticket and an engineer can pull the
    /// matching verbose entry via `SDKDeveloperLogger.fetchEntries`.
    /// Empty for informational entries that are not tied to an error event.
    public let correlationId: String

    public init(
        timestamp: Date = Date(),
        level: SDKUserLogLevel,
        title: String,
        message: String,
        correlationId: String
    ) {
        self.timestamp = timestamp
        self.level = level
        self.title = title
        self.message = message
        self.correlationId = correlationId
    }
}

// MARK: - SDKUserLogger
//
// User-facing, sanitized logging pipeline (spec §16.1).
//
// Every message that reaches this logger is run through
// `SDKLogRedaction.sanitizeForUser(_:)` before it is buffered or emitted:
// stack-trace-looking lines are dropped, memory addresses and absolute
// filesystem paths are masked, and secret-looking tokens are redacted.
//
// Entries are kept in an in-memory ring buffer (last 200) for UI surfaces
// (workspace status bar, Activity Console, Studio popovers) and mirrored to
// the unified log via `os_log` (subsystem `com.swiftcode.sdk`, category
// `sdk-user`).
//
// RULE: never pass a raw underlying service error's `localizedDescription`
// (or `String(describing:)` output) to the UI or `os_log` without
// sanitizing. Use `log(error:title:correlationId:)`, which sanitizes for you.

public final class SDKUserLogger: Sendable {
    public static let shared = SDKUserLogger()

    /// Maximum entries retained in the in-memory ring buffer.
    public static let maxBufferedEntries = 200

    private let logger = Logger(subsystem: "com.swiftcode.sdk", category: "sdk-user")
    private let buffer = RingBuffer()

    private init() {}

    // MARK: - Logging

    /// Logs a typed SDK error. The title, message, and suggestion come from
    /// `SDKError`'s user-safe fields, and the whole rendering is sanitized
    /// once more as defense in depth.
    public func log(_ error: SDKError) {
        var rendered = error.userFacingDescription
        if let suggestion = error.suggestion, !suggestion.isEmpty {
            rendered += "\n\(suggestion)"
        }
        let entry = SDKUserLogEntry(
            timestamp: error.timestamp,
            level: .error,
            title: error.code.userFacingTitle,
            message: SDKLogRedaction.sanitizeForUser(rendered),
            correlationId: error.correlationId
        )
        record(entry)
        logger.error("\(entry.title, privacy: .public) [\(entry.correlationId, privacy: .public)]: \(entry.message, privacy: .public)")
    }

    /// Logs a raw underlying error (network stack, Process output, decoding
    /// failure, …). The error's text is ALWAYS sanitized before buffering or
    /// emission — callers must not pre-sanitize or, worse, log it raw.
    public func log(error: Error, title: String, correlationId: String? = nil) {
        let rawText: String
        if let localized = (error as? LocalizedError)?.errorDescription {
            rawText = localized
        } else {
            rawText = String(describing: error)
        }
        let entry = SDKUserLogEntry(
            level: .error,
            title: title,
            message: SDKLogRedaction.sanitizeForUser(rawText),
            correlationId: correlationId ?? SDKError.newCorrelationId()
        )
        record(entry)
        logger.error("\(entry.title, privacy: .public) [\(entry.correlationId, privacy: .public)]: \(entry.message, privacy: .public)")
    }

    /// Logs an informational message (already user-safe phrasing expected;
    /// still sanitized as defense in depth).
    public func logInfo(_ message: String, correlationId: String? = nil) {
        emit(level: .info, title: "Info", message: message, correlationId: correlationId)
    }

    /// Logs a warning message (already user-safe phrasing expected; still
    /// sanitized as defense in depth).
    public func logWarning(_ message: String, correlationId: String? = nil) {
        emit(level: .warning, title: "Warning", message: message, correlationId: correlationId)
    }

    // MARK: - Reading

    /// Newest-first snapshot of buffered entries for UI surfaces.
    public func recentEntries(limit: Int? = nil) -> [SDKUserLogEntry] {
        let entries = buffer.snapshot().reversed()
        if let limit {
            return Array(entries.prefix(limit))
        }
        return Array(entries)
    }

    /// All buffered entries carrying the given `ERR-XXXXXX` correlation ID,
    /// newest first. Lets UI surfaces link a user-visible error to its
    /// developer-log counterpart.
    public func entries(matching correlationId: String) -> [SDKUserLogEntry] {
        buffer.snapshot().reversed().filter { $0.correlationId == correlationId }
    }

    /// Drops all buffered entries.
    public func clear() {
        buffer.removeAll()
    }

    // MARK: - Private

    private func emit(
        level: SDKUserLogLevel,
        title: String,
        message: String,
        correlationId: String?
    ) {
        let entry = SDKUserLogEntry(
            level: level,
            title: title,
            message: SDKLogRedaction.sanitizeForUser(message),
            correlationId: correlationId ?? ""
        )
        record(entry)
        switch level {
        case .info:
            if entry.correlationId.isEmpty {
                logger.info("\(entry.message, privacy: .public)")
            } else {
                logger.info("[\(entry.correlationId, privacy: .public)] \(entry.message, privacy: .public)")
            }
        case .warning:
            if entry.correlationId.isEmpty {
                logger.warning("\(entry.message, privacy: .public)")
            } else {
                logger.warning("[\(entry.correlationId, privacy: .public)] \(entry.message, privacy: .public)")
            }
        case .error:
            // Errors go through log(_:)/log(error:title:) instead.
            break
        }
    }

    private func record(_ entry: SDKUserLogEntry) {
        buffer.append(entry)
    }
}

// MARK: - RingBuffer (private)

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
