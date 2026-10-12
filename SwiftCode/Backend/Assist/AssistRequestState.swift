//
//  AssistRequestState.swift
//  SwiftCode
//
//  Unified request lifecycle state for Assist. Replaces the previous
//  stringly-typed `currentActivityStatus` + scattered `isProcessing` Bool as
//  the source of truth for what a request is doing; the UI string is derived
//  from the phase so status labels always reflect real runtime events.
//

import Foundation

/// Every observable phase of an Assist request, from submission to a terminal
/// state. Every request must end in one of the terminal phases
/// (completed / failed / cancelled / timedOut) — never stuck "running".
public enum AssistRequestPhase: String, Sendable, CaseIterable {
    case idle
    case preparingRequest
    case retrievingInstructions
    case resolvingModel
    case resolvingCredentials
    case preparingTools
    case buildingRequest
    case sendingRequest
    case waitingForModel
    case receivingResponse
    case executingTool
    case handlingToolResult
    case recoveringFromError
    case fallingBack
    case finalizing
    case completed
    case failed
    case cancelled
    case timedOut

    /// The user-facing status text for this phase. Status labels in
    /// AssistMainView are driven by this mapping, not by ad-hoc strings.
    public var statusText: String {
        switch self {
        case .idle: return "Idle"
        case .preparingRequest: return "Preparing request…"
        case .retrievingInstructions: return "Loading instructions…"
        case .resolvingModel: return "Resolving model…"
        case .resolvingCredentials: return "Checking credentials…"
        case .preparingTools: return "Preparing tools…"
        case .buildingRequest: return "Building request…"
        case .sendingRequest: return "Connecting to model…"
        case .waitingForModel: return "Waiting for model output…"
        case .receivingResponse: return "Receiving response…"
        case .executingTool: return "Running tool…"
        case .handlingToolResult: return "Processing tool result…"
        case .recoveringFromError: return "Recovering…"
        case .fallingBack: return "Trying fallback model…"
        case .finalizing: return "Finalizing…"
        case .completed: return "Idle"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .timedOut: return "Timed out"
        }
    }

    /// Whether this phase is terminal: the request is over and the UI must
    /// not show a spinner for it anymore.
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled, .timedOut: return true
        default: return false
        }
    }
}

/// Monotonic generation counter identifying a single user submission.
/// Async callbacks capture the generation they were created under and ignore
/// their results when the generation has advanced (conversation cleared or a
/// newer request started), which prevents late callbacks from repopulating a
/// cleared conversation.
public struct AssistRequestGeneration: Sendable, Equatable {
    public let value: Int
    public init(_ value: Int) { self.value = value }
}

/// Error thrown when a provider request exceeds its wall-clock budget.
/// Surfaced to the user as an explicit timeout, never a silent stall.
/// Conforms to LocalizedError so the custom message survives
/// `error.localizedDescription` instead of degrading to a generic
/// "operation couldn't be completed" string.
public enum AssistRequestTimeoutError: LocalizedError, Sendable {
    case timedOut(TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            return "The model request timed out after \(Int(seconds)) seconds without completing. Please retry; if a tool was running, inspect its result before repeating it."
        }
    }
}

/// Tracks streaming progress for the chat-mode watchdog. Thread-safe so the
/// provider's token callback (which may not be MainActor-isolated) can record
/// progress while a detached watchdog task reads it.
public final class AssistStreamProgressMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var lastProgressAt: Date = Date()

    public init() {}

    public func markProgress() {
        lock.lock()
        lastProgressAt = Date()
        lock.unlock()
    }

    public func secondsSinceProgress() -> TimeInterval {
        lock.lock()
        let elapsed = Date().timeIntervalSince(lastProgressAt)
        lock.unlock()
        return elapsed
    }
}
