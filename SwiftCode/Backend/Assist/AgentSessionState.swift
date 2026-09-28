import Foundation
import Observation

public enum AgentSessionStatus: String, Codable, Sendable {
    case idle = "Idle"
    case initializing = "Initializing"
    case grounding = "Grounding"
    case planning = "Planning"
    case executing = "Executing"
    case observing = "Observing"
    case verifying = "Verifying"
    case repairing = "Repairing"
    case recovering = "Recovering"
    case waiting = "Waiting"
    case completed = "Completed"
    case blocked = "Blocked"
    case failed = "Failed"
    case cancelled = "Cancelled"

    // Legacy aliases for backward compatibility
    case receivingRequest = "Receiving Request"
    case analyzingRepository = "Analyzing Repository"
    case collectingContext = "Collecting Context"
    case planningReview = "Planning Review"
    case awaitingApproval = "Awaiting Approval"
    case executingStrategy = "Executing Strategy"
    case selectingTools = "Selecting Tools"
    case executingTools = "Executing Tools"
    case updatingRepository = "Updating Repository"
    case validating = "Validating"
    case reviewing = "Reviewing"
    case reviewFailed = "Review Failed"
    case generatingSummary = "Generating Summary"
    case completing = "Completing"
    case terminated = "Terminated"
    case evaluatingGoalExpansion = "Evaluating Goal Expansion"
    case transitioningToNextGoal = "Transitioning to Expanded Goal"
    case understandingRequest = "Understanding Request"
    case gatheringContext = "Gathering Context"
    case selectingTool = "Selecting Tool"
    case executingTool = "Executing Tool"
    case waitingForUserApproval = "Waiting For User Approval"
    case inspectingResult = "Inspecting Result"
    case finished = "Finished"
    case stalled = "Stalled"
}

extension AgentSessionStatus {
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled, .blocked:
            return true
        default:
            return false
        }
    }

    public var isLegacy: Bool {
        switch self {
        case .receivingRequest, .analyzingRepository, .collectingContext, .planningReview,
             .awaitingApproval, .executingStrategy, .selectingTools, .executingTools,
             .updatingRepository, .validating, .reviewing, .reviewFailed,
             .generatingSummary, .completing, .terminated, .evaluatingGoalExpansion,
             .transitioningToNextGoal, .understandingRequest, .gatheringContext,
             .selectingTool, .executingTool, .waitingForUserApproval, .inspectingResult,
             .finished, .stalled:
            return true
        default:
            return false
        }
    }

    public static let validTransitions: [AgentSessionStatus: Set<AgentSessionStatus>] = [
        .idle: [.initializing, .failed, .cancelled],
        .initializing: [.grounding, .planning, .failed, .cancelled],
        .grounding: [.planning, .executing, .failed, .cancelled],
        .planning: [.executing, .repairing, .recovering, .blocked, .failed, .cancelled],
        .executing: [.observing, .verifying, .repairing, .recovering, .waiting, .completed, .blocked, .failed, .cancelled],
        .observing: [.executing, .planning, .verifying, .repairing, .recovering, .blocked, .failed, .cancelled],
        .verifying: [.completed, .repairing, .recovering, .executing, .blocked, .failed, .cancelled],
        .repairing: [.executing, .observing, .recovering, .blocked, .failed, .cancelled],
        .recovering: [.executing, .planning, .repairing, .blocked, .failed, .cancelled],
        .waiting: [.executing, .planning, .cancelled],
        .blocked: [.planning, .cancelled],
        .completed: [],
        .failed: [.idle],
        .cancelled: [.idle]
    ]

    public func canTransition(to newState: AgentSessionStatus) -> Bool {
        if self == newState { return true }
        if isTerminal || newState.isTerminal { return true }
        let allowed = AgentSessionStatus.validTransitions[self] ?? []
        return allowed.contains(newState)
    }
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

    // MARK: - Assist v4 Continuous Takeover & Multi-Goal State
    public var rootGoal: String = ""
    public var currentGoal: AssistGoal?
    public var goalGraph: [AssistGoal] = []
    public var completedGoals: [AssistGoal] = []
    public var pendingGoals: [AssistGoal] = []
    public var rejectedGoals: [String] = []
    public var takeoverActive: Bool = false
    public var isAutonomousExpansion: Bool = false

    // MARK: - Observation Loop State
    public var lastObservation: ToolObservation?
    public var observationHistory: [ToolObservation] = []
    public var semanticStateVersion: Int = 0

    // MARK: - Stuck Detection State
    public var toolCallSignatures: [String: Int] = [:]
    public var recentToolCallWindow: [String] = []
    public var lastFileChangeCount: Int = 0
    public var iterationsSinceFileChange: Int = 0
    public var replanningCount: Int = 0
    public var stuckDetectionLog: [StuckDetectionEvent] = []

    public init() {}
}

// MARK: - Tool Observation

public struct ToolObservation: Codable, Sendable, Identifiable {
    public let id: UUID
    public let toolId: String
    public let inputSignature: String
    public let success: Bool
    public let outputSummary: String
    public let filesChanged: [String]
    public let timestamp: Date
    public let interpretation: String
    public let suggestedNextAction: String?

    public init(
        id: UUID = UUID(),
        toolId: String,
        inputSignature: String,
        success: Bool,
        outputSummary: String,
        filesChanged: [String] = [],
        timestamp: Date = Date(),
        interpretation: String = "",
        suggestedNextAction: String? = nil
    ) {
        self.id = id
        self.toolId = toolId
        self.inputSignature = inputSignature
        self.success = success
        self.outputSummary = outputSummary
        self.filesChanged = filesChanged
        self.timestamp = timestamp
        self.interpretation = interpretation
        self.suggestedNextAction = suggestedNextAction
    }
}

// MARK: - Stuck Detection Event

public struct StuckDetectionEvent: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let detectionType: StuckDetectionType
    public let reason: String
    public let iteration: Int
    public let evidence: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        detectionType: StuckDetectionType,
        reason: String,
        iteration: Int,
        evidence: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.detectionType = detectionType
        self.reason = reason
        self.iteration = iteration
        self.evidence = evidence
    }
}

public enum StuckDetectionType: String, Codable, Sendable {
    case noProgress = "No Progress"
    case circularBehavior = "Circular Behavior"
    case repeatedIdenticalCalls = "Repeated Identical Calls"
    case staleReasoning = "Stale Reasoning"
    case repeatedFailures = "Repeated Failures"
    case noFileChangesWhenExpected = "No File Changes When Expected"
}
