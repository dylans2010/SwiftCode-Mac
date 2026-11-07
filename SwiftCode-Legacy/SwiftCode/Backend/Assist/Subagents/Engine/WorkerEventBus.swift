import Foundation
import os

@MainActor
public final class WorkerEventBus: Sendable {
    public static let shared = WorkerEventBus()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerEventBus")
    private var subscribers: [(WorkerEvent) -> Void] = []
    private var continuations: [UUID: AsyncStream<WorkerEvent>.Continuation] = [:]

    private init() {}

    public func subscribe(_ handler: @escaping (WorkerEvent) -> Void) {
        subscribers.append(handler)
    }

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

    public func publish(_ event: WorkerEvent) {
        emit(event)
    }

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
