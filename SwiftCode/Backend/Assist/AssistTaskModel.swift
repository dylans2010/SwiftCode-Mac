import Foundation

// MARK: - Assist v3 Structured Task Model

/// Represents the comprehensive state of an active autonomous agent engineering task.
public struct AgentTask: Codable, Sendable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public var updatedAt: Date

    // Core intent & boundaries
    public var originalRequest: String
    public var interpretedObjective: String
    public var constraints: [String]
    public var discoveredRequirements: [String]

    // Scope & operations
    public var filesInvolved: [String]
    public var plannedOperations: [TaskOperation]
    public var completedOperations: [TaskOperation]

    // Verification & Quality Gate
    public var verificationRequirements: [VerificationRequirement]
    public var completionCriteria: [CompletionCriterion]

    // Diagnostics & Healing
    public var failures: [TaskFailure]
    public var repairAttempts: [RepairAttempt]
    public var toolHistory: [ToolExecutionRecord]
    public var importantObservations: [String]
    public var unresolvedIssues: [String]

    // Budget & Lifecycle
    public var status: AgentSessionStatus
    public var budgets: TaskExecutionBudget

    public init(
        id: UUID = UUID(),
        originalRequest: String,
        interpretedObjective: String = "",
        constraints: [String] = [],
        discoveredRequirements: [String] = [],
        filesInvolved: [String] = [],
        plannedOperations: [TaskOperation] = [],
        completedOperations: [TaskOperation] = [],
        verificationRequirements: [VerificationRequirement] = [],
        completionCriteria: [CompletionCriterion] = [],
        failures: [TaskFailure] = [],
        repairAttempts: [RepairAttempt] = [],
        toolHistory: [ToolExecutionRecord] = [],
        importantObservations: [String] = [],
        unresolvedIssues: [String] = [],
        status: AgentSessionStatus = .idle,
        budgets: TaskExecutionBudget = TaskExecutionBudget()
    ) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.originalRequest = originalRequest
        self.interpretedObjective = interpretedObjective.isEmpty ? originalRequest : interpretedObjective
        self.constraints = constraints
        self.discoveredRequirements = discoveredRequirements
        self.filesInvolved = filesInvolved
        self.plannedOperations = plannedOperations
        self.completedOperations = completedOperations
        self.verificationRequirements = verificationRequirements
        self.completionCriteria = completionCriteria.isEmpty ? CompletionCriterion.defaultCriteria() : completionCriteria
        self.failures = failures
        self.repairAttempts = repairAttempts
        self.toolHistory = toolHistory
        self.importantObservations = importantObservations
        self.unresolvedIssues = unresolvedIssues
        self.status = status
        self.budgets = budgets
    }

    public init(objective: String) {
        self.init(originalRequest: objective, interpretedObjective: objective)
    }

    public mutating func recordFileInvolved(_ file: String) {
        if !filesInvolved.contains(file) {
            filesInvolved.append(file)
        }
    }
}

// MARK: - Task Operations

public struct TaskOperation: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let toolId: String
    public let description: String
    public let targetFile: String?
    public var isMutating: Bool
    public var status: AssistExecutionStatus
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        toolId: String,
        description: String,
        targetFile: String? = nil,
        isMutating: Bool = false,
        status: AssistExecutionStatus = .pending,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.toolId = toolId
        self.description = description
        self.targetFile = targetFile
        self.isMutating = isMutating
        self.status = status
        self.timestamp = timestamp
    }
}

// MARK: - Verification Requirements

public enum VerificationKind: String, Codable, Sendable {
    case syntaxCheck = "Syntax Check"
    case compilation = "Project Compilation"
    case unitTests = "Unit Tests"
    case diffAudit = "Diff & Completeness Audit"
    case custom = "Custom Verification"
}

public struct VerificationRequirement: Codable, Sendable, Identifiable {
    public let id: UUID
    public let kind: VerificationKind
    public let description: String
    public var isSatisfied: Bool
    public var evidence: String?
    public var evaluatedAt: Date?

    public init(
        id: UUID = UUID(),
        kind: VerificationKind,
        description: String,
        isSatisfied: Bool = false,
        evidence: String? = nil,
        evaluatedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.description = description
        self.isSatisfied = isSatisfied
        self.evidence = evidence
        self.evaluatedAt = evaluatedAt
    }
}

// MARK: - Completion Criteria Contract

public enum CompletionCriterionType: String, Codable, Sendable {
    case requestUnderstood = "REQUEST_UNDERSTOOD"
    case implementationComplete = "IMPLEMENTATION_COMPLETE"
    case expectedFilesChanged = "EXPECTED_FILES_CHANGED"
    case buildVerified = "BUILD_VERIFIED"
    case testsVerified = "TESTS_VERIFIED"
    case diffReviewed = "DIFF_REVIEWED"
    case noBlockingErrors = "NO_BLOCKING_ERRORS"
}

public struct CompletionCriterion: Codable, Sendable, Identifiable {
    public let id: UUID
    public let type: CompletionCriterionType
    public let name: String
    public var isMet: Bool
    public var evidence: String

    public init(
        id: UUID = UUID(),
        type: CompletionCriterionType,
        name: String,
        isMet: Bool = false,
        evidence: String = ""
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.isMet = isMet
        self.evidence = evidence
    }

    public static func defaultCriteria() -> [CompletionCriterion] {
        return [
            CompletionCriterion(type: .requestUnderstood, name: "Request Understood", isMet: false),
            CompletionCriterion(type: .implementationComplete, name: "Implementation Complete", isMet: false),
            CompletionCriterion(type: .expectedFilesChanged, name: "Expected Files Changed", isMet: false),
            CompletionCriterion(type: .buildVerified, name: "Build Verified", isMet: false),
            CompletionCriterion(type: .testsVerified, name: "Tests Verified", isMet: false),
            CompletionCriterion(type: .diffReviewed, name: "Diff Reviewed", isMet: false),
            CompletionCriterion(type: .noBlockingErrors, name: "No Known Blocking Errors", isMet: false)
        ]
    }
}

// MARK: - Failure & Repair Tracking

public enum FailureCategory: String, Codable, Sendable {
    case compilerError = "Compiler Error"
    case testFailure = "Test Failure"
    case editConflict = "Edit Conflict"
    case toolError = "Tool Error"
    case sandboxViolation = "Sandbox Violation"
    case loopStagnation = "Loop Stagnation"
    case ambiguity = "Ambiguity"
    case unknown = "Unknown"
}

public struct TaskFailure: Codable, Sendable, Identifiable {
    public let id: UUID
    public let iteration: Int
    public let signature: String
    public let category: FailureCategory
    public let message: String
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        iteration: Int,
        signature: String,
        category: FailureCategory,
        message: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.iteration = iteration
        self.signature = signature
        self.category = category
        self.message = message
        self.timestamp = timestamp
    }
}

public struct RepairAttempt: Codable, Sendable, Identifiable {
    public let id: UUID
    public let failureSignature: String
    public let hypothesis: String
    public let strategy: String
    public var wasSuccessful: Bool
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        failureSignature: String,
        hypothesis: String,
        strategy: String,
        wasSuccessful: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.failureSignature = failureSignature
        self.hypothesis = hypothesis
        self.strategy = strategy
        self.wasSuccessful = wasSuccessful
        self.timestamp = timestamp
    }
}

// MARK: - Tool History Record

public struct ToolExecutionRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let toolId: String
    public let explanation: String
    public let inputSummary: String
    public let outputSummary: String
    public let success: Bool
    public let duration: TimeInterval
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        toolId: String,
        explanation: String,
        inputSummary: String,
        outputSummary: String,
        success: Bool,
        duration: TimeInterval,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.toolId = toolId
        self.explanation = explanation
        self.inputSummary = inputSummary
        self.outputSummary = outputSummary
        self.success = success
        self.duration = duration
        self.timestamp = timestamp
    }
}

// MARK: - Execution Budgets

public struct TaskExecutionBudget: Codable, Sendable {
    public var maxIterations: Int
    public var maxToolCalls: Int
    public var maxRepairAttempts: Int
    public var maxExecutionTimeSeconds: TimeInterval
    public var maxRepeatedFailures: Int

    public init(
        maxIterations: Int = 30,
        maxToolCalls: Int = 50,
        maxRepairAttempts: Int = 5,
        maxExecutionTimeSeconds: TimeInterval = 600,
        maxRepeatedFailures: Int = 3
    ) {
        self.maxIterations = maxIterations
        self.maxToolCalls = maxToolCalls
        self.maxRepairAttempts = maxRepairAttempts
        self.maxExecutionTimeSeconds = maxExecutionTimeSeconds
        self.maxRepeatedFailures = maxRepeatedFailures
    }

    public func isExceeded(
        iterations: Int,
        toolCalls: Int,
        duration: TimeInterval,
        repairAttempts: Int
    ) -> String? {
        if iterations > maxIterations {
            return "Maximum iterations reached (\(iterations)/\(maxIterations))"
        }
        if toolCalls > maxToolCalls {
            return "Maximum tool calls reached (\(toolCalls)/\(maxToolCalls))"
        }
        if repairAttempts > maxRepairAttempts {
            return "Maximum repair attempts reached (\(repairAttempts)/\(maxRepairAttempts))"
        }
        if duration > maxExecutionTimeSeconds {
            return "Maximum execution time exceeded (\(Int(duration))s/\(Int(maxExecutionTimeSeconds))s)"
        }
        return nil
    }
}
