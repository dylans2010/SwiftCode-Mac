import Foundation
import SwiftUI

// MARK: - AI Models & Providers

public enum AssistModelProvider: String, Codable, CaseIterable {
    case openAI = "ChatGPT"
    case anthropic = "Claude"
    case gemini = "Gemini"
    case mistral = "Mistral"
    case meta = "Meta AI"
    case kimi = "Kimi"
    case openRouter = "OpenRouter"
    case codex = "Codex"

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

    public init(success: Bool, output: String, data: [String: String]? = nil, error: String? = nil, errorCode: Int? = nil) {
        self.success = success
        self.output = output
        self.data = data
        self.error = error
        self.errorCode = errorCode
    }

    public static func success(_ output: String, data: [String: String]? = nil) -> AssistToolResult {
        AssistToolResult(success: true, output: output, data: data)
    }

    public static func failure(_ error: String, code: Int? = nil) -> AssistToolResult {
        AssistToolResult(success: false, output: "Error: \(error)", error: error, errorCode: code)
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

// MARK: - Legacy / UI Compatibility Models

/// Maintained for UI compatibility
public enum AssistStatus: String, Codable {
    case pending
    case inProgress
    case completed
    case failed
    case rejected
}

public struct AssistMessage: Codable, Identifiable, Sendable {
    public let id: UUID
    public let role: AssistRole
    public let content: String
    public let timestamp: Date
    public var attachments: [AgentFileContext]?

    public init(role: AssistRole, content: String, attachments: [AgentFileContext]? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.attachments = attachments
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
