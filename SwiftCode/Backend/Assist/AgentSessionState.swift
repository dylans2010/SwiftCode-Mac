import Foundation
import Observation

public enum AgentSessionStatus: String, Codable, Sendable {
    case idle = "Idle"
    case receivingRequest = "Receiving Request"
    case analyzingRepository = "Analyzing Repository"
    case collectingContext = "Collecting Context"
    case planning = "Planning"
    case planningReview = "Planning Review"
    case awaitingApproval = "Awaiting Approval"
    case executingStrategy = "Executing Strategy"
    case selectingTools = "Selecting Tools"
    case executingTools = "Executing Tools"
    case updatingRepository = "Updating Repository"
    case validating = "Validating"
    case reviewing = "Reviewing"
    case reviewFailed = "Review Failed"
    case recovering = "Recovering"
    case generatingSummary = "Generating Summary"
    case completing = "Completing"
    case terminated = "Terminated"

    // Backward compatibility cases
    case initializing = "Initializing"
    case understandingRequest = "Understanding Request"
    case gatheringContext = "Gathering Context"
    case selectingTool = "Selecting Tool"
    case executingTool = "Executing Tool"
    case waitingForUserApproval = "Waiting For User Approval"
    case inspectingResult = "Inspecting Result"
    case finished = "Finished"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
    case stalled = "Stalled"
}

public struct StateTransition: Codable, Sendable, Identifiable {
    public let id: UUID
    public let fromState: AgentSessionStatus
    public let toState: AgentSessionStatus
    public let reason: String
    public let timestamp: Date

    public init(id: UUID = UUID(), fromState: AgentSessionStatus, toState: AgentSessionStatus, reason: String, timestamp: Date = Date()) {
        self.id = id
        self.fromState = fromState
        self.toState = toState
        self.reason = reason
        self.timestamp = timestamp
    }
}

public struct AgentEvent: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let state: AgentSessionStatus
    public let summary: String
    public let toolResult: String?

    public init(id: UUID = UUID(), timestamp: Date = Date(), state: AgentSessionStatus, summary: String, toolResult: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.state = state
        self.summary = summary
        self.toolResult = toolResult
    }
}

public struct PlanStep: Identifiable, Codable, Sendable {
    public let id: UUID
    public let toolId: String
    public let description: String
    public var input: [String: String]
    public var status: AssistExecutionStatus

    public init(id: UUID = UUID(), toolId: String, description: String, input: [String: String], status: AssistExecutionStatus = .pending) {
        self.id = id
        self.toolId = toolId
        self.description = description
        self.input = input
        self.status = status
    }
}

public struct FileChangeItem: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let filename: String
    public let details: String

    public init(id: UUID = UUID(), filename: String, details: String) {
        self.id = id
        self.filename = filename
        self.details = details
    }
}

public struct ToolActivityItem: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let toolId: String
    public let purpose: String
    public let result: String
    public let timestamp: Date

    public init(id: UUID = UUID(), toolId: String, purpose: String, result: String, timestamp: Date = Date()) {
        self.id = id
        self.toolId = toolId
        self.purpose = purpose
        self.result = result
        self.timestamp = timestamp
    }
}

@Observable
@MainActor
public final class AgentChangeSummary: Sendable {
    public var modifiedFiles: [FileChangeItem] = []
    public var createdFiles: [FileChangeItem] = []
    public var deletedFiles: [FileChangeItem] = []
    public var renamedFiles: [FileChangeItem] = []
    public var movedFiles: [FileChangeItem] = []
    public var configChanges: [FileChangeItem] = []
    public var toolActivities: [ToolActivityItem] = []

    public init() {}

    public func clear() {
        modifiedFiles.removeAll()
        createdFiles.removeAll()
        deletedFiles.removeAll()
        renamedFiles.removeAll()
        movedFiles.removeAll()
        configChanges.removeAll()
        toolActivities.removeAll()
    }
}

@Observable
@MainActor
public final class AgentSessionState: Sendable {
    public var objective: String = ""
    public var plan: [PlanStep] = []
    public var completedActions: [String] = []
    public var remainingActions: [PlanStep] = []
    public var toolCallCount: Int = 0
    public var status: AgentSessionStatus = .idle
    public var events: [AgentEvent] = []
    public var stateHistory: [StateTransition] = []
    public var changeSummary = AgentChangeSummary()

    public init() {}
}
