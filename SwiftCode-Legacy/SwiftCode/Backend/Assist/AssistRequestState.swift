import Foundation

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

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled, .timedOut: return true
        default: return false
        }
    }
}

public struct AssistRequestGeneration: Sendable, Equatable {
    public let value: Int
    public init(_ value: Int) { self.value = value }
}

public enum AssistRequestTimeoutError: LocalizedError, Sendable {
    case timedOut(TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            return "The model request timed out after \(Int(seconds)) seconds without completing. Please retry; if a tool was running, inspect its result before repeating it."
        }
    }
}

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
