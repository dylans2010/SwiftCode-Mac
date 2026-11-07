import Foundation

@MainActor
@Observable
public final class SDKToolEventStore {
    public static let shared = SDKToolEventStore()

    private var eventsBySession: [String: [SDKToolEvent]] = [:]

    public init() {}

    public func apply(_ event: SDKToolEvent) {
        var rows = eventsBySession[event.sessionId, default: []]
        if let index = rows.firstIndex(where: { $0.toolCallId == event.toolCallId && $0.source == event.source }) {
            rows[index] = rows[index].updating(with: event)
        } else {
            rows.append(event)
        }
        eventsBySession[event.sessionId] = rows
    }

    public func cancelNonTerminal(sessionId: String) {
        guard var rows = eventsBySession[sessionId] else { return }
        for index in rows.indices {
            switch rows[index].state {
            case .requested, .running:
                rows[index] = rows[index].updating(with: SDKToolEvent(
                    provider: rows[index].provider,
                    sessionId: sessionId,
                    toolCallId: rows[index].toolCallId,
                    toolName: rows[index].toolName,
                    source: rows[index].source,
                    state: .cancelled,
                    arguments: rows[index].arguments,
                    error: "Cancelled"
                ))
            case .completed, .failed, .cancelled:
                break
            }
        }
        eventsBySession[sessionId] = rows
    }

    public func events(for sessionId: String) -> [SDKToolEvent] {
        eventsBySession[sessionId, default: []]
    }

    public func reset(sessionId: String) {
        eventsBySession[sessionId] = nil
    }

    public func resetAll() {
        eventsBySession.removeAll()
    }
}
