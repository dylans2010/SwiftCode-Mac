import Foundation

public enum GitAction: String, Sendable, Codable {
    case status
    case diff
    case commit
    case branch
    case rollback
    case log
}

public enum FileAction: String, Sendable, Codable {
    case read
    case write
    case replace
    case create
    case delete
    case move
    case rename
    case openInFinder
    case revealInFinder
}

public enum SearchType: String, Sendable, Codable {
    case symbol
    case text
    case regex
}

public enum CodingActionType: String, Sendable, Codable {
    case explain
    case refactor
    case documentation
    case preview
    case custom
}

public enum UserIntent: Sendable, Equatable {
    case git(action: GitAction, details: [String: String])
    case build(scheme: String?, configuration: String?)
    case test(target: String?)
    case codeSearch(type: SearchType, query: String)
    case fileOperation(action: FileAction, path: String?)
    case codingAction(action: CodingActionType, context: String?)
    case workerDelegation(tasks: [String])
    case complexEngineering(goal: String)
    case conversational(text: String)

    case screenshot(targetApp: String?, isRegion: Bool, purpose: String?)
    case screenRecording(targetApp: String?, duration: Double?, purpose: String?)
    case appInteraction(targetApp: String?, action: String?, targetElement: String?, purpose: String?)
    indirect case multiStep(intents: [UserIntent])
    case informational(topic: String)
}

public enum TaskExecutionProfile: String, Sendable, Codable {
    case simple
    case moderate
    case complex
    case heavy
}

public struct ExplicitToolRequest: @unchecked Sendable, Equatable {
    public let toolId: String
    public let suggestedInput: [String: Any]
    public let explanation: String

    public static func == (lhs: ExplicitToolRequest, rhs: ExplicitToolRequest) -> Bool {
        return lhs.toolId == rhs.toolId && lhs.explanation == rhs.explanation
    }
}

public struct IntentClassificationResult: @unchecked Sendable {
    public let primaryIntent: UserIntent
    public let profile: TaskExecutionProfile
    public let explicitTool: ExplicitToolRequest?
    public let deterministicToolId: String?
    public let deterministicInput: [String: Any]?
    public let confidence: Double
    public let explanation: String
}
