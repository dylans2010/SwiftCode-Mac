//  SDKToolEventStore.swift
//  SwiftCode
//
//  Observable store for provider tool events.
//
//  Design choice: one dictionary keyed by sessionId, each value an array
//  in first-seen order. A single current-session array would have forced
//  the parent to drop or stash other sessions' rows whenever the user
//  switched conversations; the dictionary keeps every live session's
//  rows intact and lets a view snapshot exactly one session.
//
//  Workstreams A and B publish into this store (from non-isolated
//  contexts, `await store.apply(event)`); the OR/OC views render a
//  snapshot passed in by the parent (`store.events(for: sessionId)`).
//  The store is intentionally dependency-free: it imports nothing from
//  any provider, so no provider change can break it, and the views never
//  observe a provider client directly.
//
//  Merge and ordering guarantees live in `SDKToolEvent.updating(with:)`
//  and are preserved here: `apply` replaces the row in place, so the
//  first-seen order never changes and a duplicate `toolCallId` never
//  produces a second row.

import Foundation

/// Main-actor store of tool-call rows, one list per session.
@MainActor
@Observable
public final class SDKToolEventStore {
    public static let shared = SDKToolEventStore()

    /// Rows per session, in first-seen order. Private: readers go through
    /// `events(for:)` so a snapshot, not the storage, is what views hold.
    private var eventsBySession: [String: [SDKToolEvent]] = [:]

    public init() {}

    /// Merges `event` into its session's rows. A first-seen `toolCallId`
    /// appends a row; a known one replaces its row with the merged event
    /// (see `SDKToolEvent.updating(with:)` for the state rules). Row
    /// order is first-seen order and never changes on merge.
    public func apply(_ event: SDKToolEvent) {
        var rows = eventsBySession[event.sessionId, default: []]
        // Merge key is toolCallId + source: in combined mode a
        // SwiftCode tool and a provider tool could share an id, and
        // merging on id alone would fuse two different calls.
        if let index = rows.firstIndex(where: { $0.toolCallId == event.toolCallId && $0.source == event.source }) {
            rows[index] = rows[index].updating(with: event)
        } else {
            rows.append(event)
        }
        eventsBySession[event.sessionId] = rows
    }

    /// Marks every non-terminal row in a session as cancelled.
    /// Cancellation previously left in-flight rows in `running`
    /// forever (OpenCode emitted no cancelled event; OpenRouter
    /// emitted `failed`), so a cancelled run looked either stuck or
    /// like a tool failure. Callers invoke this when a run is
    /// cancelled; bridge-side cancelled events, when they arrive,
    /// merge into the same rows.
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

    /// Snapshot of one session's rows, in first-seen order. Empty when
    /// the session has no rows yet. Views render this snapshot; they do
    /// not read the store themselves, so rendering can never block on
    /// store work and the parent controls exactly when a snapshot refreshes.
    public func events(for sessionId: String) -> [SDKToolEvent] {
        eventsBySession[sessionId, default: []]
    }

    /// Drops one session's rows (session closed, provider switched, or
    /// conversation cleared). Other sessions are untouched.
    public func reset(sessionId: String) {
        eventsBySession[sessionId] = nil
    }

    /// Drops every session's rows.
    public func resetAll() {
        eventsBySession.removeAll()
    }
}
