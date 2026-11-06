import Foundation
import os

/// Authoritative event bus for all Assist Worker lifecycle, progress, and file activity events.
@MainActor
public final class WorkerEventBus: Sendable {
    public static let shared = WorkerEventBus()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerEventBus")
    private var subscribers: [(WorkerEvent) -> Void] = []
    /// Stream continuations, each with an optional worker filter (`nil` =
    /// unfiltered). Filtering happens at emit time so a filtered stream
    /// only ever sees its own worker's events.
    private var continuations: [UUID: (filter: UUID?, continuation: AsyncStream<WorkerEvent>.Continuation)] = [:]

    private init() {}

    /// Subscribes a closure to all Worker events
    public func subscribe(_ handler: @escaping (WorkerEvent) -> Void) {
        subscribers.append(handler)
    }

    /// Creates an AsyncStream for streaming events
    public func eventStream() -> AsyncStream<WorkerEvent> {
        makeStream(filter: nil)
    }

    /// Emits a structured Worker event across subscribers and streams.
    ///
    /// Legacy also forwarded every event to `DiagnosticEventBus`; that bus
    /// does not exist in this target, so emission here is the `os.Logger`
    /// line above plus subscribers and streams — nothing is silently
    /// dropped into a store that is not there.
    public func emit(_ event: WorkerEvent) {
        logger.info("[WorkerEvent] [\(event.type.rawValue)] \(event.title) - \(event.details)")

        for subscriber in subscribers {
            subscriber(event)
        }

        for (_, entry) in continuations {
            if let filter = entry.filter, filter != event.workerID { continue }
            entry.continuation.yield(event)
        }
    }

    /// Alias for emit — used by WorkerEngine for state transition events
    public func publish(_ event: WorkerEvent) {
        emit(event)
    }

    /// Creates a filtered stream for a specific worker ID.
    ///
    /// Correction vs Legacy: Legacy's `eventStream(for:)` created a stream
    /// but never filtered it, so it delivered every worker's events. This
    /// port applies the filter the method promises, at emit time.
    public func eventStream(for workerID: UUID) -> AsyncStream<WorkerEvent> {
        makeStream(filter: workerID)
    }

    private func makeStream(filter: UUID?) -> AsyncStream<WorkerEvent> {
        let streamID = UUID()
        return AsyncStream { continuation in
            continuations[streamID] = (filter: filter, continuation: continuation)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.continuations.removeValue(forKey: streamID)
                }
            }
        }
    }
}
