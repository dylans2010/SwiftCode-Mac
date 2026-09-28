import Foundation
import SwiftUI

// MARK: - Canonical Agent Model Abstraction

public struct AgentModelResponse: Codable, Sendable {
    public let content: String
    public let toolCalls: [AgentToolCall]
    public let modelId: String
    public let provider: String
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let finishReason: String?
    public let latency: TimeInterval

    public init(
        content: String,
        toolCalls: [AgentToolCall] = [],
        modelId: String,
        provider: String,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        finishReason: String? = nil,
        latency: TimeInterval = 0
    ) {
        self.content = content
        self.toolCalls = toolCalls
        self.modelId = modelId
        self.provider = provider
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.finishReason = finishReason
        self.latency = latency
    }
}

public struct AgentModelContextBudget: Sendable {
    public let modelId: String
    public let contextWindowTokens: Int
    public let reservedOutputTokens: Int
    public let maxInputTokens: Int
    public let utilizationRatio: Double

    public init(modelId: String, contextWindowTokens: Int, reservedOutputTokens: Int = 4096) {
        self.modelId = modelId
        self.contextWindowTokens = contextWindowTokens
        self.reservedOutputTokens = reservedOutputTokens
        self.maxInputTokens = max(1024, contextWindowTokens - reservedOutputTokens)
        self.utilizationRatio = Double(reservedOutputTokens) / Double(contextWindowTokens)
    }

    public func fitsContext(estimatedTokens: Int) -> Bool {
        return estimatedTokens <= maxInputTokens
    }

    public func estimatedTokenCount(for text: String) -> Int {
        return text.count / 4
    }
}

// MARK: - AI Models & Providers

public enum AssistModelProvider: String, Codable, CaseIterable, Sendable {
    case openAI = "ChatGPT"
    case anthropic = "Claude"
    case gemini = "Gemini"
    case mistral = "Mistral"
    case meta = "Meta AI"
    case kimi = "Kimi"
    case openRouter = "OpenRouter"
    case codex = "Codex"

    public static func from(llmProvider: LLMProvider) -> AssistModelProvider {
        switch llmProvider {
        case .openai: return .openAI
        case .anthropic: return .anthropic
        case .google: return .gemini
        case .mistral: return .mistral
        case .openRouter, .qwen, .offline: return .openRouter
        case .codex: return .codex
        }
    }

    var apiKeyProvider: APIKeyProvider {
        switch self {
        case .openAI: return .openai
        case .anthropic: return .anthropic
        case .gemini: return .google
        case .mistral: return .mistral
        case .meta, .kimi: return .openRouter
        case .openRouter: return .openRouter
        case .codex: return .openai
        }
    }

    var llmProvider: LLMProvider {
        switch self {
        case .openAI: return .openai
        case .anthropic: return .anthropic
        case .gemini: return .google
        case .mistral: return .mistral
        case .meta, .kimi, .openRouter: return .openRouter
        case .codex: return .codex
        }
    }

    public var endpoint: URL? {
        switch self {
        case .openAI: return URL(string: "https://api.openai.com/v1/chat/completions")
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/messages")
        case .gemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")
        case .mistral: return URL(string: "https://api.mistral.ai/v1/chat/completions")
        case .meta: return URL(string: "https://api.meta.ai/v1/chat/completions") // Example
        case .kimi: return URL(string: "https://api.moonshot.cn/v1/chat/completions")
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/chat/completions")
        case .codex: return URL(string: "http://localhost:3003/v1/chat/completions")
        }
    }
}

public struct AssistAIResponse: Sendable {
    public let content: String
    public let success: Bool
    public let error: String?

    public init(content: String, success: Bool, error: String? = nil) {
        self.content = content
        self.success = success
        self.error = error
    }
}

public struct AssistLLMService {
    @MainActor
    public static func generateResponse(prompt: String, provider: AssistModelProvider, apiKey: String?, modelOverride: String? = nil) async -> AssistAIResponse {
        do {
            // Standardize on the central LLMService which handles all model routing and logic.
            // We pass the prompt and let LLMService handle the details.
            let activeModelID = modelOverride ?? AppSettings.shared.selectedAssistModelID
            let providerOverride = provider.llmProvider

            let content = try await LLMService.shared.generateResponse(
                prompt: prompt,
                useContext: true,
                modelOverride: activeModelID,
                providerOverride: providerOverride
            )
            return AssistAIResponse(content: content, success: true)
        } catch {
            return AssistAIResponse(content: "", success: false, error: "AI request failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Assist Context & State

/// Shared context provided to tools during execution.
public struct AssistContext: Sendable {
    public let sessionId: UUID
    public let project: Project?
    public let workspaceRoot: URL
    public let memory: AssistMemoryGraphProtocol
    public let logger: AssistLoggerProtocol
    public let fileSystem: AssistFileSystemProtocol
    public let git: AssistGitManagerProtocol
    public let permissions: AssistPermissionsManagerProtocol

    // Safety & Mode settings
    public let safetyLevel: AssistSafetyLevel
    public let isAutonomous: Bool

    public init(
        sessionId: UUID,
        project: Project?,
        workspaceRoot: URL,
        memory: AssistMemoryGraphProtocol,
        logger: AssistLoggerProtocol,
        fileSystem: AssistFileSystemProtocol,
        git: AssistGitManagerProtocol,
        permissions: AssistPermissionsManagerProtocol,
        safetyLevel: AssistSafetyLevel,
        isAutonomous: Bool
    ) {
        self.sessionId = sessionId
        self.project = project
        self.workspaceRoot = workspaceRoot
        self.memory = memory
        self.logger = logger
        self.fileSystem = fileSystem
        self.git = git
        self.permissions = permissions
        self.safetyLevel = safetyLevel
        self.isAutonomous = isAutonomous
    }
}

/// Safety levels for autonomous execution.
public enum AssistSafetyLevel: String, Codable, CaseIterable, Sendable {
    case conservative = "Conservative"
    case balanced = "Balanced"
    case aggressive = "Aggressive"
}

/// Result returned by an Assist tool execution.
public struct AssistToolResult: Codable, Sendable {
    public let success: Bool
    public let output: String
    public let data: [String: String]?
    public let error: String?
    public let errorCode: Int?
    public let diagnostics: [String]
    public let filesChanged: [String]
    public let diff: String?
    public let duration: TimeInterval
    public let exitCode: Int32?
    public let suggestedNextActions: [String]
    public let beforeContent: String?
    public let afterContent: String?

    public init(
        success: Bool,
        output: String,
        data: [String: String]? = nil,
        error: String? = nil,
        errorCode: Int? = nil,
        diagnostics: [String] = [],
        filesChanged: [String] = [],
        diff: String? = nil,
        duration: TimeInterval = 0,
        exitCode: Int32? = nil,
        suggestedNextActions: [String] = [],
        beforeContent: String? = nil,
        afterContent: String? = nil
    ) {
        self.success = success
        self.output = output
        self.data = data
        self.error = error
        self.errorCode = errorCode
        self.diagnostics = diagnostics
        self.filesChanged = filesChanged
        self.diff = diff
        self.duration = duration
        self.exitCode = exitCode
        self.suggestedNextActions = suggestedNextActions
        self.beforeContent = beforeContent
        self.afterContent = afterContent
    }

    public static func success(
        _ output: String,
        data: [String: String]? = nil,
        diff: String? = nil,
        filesChanged: [String] = [],
        diagnostics: [String] = [],
        suggestedNextActions: [String] = []
    ) -> AssistToolResult {
        var finalData = data ?? [:]
        if let diff = diff, finalData[AssistToolDataKey.diff] == nil {
            finalData[AssistToolDataKey.diff] = diff
        }
        return AssistToolResult(
            success: true,
            output: output,
            data: finalData.isEmpty ? nil : finalData,
            diagnostics: diagnostics,
            filesChanged: filesChanged,
            diff: diff,
            suggestedNextActions: suggestedNextActions
        )
    }

    public static func failure(
        _ error: String,
        code: Int? = nil,
        diagnostics: [String] = [],
        suggestedNextActions: [String] = []
    ) -> AssistToolResult {
        AssistToolResult(
            success: false,
            output: "Error: \(error)",
            error: error,
            errorCode: code,
            diagnostics: diagnostics,
            suggestedNextActions: suggestedNextActions
        )
    }
}

// Standard data payload keys
public enum AssistToolDataKey {
    public static let content = "content"
    public static let explanation = "explanation"
    public static let diff = "diff"
    public static let testResults = "test_results"
    public static let buildStatus = "build_status"
    public static let searchResults = "results"
    public static let planId = "planId"
    public static let breakdown = "breakdown"
}

// MARK: - Planning & Execution Models

/// A structured plan generated by the AssistPlanner.
public struct AssistExecutionPlan: Codable, Identifiable, Sendable {
    public let id: UUID
    public let goal: String
    public var steps: [AssistExecutionStep]
    public var status: AssistExecutionStatus

    public init(goal: String, steps: [AssistExecutionStep] = []) {
        self.id = UUID()
        self.goal = goal
        self.steps = steps
        self.status = .pending
    }
}

/// A single step within an execution plan.
public struct AssistExecutionStep: Codable, Identifiable, Sendable {
    public let id: UUID
    public let toolId: String
    public let input: [String: String] // Simple key-value for storage/serialization
    public let description: String
    public var status: AssistExecutionStatus
    public var result: AssistToolResult?

    public init(toolId: String, input: [String: String], description: String) {
        self.id = UUID()
        self.toolId = toolId
        self.input = input
        self.description = description
        self.status = .pending
    }
}

public enum AssistExecutionStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case skipped
}

// MARK: - Context Engine Types

public enum ContextPriority: Int, Codable, Sendable, Comparable {
    case p0 = 0
    case p1 = 1
    case p2 = 2
    case p3 = 3

    public static func < (lhs: ContextPriority, rhs: ContextPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct ContextBudget: Sendable {
    public let modelCapacity: Int
    public let systemPromptOverhead: Int
    public let responseReserve: Int
    public let toolCallReserve: Int
    public let safetyMargin: Int
    public let usableBudget: Int

    public init(modelCapacity: Int, systemPromptOverhead: Int, responseReserve: Int = 4096, toolCallReserve: Int = 2048, safetyMargin: Int = 2048) {
        self.modelCapacity = modelCapacity
        self.systemPromptOverhead = systemPromptOverhead
        self.responseReserve = responseReserve
        self.toolCallReserve = toolCallReserve
        self.safetyMargin = safetyMargin
        self.usableBudget = max(0, modelCapacity - systemPromptOverhead - responseReserve - toolCallReserve - safetyMargin)
    }
}

public struct ContextPressureState: Sendable {
    public let capacity: Int
    public let estimatedUsage: Int
    public let safetyMargin: Int
    public let compactionStatus: CompactionStatus
    public let summaryDepth: Int
    public let lastCompaction: Date?
    public let sourceSizes: [String: Int]

    public enum CompactionStatus: String, Sendable {
        case none
        case light
        case moderate
        case aggressive
    }

    public var pressureRatio: Double {
        guard capacity > 0 else { return 0 }
        return Double(estimatedUsage) / Double(capacity)
    }

    public var needsCompaction: Bool {
        pressureRatio > 0.75
    }
}

public struct CompactedToolResult: Sendable {
    public let toolId: String
    public let success: Bool
    public let summary: String
    public let errors: [String]
    public let warnings: [String]
    public let keyOutput: String
    public let filesChanged: [String]
    public let exitCode: Int32?
    public let originalOutput: String?

    public init(toolId: String, success: Bool, summary: String, errors: [String] = [], warnings: [String] = [], keyOutput: String = "", filesChanged: [String] = [], exitCode: Int32? = nil, originalOutput: String? = nil) {
        self.toolId = toolId
        self.success = success
        self.summary = summary
        self.errors = errors
        self.warnings = warnings
        self.keyOutput = keyOutput
        self.filesChanged = filesChanged
        self.exitCode = exitCode
        self.originalOutput = originalOutput
    }
}

public struct HierarchicalSummary: Sendable {
    public let level: SummaryLevel
    public let content: String
    public let timestamp: Date
    public let sourceEventCount: Int

    public enum SummaryLevel: String, Sendable {
        case raw
        case recentWindow
        case actionSummary
        case taskSummary
        case sessionSummary
    }

    public init(level: SummaryLevel, content: String, sourceEventCount: Int, timestamp: Date = Date()) {
        self.level = level
        self.content = content
        self.sourceEventCount = sourceEventCount
        self.timestamp = timestamp
    }
}

public struct ModelContextSection: Sendable {
    public let priority: ContextPriority
    public let title: String
    public let content: String
    public let estimatedTokens: Int
    public let isCompacted: Bool

    public init(priority: ContextPriority, title: String, content: String, estimatedTokens: Int = 0, isCompacted: Bool = false) {
        self.priority = priority
        self.title = title
        self.content = content
        self.estimatedTokens = estimatedTokens
        self.isCompacted = isCompacted
    }
}

public struct ContextRecoveryResult: Sendable {
    public let success: Bool
    public let originalError: String
    public let compactionApplied: Bool
    public let retryCount: Int
    public let finalPrompt: String?

    public init(success: Bool, originalError: String, compactionApplied: Bool, retryCount: Int, finalPrompt: String? = nil) {
        self.success = success
        self.originalError = originalError
        self.compactionApplied = compactionApplied
        self.retryCount = retryCount
        self.finalPrompt = finalPrompt
    }
}

// MARK: - Legacy / UI Compatibility Models

/// Maintained for UI compatibility
public enum AssistStatus: String, Codable {
    case pending
    case inProgress
    case completed
    case failed
    case rejected
}

// MARK: - Composio Execution Metadata for Timeline Rendering

public struct ComposioExecutionMetadata: Codable, Sendable, Identifiable {
    public let id: UUID
    public let toolkit: String
    public let toolSlug: String
    public let arguments: String
    public var output: String
    public var logId: String?
    public var success: Bool
    public var isExecuting: Bool
    public var duration: TimeInterval
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        toolkit: String = "general",
        toolSlug: String,
        arguments: String,
        output: String,
        logId: String? = nil,
        success: Bool = false,
        isExecuting: Bool = true,
        duration: TimeInterval = 0.0,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.toolkit = toolkit
        self.toolSlug = toolSlug
        self.arguments = arguments
        self.output = output
        self.logId = logId
        self.success = success
        self.isExecuting = isExecuting
        self.duration = duration
        self.timestamp = timestamp
    }
}

public struct AssistMessage: Codable, Identifiable, Sendable {
    public let id: UUID
    public let role: AssistRole
    public let content: String
    public let timestamp: Date
    public var attachments: [AgentFileContext]?
    public var mcpExecution: MCPExecutionMetadata?
    public var composioExecution: ComposioExecutionMetadata?
    public var activityGroup: AssistActivityGroup?

    public init(
        role: AssistRole,
        content: String,
        attachments: [AgentFileContext]? = nil,
        mcpExecution: MCPExecutionMetadata? = nil,
        composioExecution: ComposioExecutionMetadata? = nil,
        activityGroup: AssistActivityGroup? = nil
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.attachments = attachments
        self.mcpExecution = mcpExecution
        self.composioExecution = composioExecution
        self.activityGroup = activityGroup
    }
}

public enum AssistRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

public enum AssistCapabilityKind: String, Codable {
    case `extension`
    case skill
    case connection
}

// MARK: - Core Protocols for Components

public protocol AssistMemoryGraphProtocol: Sendable {
    func store(key: String, value: String)
    func retrieve(key: String) -> String?
    func clear()
}

public protocol AssistLoggerProtocol: Sendable {
    func info(_ message: String, toolId: String?) async
    func warning(_ message: String, toolId: String?) async
    func error(_ message: String, toolId: String?) async
    func debug(_ message: String, toolId: String?) async
}

public protocol AssistFileSystemProtocol: Sendable {
    func readFile(at path: String) throws -> String
    func writeFile(at path: String, content: String) throws
    func deleteFile(at path: String) throws
    func moveFile(from: String, to: String) throws
    func copyFile(from: String, to: String) throws
    func exists(at path: String) -> Bool
    func appendFile(at path: String, content: String) throws
    func listDirectory(at path: String) throws -> [String]
    func createDirectory(at path: String) throws
}

public protocol AssistGitManagerProtocol: Sendable {
    func status() throws -> String
    func commit(message: String) throws
    func push() async throws
}

public protocol AssistPermissionsManagerProtocol: Sendable {
    func isPathAllowed(_ path: String) -> Bool
    func authorizeOperation(_ operation: String) -> Bool
}


// MARK: - Legacy Typealiases

public typealias AssistPlan = AssistExecutionPlan
public typealias AssistStep = AssistExecutionStep

public enum AssistAction: Codable, Hashable {
    case createFile(String, String)
    case modifyFile(String, String)
    case deleteFile(String)
    case renameFile(String, String)
    case runTest(String)

    public var path: String {
        switch self {
        case .createFile(let path, _), .modifyFile(let path, _), .deleteFile(let path):
            return path
        case .renameFile(let oldPath, _):
            return oldPath
        case .runTest(let target):
            return target
        }
    }
}

public extension AssistExecutionPlan {
    var title: String { goal }
}

public extension AssistExecutionStep {
    var actions: [AssistAction] { [] }
}

// MARK: - Dynamic Model Options

public struct DynamicModelOption: Identifiable, Hashable, Sendable {
    public var id: String { modelID }
    public let modelID: String
    public let name: String
    public let provider: String
    public let status: String
    public let isAvailable: Bool
    public let category: ModelCategory

    public enum ModelCategory: String, CaseIterable, Sendable {
        case apple = "Apple Foundation Models"
        case local = "HuggingFace Local Models"
        case openRouter = "OpenRouter Cloud Models"
        case custom = "Custom Models"
    }

    public init(modelID: String, name: String, provider: String, status: String, isAvailable: Bool, category: ModelCategory) {
        self.modelID = modelID
        self.name = name
        self.provider = provider
        self.status = status
        self.isAvailable = isAvailable
        self.category = category
    }
}

// MARK: - Assist Model Filter

@MainActor
public final class AssistModelFilter {
    public static let shared = AssistModelFilter()

    private init() {}

    public var disabledModelIDs: Set<String> {
        get {
            let array = UserDefaults.standard.stringArray(forKey: "com.swiftcode.assist.disabled_models") ?? []
            return Set(array)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: "com.swiftcode.assist.disabled_models")
        }
    }

    public func isEnabled(_ modelID: String) -> Bool {
        return !disabledModelIDs.contains(modelID)
    }

    public func toggleModel(_ modelID: String, enabled: Bool) {
        var current = disabledModelIDs
        if enabled {
            current.remove(modelID)
        } else {
            current.insert(modelID)
        }
        disabledModelIDs = current
    }
}

// MARK: - Assist v4 Continuous Multi-Goal Autonomous Takeover Models

public enum GoalStatus: String, Codable, Sendable {
    case pending = "Pending"
    case inProgress = "In Progress"
    case completed = "Completed"
    case failed = "Failed"
    case rejected = "Rejected"
    case skipped = "Skipped"
}

public struct GoalProvenance: Codable, Sendable {
    public let createdReason: String
    public let evidenceTrigger: String
    public let relationshipToRoot: String
    public let parentGoalId: UUID?
    public let generationDepth: Int
    public let timestamp: Date

    public init(
        createdReason: String,
        evidenceTrigger: String,
        relationshipToRoot: String,
        parentGoalId: UUID? = nil,
        generationDepth: Int = 1,
        timestamp: Date = Date()
    ) {
        self.createdReason = createdReason
        self.evidenceTrigger = evidenceTrigger
        self.relationshipToRoot = relationshipToRoot
        self.parentGoalId = parentGoalId
        self.generationDepth = generationDepth
        self.timestamp = timestamp
    }
}

public struct AssistGoal: Identifiable, Codable, Sendable {
    public let id: UUID
    public let title: String
    public let detailedObjective: String
    public var status: GoalStatus
    public let provenance: GoalProvenance
    public var dependencies: [UUID]
    public var expectedOutcome: String
    public var executionResult: String?
    public var verificationResult: String?
    public var filesModified: [String]
    public var startedAt: Date?
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        detailedObjective: String,
        status: GoalStatus = .pending,
        provenance: GoalProvenance,
        dependencies: [UUID] = [],
        expectedOutcome: String,
        executionResult: String? = nil,
        verificationResult: String? = nil,
        filesModified: [String] = [],
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.detailedObjective = detailedObjective
        self.status = status
        self.provenance = provenance
        self.dependencies = dependencies
        self.expectedOutcome = expectedOutcome
        self.executionResult = executionResult
        self.verificationResult = verificationResult
        self.filesModified = filesModified
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

/// Evaluates candidates against runaway autonomous expansion safeguards.
public struct AssistGoalSafeguards: Sendable {
    public static let maxDepth = 5
    public static let maxTotalExpandedGoals = 8
    public static let maxConsecutiveFailures = 2

    /// Validates candidate goals against all safety constraints.
    public static func validateCandidate(
        candidateTitle: String,
        candidateObjective: String,
        existingGoals: [AssistGoal],
        rootGoal: String,
        depth: Int,
        consecutiveFailures: Int
    ) -> (isValid: Bool, rejectionReason: String?) {
        // 1. Circuit breaker on repeated failures
        if consecutiveFailures >= maxConsecutiveFailures {
            return (false, "Safeguard Triggered: Repeated verification failure circuit breaker active (\(consecutiveFailures) consecutive failures).")
        }

        // 2. Goal Explosion: Generation Depth
        if depth > maxDepth {
            return (false, "Safeguard Triggered: Goal tree depth (\(depth)) exceeds maximum allowed depth (\(maxDepth)).")
        }

        // 3. Goal Explosion: Total Count
        if existingGoals.count >= maxTotalExpandedGoals {
            return (false, "Safeguard Triggered: Total expanded goal limit (\(maxTotalExpandedGoals)) reached.")
        }

        let normalizedCandidate = candidateTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 4. Duplicate / Circular Goal Detection
        for existing in existingGoals {
            let normalizedExisting = existing.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedCandidate == normalizedExisting {
                return (false, "Safeguard Triggered: Duplicate goal detected ('\(candidateTitle)').")
            }

            // Word overlap / token similarity
            let candTokens = Set(normalizedCandidate.split(separator: " "))
            let existTokens = Set(normalizedExisting.split(separator: " "))
            let intersection = candTokens.intersection(existTokens)
            if candTokens.count >= 3 && intersection.count >= candTokens.count - 1 {
                return (false, "Safeguard Triggered: Repetitive/near-identical goal detected ('\(candidateTitle)').")
            }
        }

        // 5. Unrelated Work Safeguard (Grounding check)
        let rootTokens = Set(rootGoal.lowercased().split(separator: " ").filter { $0.count > 3 })
        let candTokens = Set(candidateObjective.lowercased().split(separator: " ").filter { $0.count > 3 })

        // Check if candidate shares domain context or common engineering actions
        let commonEngineeringVerbs = ["test", "verify", "lint", "doc", "document", "error", "guard", "robust", "refactor", "benchmark", "spec", "clean"]
        let hasEngineeringLink = candidateObjective.lowercased().split(separator: " ").contains { commonEngineeringVerbs.contains(String($0)) }
        let hasRootDomainOverlap = !rootTokens.intersection(candTokens).isEmpty

        if !hasEngineeringLink && !hasRootDomainOverlap {
            return (false, "Safeguard Triggered: Goal lacks semantic alignment with root task ('\(candidateTitle)').")
        }

        return (true, nil)
    }
}

public struct MultiGoalSessionSummary: Codable, Sendable {
    public let rootGoal: String
    public let goals: [AssistGoal]
    public let totalGoalsCompleted: Int
    public let totalDuration: TimeInterval
    public let totalFilesModified: Int
    public let overallOutcome: String

    public init(
        rootGoal: String,
        goals: [AssistGoal],
        totalGoalsCompleted: Int,
        totalDuration: TimeInterval,
        totalFilesModified: Int,
        overallOutcome: String
    ) {
        self.rootGoal = rootGoal
        self.goals = goals
        self.totalGoalsCompleted = totalGoalsCompleted
        self.totalDuration = totalDuration
        self.totalFilesModified = totalFilesModified
        self.overallOutcome = overallOutcome
    }
}

