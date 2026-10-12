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
    case credentialsResolved
    case systemIndexRetrievalStarted
    case systemIndexRetrievalCompleted
    case toolsPrepared
    case requestCreated
    case requestSent
    case modelStarted
    case firstEventReceived
    case firstReasoningDelta
    case firstTextDelta
    case firstVisibleRender
    case firstToolCall
    case toolExecutionStarted
    case toolExecutionCompleted
    case followUpRequestInitiated
    case responseCompleted
}

/// Captures fine-grained timestamps throughout the Assist request lifecycle to measure
/// and eliminate bottlenecks between user submission and visible model output.
public final class AssistRequestMetrics: Identifiable, @unchecked Sendable {
    public let id: UUID
    public let messageSubmitted: Date
    public var sessionResolved: Date?
    public var modelResolved: Date?
    public var credentialsResolved: Date?
    public var systemIndexRetrievalStarted: Date?
    public var systemIndexRetrievalCompleted: Date?
    public var toolsPrepared: Date?
    public var requestCreated: Date?
    public var requestSent: Date?
    public var modelStarted: Date?
    public var firstEventReceived: Date?
    public var firstReasoningDelta: Date?
    public var firstTextDelta: Date?
    public var firstVisibleRender: Date?
    public var firstToolCall: Date?
    public var toolExecutionStarted: Date?
    public var toolExecutionCompleted: Date?
    public var followUpRequestInitiated: Date?
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
        case .credentialsResolved: if credentialsResolved == nil { credentialsResolved = now }
        case .systemIndexRetrievalStarted: if systemIndexRetrievalStarted == nil { systemIndexRetrievalStarted = now }
        case .systemIndexRetrievalCompleted: if systemIndexRetrievalCompleted == nil { systemIndexRetrievalCompleted = now }
        case .toolsPrepared: if toolsPrepared == nil { toolsPrepared = now }
        case .requestCreated: if requestCreated == nil { requestCreated = now }
        case .requestSent: if requestSent == nil { requestSent = now }
        case .modelStarted: if modelStarted == nil { modelStarted = now }
        case .firstEventReceived: if firstEventReceived == nil { firstEventReceived = now }
        case .firstReasoningDelta: if firstReasoningDelta == nil { firstReasoningDelta = now }
        case .firstTextDelta: if firstTextDelta == nil { firstTextDelta = now }
        case .firstVisibleRender: if firstVisibleRender == nil { firstVisibleRender = now }
        case .firstToolCall: if firstToolCall == nil { firstToolCall = now }
        case .toolExecutionStarted: if toolExecutionStarted == nil { toolExecutionStarted = now }
        case .toolExecutionCompleted: if toolExecutionCompleted == nil { toolExecutionCompleted = now }
        case .followUpRequestInitiated: if followUpRequestInitiated == nil { followUpRequestInitiated = now }
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

    /// Time spent in SystemIndex instruction retrieval (0 after the first
    /// request warms the persisted index — the corpus is never reparsed per
    /// request).
    public var systemIndexRetrievalDuration: TimeInterval? {
        guard let started = systemIndexRetrievalStarted,
              let completed = systemIndexRetrievalCompleted else { return nil }
        return completed.timeIntervalSince(started)
    }

    /// Preparation time: submission until the request was dispatched.
    /// Covers session/model/credential resolution, instruction retrieval,
    /// tool preparation and payload construction.
    public var preparationDuration: TimeInterval? {
        guard let sent = requestSent else { return nil }
        return sent.timeIntervalSince(messageSubmitted)
    }

    /// Time from user submission to the first visibly rendered content.
    public var timeToFirstVisibleRender: TimeInterval? {
        guard let render = firstVisibleRender else { return nil }
        return render.timeIntervalSince(messageSubmitted)
    }

    /// Total round-trip duration from submission to completion.
    public var totalResponseTime: TimeInterval? {
        guard let completed = responseCompleted else { return nil }
        return completed.timeIntervalSince(messageSubmitted)
    }

    /// Logs diagnostic summary to the internal event bus and subsystem logger.
    public func logSummary(modelName: String = "Assist") {
        let runtimeStartup = sessionResolved.map { String(format: "%.0fms", $0.timeIntervalSince(messageSubmitted) * 1000) } ?? "n/a"
        let modelResolve: String
        if let resolved = modelResolved, let runtimeReady = sessionResolved {
            modelResolve = String(format: "%.0fms", resolved.timeIntervalSince(runtimeReady) * 1000)
        } else {
            modelResolve = modelResolved.map { String(format: "%.0fms", $0.timeIntervalSince(messageSubmitted) * 1000) } ?? "n/a"
        }
        let setup: String
        if let sent = requestSent, let resolved = modelResolved {
            setup = String(format: "%.0fms", sent.timeIntervalSince(resolved) * 1000)
        } else {
            setup = "n/a"
        }
        let ttReq = timeToRequest.map { String(format: "%.0fms", $0 * 1000) } ?? "n/a"
        let ttEvent = timeToFirstEvent.map { String(format: "%.0fms", $0 * 1000) } ?? "n/a"
        let ttReasoning = timeToFirstReasoning.map { String(format: "%.0fms", $0 * 1000) } ?? "n/a"
        let ttText = timeToFirstText.map { String(format: "%.0fms", $0 * 1000) } ?? "n/a"
        let ttTool = timeToFirstToolCall.map { String(format: "%.0fms", $0 * 1000) } ?? "n/a"
        let total = totalResponseTime.map { String(format: "%.2fs", $0) } ?? "n/a"
        let indexRetrieval = systemIndexRetrievalDuration.map { String(format: "%.0fms", $0 * 1000) } ?? "n/a"
        let prep = preparationDuration.map { String(format: "%.0fms", $0 * 1000) } ?? "n/a"
        let ttVisible = timeToFirstVisibleRender.map { String(format: "%.0fms", $0 * 1000) } ?? "n/a"

        logger.info("[RequestTelemetry:\(self.id.uuidString.prefix(8))] Model: \(modelName) | RuntimeStart: \(runtimeStartup) | ModelResolve: \(modelResolve) | SessionSetup: \(setup) | IndexRetrieval: \(indexRetrieval) | Preparation: \(prep) | Dispatch: \(ttReq) | FirstEvent: \(ttEvent) | FirstReasoning: \(ttReasoning) | FirstText: \(ttText) | FirstVisible: \(ttVisible) | FirstTool: \(ttTool) | Total: \(total)")

        DiagnosticEventBus.shared.logEvent(
            component: "AssistMetrics",
            severity: "INFO",
            category: "performance",
            message: "Request \(self.id.uuidString.prefix(8)) [\(modelName)] -> RuntimeStart: \(runtimeStartup), ModelResolve: \(modelResolve), SessionSetup: \(setup), IndexRetrieval: \(indexRetrieval), Preparation: \(prep), FirstEvent: \(ttEvent), FirstText: \(ttText), FirstVisible: \(ttVisible), Total: \(total)"
        )
    }
}
