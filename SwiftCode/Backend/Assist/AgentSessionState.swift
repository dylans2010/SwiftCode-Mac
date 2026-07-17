import Foundation
import Observation

public enum AgentSessionStatus: String, Codable, Sendable {
    case idle = "Idle"
    case planning = "Planning"
    case selectingTool = "Selecting Tool"
    case executingTool = "Executing Tool"
    case inspectingResult = "Inspecting Result"
    case validating = "Validating"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
    case stalled = "Stalled"
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

    public init() {}
}
