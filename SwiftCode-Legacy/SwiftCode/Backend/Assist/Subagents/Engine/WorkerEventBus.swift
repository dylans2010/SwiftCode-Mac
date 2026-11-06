import Foundation
import os

/// Authoritative event bus for all Assist Worker lifecycle, progress, and file activity events.
@MainActor
public final class WorkerEventBus: Sendable {
    public static let shared = WorkerEventBus()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerEventBus")
    private var subscribers: [(WorkerEvent) -> Void] = []
    private var continuations: [UUID: AsyncStream<WorkerEvent>.Continuation] = [:]

    private init() {}

    /// Subscribes a closure to all Worker events
    public func subscribe(_ handler: @escaping (WorkerEvent) -> Void) {
        subscribers.append(handler)
    }

    /// Creates an AsyncStream for streaming events
    public func eventStream() -> AsyncStream<WorkerEvent> {
        let streamID = UUID()
        return AsyncStream { continuation in
            continuations[streamID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.continuations.removeValue(forKey: streamID)
                }
            }
        }
    }

    /// Emits a structured Worker event across subscribers, streams, and diagnostic telemetry
    public func emit(_ event: WorkerEvent) {
        logger.info("[WorkerEvent] [\(event.type.rawValue)] \(event.title) - \(event.details)")

        DiagnosticEventBus.shared.logEvent(
            component: "WorkerEventBus",
            severity: event.type == .workerFailed ? "ERROR" : "INFO",
            category: "worker_event",
            message: "[\(event.type.rawValue)] \(event.title): \(event.details)"
        )

        for subscriber in subscribers {
            subscriber(event)
        }

        for (_, continuation) in continuations {
            continuation.yield(event)
        }
    }

    /// Alias for emit — used by WorkerEngine for state transition events
    public func publish(_ event: WorkerEvent) {
        emit(event)
    }

    /// Creates a filtered stream for a specific worker ID
    public func eventStream(for workerID: UUID) -> AsyncStream<WorkerEvent> {
        let streamID = UUID()
        return AsyncStream { continuation in
            continuations[streamID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.continuations.removeValue(forKey: streamID)
                }
            }
        }
    }
}
