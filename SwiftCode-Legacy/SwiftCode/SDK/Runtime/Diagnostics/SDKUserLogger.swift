import Foundation
import os

public enum SDKUserLogLevel: String, Sendable, Codable, CaseIterable {
    case info
    case warning
    case error
}

public struct SDKUserLogEntry: Sendable, Codable {
    public let timestamp: Date
    public let level: SDKUserLogLevel
    public let title: String
    public let message: String
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

public final class SDKUserLogger: Sendable {
    public static let shared = SDKUserLogger()

    public static let maxBufferedEntries = 200

    private let logger = Logger(subsystem: "com.swiftcode.sdk", category: "sdk-user")
    private let buffer = RingBuffer()

    private init() {}

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

    public func logInfo(_ message: String, correlationId: String? = nil) {
        emit(level: .info, title: "Info", message: message, correlationId: correlationId)
    }

    public func logWarning(_ message: String, correlationId: String? = nil) {
        emit(level: .warning, title: "Warning", message: message, correlationId: correlationId)
    }

    public func recentEntries(limit: Int? = nil) -> [SDKUserLogEntry] {
        let entries = buffer.snapshot().reversed()
        if let limit {
            return Array(entries.prefix(limit))
        }
        return Array(entries)
    }

    public func entries(matching correlationId: String) -> [SDKUserLogEntry] {
        buffer.snapshot().reversed().filter { $0.correlationId == correlationId }
    }

    public func clear() {
        buffer.removeAll()
    }

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
            break
        }
    }

    private func record(_ entry: SDKUserLogEntry) {
        buffer.append(entry)
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
