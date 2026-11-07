import Foundation
import SwiftUI

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

public enum AssistModelProvider: String, Codable, CaseIterable, Sendable {
    case openAI = "ChatGPT"
    case anthropic = "Claude"
    case gemini = "Gemini"
    case mistral = "Mistral"
    case meta = "Meta AI"
    case kimi = "Kimi"
    case openRouter = "OpenRouter"
    case openCode = "OpenCode"
    case hermes = "Hermes"
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

    var apiKeyProvider: APIKeyProvider? {
        switch self {
        case .openAI: return .openai
        case .anthropic: return .anthropic
        case .gemini: return .google
        case .mistral: return .mistral
        case .meta, .kimi: return .openRouter
        case .openRouter: return .openRouter
        case .openCode: return nil
        case .hermes: return nil
        case .codex: return .openai
        }
    }

    @MainActor
    public func storedAPIKey() async -> String? {
        guard let keyProvider = apiKeyProvider else { return nil }
        return await APIKeyManager.shared.retrieveKey(service: keyProvider)
    }

    var llmProvider: LLMProvider {
        switch self {
        case .openAI: return .openai
        case .anthropic: return .anthropic
        case .gemini: return .google
        case .mistral: return .mistral
        case .meta, .kimi, .openRouter: return .openRouter
        case .openCode: return .openRouter
        case .hermes: return .openRouter
        case .codex: return .codex
        }
    }

    public var endpoint: URL? {
        switch self {
        case .openAI: return URL(string: "https://api.openai.com/v1/chat/completions")
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/messages")
        case .gemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")
        case .mistral: return URL(string: "https://api.mistral.ai/v1/chat/completions")
        case .meta: return URL(string: "https://api.meta.ai/v1/chat/completions")
        case .kimi: return URL(string: "https://api.moonshot.cn/v1/chat/completions")
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/chat/completions")
        case .openCode: return OpenCodeConfiguration.load().serverURL
        case .hermes: return nil
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
        if provider == .openCode {
            return AssistAIResponse(
                content: "",
                success: false,
                error: "OpenCode models run through OpenCodeClient (see AgentModelAdapter), not LLMService. Select the model in Assist Settings and retry."
            )
        }
        if provider == .hermes {
            return AssistAIResponse(
                content: "",
                success: false,
                error: "Hermes models run through HermesProvider (see HermesSessionRunner), not LLMService. Select a Hermes model in Assist Settings and retry."
            )
        }
        do {
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

public struct AssistContext: Sendable {
    public let sessionId: UUID
    public let project: Project?
    public let workspaceRoot: URL
    public let memory: AssistMemoryGraphProtocol
    public let logger: AssistLoggerProtocol
    public let fileSystem: AssistFileSystemProtocol
    public let git: AssistGitManagerProtocol
    public let permissions: AssistPermissionsManagerProtocol

    public let safetyLevel: AssistSafetyLevel
    public let isAutonomous: Bool
    public let sessionExecutionMode: ExecutionMode

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
        isAutonomous: Bool,
        sessionExecutionMode: ExecutionMode = .autopilot
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
        self.sessionExecutionMode = sessionExecutionMode
    }
}

public enum AssistSafetyLevel: String, Codable, CaseIterable, Sendable {
    case conservative = "Conservative"
    case balanced = "Balanced"
    case aggressive = "Aggressive"
}

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
    public var toolErrorCode: AssistToolErrorCode? = nil

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
        code: AssistToolErrorCode? = nil,
        diagnostics: [String] = [],
        suggestedNextActions: [String] = []
    ) -> AssistToolResult {
        var result = AssistToolResult(
            success: false,
            output: "Error: \(error)",
            error: error,
            diagnostics: diagnostics,
            suggestedNextActions: suggestedNextActions
        )
        result.toolErrorCode = code
        return result
    }
}

public enum AssistToolDataKey {
    public static let content = "content"
    public static let explanation = "explanation"
    public static let diff = "diff"
    public static let testResults = "test_results"
    public static let buildStatus = "build_status"
    public static let searchResults = "results"
    public static let planId = "planId"
    public static let breakdown = "breakdown"
    public static let count = "count"
    public static let truncated = "truncated"
    public static let path = "path"
    public static let exitCode = "exitCode"
    public static let durationMs = "durationMs"
    public static let stdout = "stdout"
    public static let stderr = "stderr"
    public static let startLine = "startLine"
    public static let endLine = "endLine"
    public static let totalLines = "totalLines"
    public static let fullyAvailable = "fullyAvailable"
}

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

public struct AssistExecutionStep: Codable, Identifiable, Sendable {
    public let id: UUID
    public let toolId: String
    public let input: [String: String]
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

    public var isFixed: Bool { priority == .p0 }

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

public enum AssistStatus: String, Codable {
    case pending
    case inProgress
    case completed
    case failed
    case rejected
}

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
    public var content: String
    public let timestamp: Date
    public var attachments: [AgentFileContext]?
    public var mcpExecution: MCPExecutionMetadata?
    public var composioExecution: ComposioExecutionMetadata?
    public var activityGroup: AssistActivityGroup?
    public var thinkingContent: String?
    public var thinkingDuration: TimeInterval?
    public var noticeLevel: AssistNoticeLevel?
    public var serverError: ServerErrorDetail?
    public var providerID: String?
    public var envelope: AssistTaskEnvelope?
    public var modelId: String?
    public var tokenUsage: AssistTokenUsage?
    public var retryOfMessageID: UUID?
    public var regenerationCount: Int = 0

    public init(
        role: AssistRole,
        content: String,
        attachments: [AgentFileContext]? = nil,
        mcpExecution: MCPExecutionMetadata? = nil,
        composioExecution: ComposioExecutionMetadata? = nil,
        activityGroup: AssistActivityGroup? = nil,
        thinkingContent: String? = nil,
        thinkingDuration: TimeInterval? = nil,
        noticeLevel: AssistNoticeLevel? = nil,
        serverError: ServerErrorDetail? = nil,
        providerID: String? = nil,
        envelope: AssistTaskEnvelope? = nil,
        modelId: String? = nil,
        tokenUsage: AssistTokenUsage? = nil,
        retryOfMessageID: UUID? = nil,
        regenerationCount: Int = 0
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.attachments = attachments
        self.mcpExecution = mcpExecution
        self.composioExecution = composioExecution
        self.activityGroup = activityGroup
        self.thinkingContent = thinkingContent
        self.thinkingDuration = thinkingDuration
        self.noticeLevel = noticeLevel
        self.serverError = serverError
        self.providerID = providerID
        self.envelope = envelope
        self.modelId = modelId
        self.tokenUsage = tokenUsage
        self.retryOfMessageID = retryOfMessageID
        self.regenerationCount = regenerationCount
    }
}

public struct AssistTokenUsage: Codable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int

    public init(promptTokens: Int = 0, completionTokens: Int = 0, totalTokens: Int = 0) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

public enum AssistNoticeLevel: String, Codable, Sendable {
    case warning
    case error
}

public struct ServerErrorDetail: Codable, Sendable, Hashable {
    public let endpoint: String
    public let statusCode: Int?
    public let rawBody: String
    public let timestamp: Date

    public init(endpoint: String, statusCode: Int?, rawBody: String, timestamp: Date = Date()) {
        self.endpoint = endpoint
        self.statusCode = statusCode
        self.rawBody = rawBody
        self.timestamp = timestamp
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
    func deleteDirectory(at path: String) throws
    func moveFile(from: String, to: String) throws
    func copyFile(from: String, to: String) throws
    func exists(at path: String) -> Bool
    func appendFile(at path: String, content: String) throws
    func listDirectory(at path: String) throws -> [String]
    func createDirectory(at path: String) throws
    func resolve(_ path: String) throws -> URL
    var currentDirectory: URL { get }
    func setCurrentDirectory(_ path: String) throws -> URL
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

public struct AssistGoalSafeguards: Sendable {
    public static let maxDepth = 5
    public static let maxTotalExpandedGoals = 8
    public static let maxConsecutiveFailures = 2

    public static func validateCandidate(
        candidateTitle: String,
        candidateObjective: String,
        existingGoals: [AssistGoal],
        rootGoal: String,
        depth: Int,
        consecutiveFailures: Int
    ) -> (isValid: Bool, rejectionReason: String?) {
        if consecutiveFailures >= maxConsecutiveFailures {
            return (false, "Safeguard Triggered: Repeated verification failure circuit breaker active (\(consecutiveFailures) consecutive failures).")
        }

        if depth > maxDepth {
            return (false, "Safeguard Triggered: Goal tree depth (\(depth)) exceeds maximum allowed depth (\(maxDepth)).")
        }

        if existingGoals.count >= maxTotalExpandedGoals {
            return (false, "Safeguard Triggered: Total expanded goal limit (\(maxTotalExpandedGoals)) reached.")
        }

        let normalizedCandidate = candidateTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        for existing in existingGoals {
            let normalizedExisting = existing.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedCandidate == normalizedExisting {
                return (false, "Safeguard Triggered: Duplicate goal detected ('\(candidateTitle)').")
            }

            let candTokens = Set(normalizedCandidate.split(separator: " "))
            let existTokens = Set(normalizedExisting.split(separator: " "))
            let intersection = candTokens.intersection(existTokens)
            if candTokens.count >= 3 && intersection.count >= candTokens.count - 1 {
                return (false, "Safeguard Triggered: Repetitive/near-identical goal detected ('\(candidateTitle)').")
            }
        }

        let rootTokens = Set(rootGoal.lowercased().split(separator: " ").filter { $0.count > 3 })
        let candTokens = Set(candidateObjective.lowercased().split(separator: " ").filter { $0.count > 3 })

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

public struct QueuedAssistMessage: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var content: String
    public var attachments: [AgentFileContext]
    public let timestamp: Date
    public var envelope: AssistTaskEnvelope?

    public init(
        id: UUID = UUID(),
        content: String,
        attachments: [AgentFileContext] = [],
        timestamp: Date = Date(),
        envelope: AssistTaskEnvelope? = nil
    ) {
        self.id = id
        self.content = content
        self.attachments = attachments
        self.timestamp = timestamp
        self.envelope = envelope
    }
}

public enum AssistModelEligibilityError: LocalizedError, Equatable {
    case ineligibleModel(modelID: String, provider: String?)
    case noEligibleFreeModelAvailable(provider: String?)

    public var errorDescription: String? {
        switch self {
        case .ineligibleModel(let modelID, let provider):
            let provStr = provider.map { " on provider '\($0)'" } ?? ""
            return "Model '\(modelID)'\(provStr) is ineligible under the 'Only Use Free Models' policy. The model ID must contain 'free' (case-insensitive)."
        case .noEligibleFreeModelAvailable(let provider):
            let provStr = provider.map { " for provider '\($0)'" } ?? ""
            return "No eligible free model is available\(provStr). Please disable 'Only Use Free Models' or select a provider that offers free models."
        }
    }
}

public struct AssistModelEligibilityPolicy {

    public static func isEligible(modelID: String, onlyUseFreeModels: Bool) -> Bool {
        guard onlyUseFreeModels else { return true }
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.localizedCaseInsensitiveContains("free")
    }

    public static func validateExecutionEligibility(modelID: String, provider: String? = nil, onlyUseFreeModels: Bool) throws {
        guard onlyUseFreeModels else { return }
        if !isEligible(modelID: modelID, onlyUseFreeModels: true) {
            throw AssistModelEligibilityError.ineligibleModel(modelID: modelID, provider: provider)
        }
    }

    public static func filterEligibleModelIDs(_ modelIDs: [String], onlyUseFreeModels: Bool) -> [String] {
        guard onlyUseFreeModels else { return modelIDs }
        return modelIDs.filter { isEligible(modelID: $0, onlyUseFreeModels: true) }
    }

    public static func filterEligible<T>(_ models: [T], onlyUseFreeModels: Bool, idKeyPath: KeyPath<T, String>) -> [T] {
        guard onlyUseFreeModels else { return models }
        return models.filter { isEligible(modelID: $0[keyPath: idKeyPath], onlyUseFreeModels: true) }
    }

    public static func filterEligible<T>(_ models: [T], onlyUseFreeModels: Bool, idExtractor: (T) -> String) -> [T] {
        guard onlyUseFreeModels else { return models }
        return models.filter { isEligible(modelID: idExtractor($0), onlyUseFreeModels: true) }
    }
}
