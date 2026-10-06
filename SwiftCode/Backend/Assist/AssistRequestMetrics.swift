//
//  AssistRequestMetrics.swift
//  SwiftCode
//
//  High-resolution request lifecycle metrics and performance telemetry for Assist.
//

import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.Assist", category: "Metrics")

public enum MetricCheckpoint: Sendable {
    case sessionResolved
    case modelResolved
    case requestCreated
    case requestSent
    case modelStarted
    case firstEventReceived
    case firstReasoningDelta
    case firstTextDelta
    case firstToolCall
    case responseCompleted
}

/// Captures fine-grained timestamps throughout the Assist request lifecycle to measure
/// and eliminate bottlenecks between user submission and visible model output.
public final class AssistRequestMetrics: Identifiable, @unchecked Sendable {
    public let id: UUID
    public let messageSubmitted: Date
    public var sessionResolved: Date?
    public var modelResolved: Date?
    public var requestCreated: Date?
    public var requestSent: Date?
    public var modelStarted: Date?
    public var firstEventReceived: Date?
    public var firstReasoningDelta: Date?
    public var firstTextDelta: Date?
    public var firstToolCall: Date?
    public var responseCompleted: Date?

    private let lock = NSLock()

    public init(id: UUID = UUID(), messageSubmitted: Date = Date()) {
        self.id = id
        self.messageSubmitted = messageSubmitted
    }

    public static func start(prompt: String = "") -> AssistRequestMetrics {
        AssistRequestMetrics(messageSubmitted: Date())
    }

    public func mark(_ checkpoint: MetricCheckpoint) {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        switch checkpoint {
        case .sessionResolved: if sessionResolved == nil { sessionResolved = now }
        case .modelResolved: if modelResolved == nil { modelResolved = now }
        case .requestCreated: if requestCreated == nil { requestCreated = now }
        case .requestSent: if requestSent == nil { requestSent = now }
        case .modelStarted: if modelStarted == nil { modelStarted = now }
        case .firstEventReceived: if firstEventReceived == nil { firstEventReceived = now }
        case .firstReasoningDelta: if firstReasoningDelta == nil { firstReasoningDelta = now }
        case .firstTextDelta: if firstTextDelta == nil { firstTextDelta = now }
        case .firstToolCall: if firstToolCall == nil { firstToolCall = now }
        case .responseCompleted: if responseCompleted == nil { responseCompleted = now }
        }
    }

    // MARK: - Derived Latency Durations (in seconds)

    /// Time from user submission to the request being dispatched over the transport.
    public var timeToRequest: TimeInterval? {
        guard let sent = requestSent else { return nil }
        return sent.timeIntervalSince(messageSubmitted)
    }

    /// Time from user submission to the first event emitted by the runtime/model.
    public var timeToFirstEvent: TimeInterval? {
        guard let first = firstEventReceived else { return nil }
        return first.timeIntervalSince(messageSubmitted)
    }

    /// Time from user submission to the first streaming reasoning/thought chunk.
    public var timeToFirstReasoning: TimeInterval? {
        guard let reasoning = firstReasoningDelta else { return nil }
        return reasoning.timeIntervalSince(messageSubmitted)
    }

    /// Time from user submission to the first streaming text chunk.
    public var timeToFirstText: TimeInterval? {
        guard let text = firstTextDelta else { return nil }
        return text.timeIntervalSince(messageSubmitted)
    }

    /// Time from user submission to the first tool execution call.
    public var timeToFirstToolCall: TimeInterval? {
        guard let tool = firstToolCall else { return nil }
        return tool.timeIntervalSince(messageSubmitted)
    }

    /// Total round-trip duration from submission to completion.
    public var totalResponseTime: TimeInterval? {
        guard let completed = responseCompleted else { return nil }
        return completed.timeIntervalSince(messageSubmitted)
    }

    /// Logs diagnostic summary to the internal event bus and subsystem logger.
    public func logSummary(modelName: String = "Assist") {
        let ttReq = timeToRequest.map { String(format: "%.0fms", $0 * 1000) } ?? "n/a"
        let ttEvent = timeToFirstEvent.map { String(format: "%.0fms", $0 * 1000) } ?? "n/a"
        let ttReasoning = timeToFirstReasoning.map { String(format: "%.0fms", $0 * 1000) } ?? "n/a"
        let ttText = timeToFirstText.map { String(format: "%.0fms", $0 * 1000) } ?? "n/a"
        let ttTool = timeToFirstToolCall.map { String(format: "%.0fms", $0 * 1000) } ?? "n/a"
        let total = totalResponseTime.map { String(format: "%.2fs", $0) } ?? "n/a"

        logger.info("[RequestTelemetry:\(self.id.uuidString.prefix(8))] Model: \(modelName) | Dispatch: \(ttReq) | FirstEvent: \(ttEvent) | FirstReasoning: \(ttReasoning) | FirstText: \(ttText) | FirstTool: \(ttTool) | Total: \(total)")

        DiagnosticEventBus.shared.logEvent(
            component: "AssistMetrics",
            severity: "INFO",
            category: "performance",
            message: "Request \(self.id.uuidString.prefix(8)) [\(modelName)] -> FirstEvent: \(ttEvent), FirstText: \(ttText), Total: \(total)"
        )
    }
}
