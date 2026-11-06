// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/Assist/AssistIntentClassifier.swift (lines 13–93 only)
//   (Legacy main ab03f681) — the intent-model types only: `GitAction`,
//   `FileAction`, `SearchType`, `CodingActionType`, `UserIntent`,
//   `TaskExecutionProfile`, `ExplicitToolRequest`, `IntentClassificationResult`.
//   The `AssistIntentClassifier` class itself (lines 94–802, ~708 lines of
//   rule-based matching) is NOT staged here: it exceeds the 600-line port
//   cap — see staging-wire/unowned/DISPOSITIONS.md (`AssistIntentClassifier`
//   row). Its only external dependency is `ReverseCommandParser`, staged in
//   this same batch, so the class is otherwise portable when the cap is
//   waived or the file is split.
//
// Destination: SwiftCodeAssistant/AssistIntentModels.swift.
//
// No adaptations: verbatim extract.
//
// LANDING NOTE — `FileAction` name collision: `SwiftCodeBuild` already
// declares a DIFFERENT `FileAction` (`compile`/`analyze`/`preprocess`/
// `assemble`, `SwiftCodeBuild/FileActions.swift`), used unqualified by
// `SwiftCodeUI/Window/WorkspaceWindowController+Product.swift:162–171`.
// Landing this file makes bare `FileAction` ambiguous in any module that
// imports both `SwiftCodeAssistant` and `SwiftCodeBuild`. Before landing,
// qualify the SwiftCodeBuild uses as `SwiftCodeBuild.FileAction` (or
// qualify this type's uses as `SwiftCodeAssistant.FileAction`). Do NOT
// rename either type silently: `AssistToolRouter` (same module) switches
// on this enum's cases (`.read` / `.write` / `.replace` / `.openInFinder` /
// `.revealInFinder`) and the classifier produces them.
// Referenced by live main code: `AssistToolRouter.filterTools(for:status:)`
// / `rankTools(for:)` / `capabilityScore(for:intent:)` take `UserIntent`;
// `AssistFeedbackService.collectUserIntentClassification` and
// `AssistAgentSession` call `AssistIntentClassifier.shared.classify`.

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

    // Natural-Language Tool Intelligence intents
    case screenshot(targetApp: String?, isRegion: Bool, purpose: String?)
    case screenRecording(targetApp: String?, duration: Double?, purpose: String?)
    case appInteraction(targetApp: String?, action: String?, targetElement: String?, purpose: String?)
    indirect case multiStep(intents: [UserIntent])
    case informational(topic: String)
}

public enum TaskExecutionProfile: String, Sendable, Codable {
    case simple      // 1 direct native call, no repo exploration, no execution_plan
    case moderate    // Targeted edit/inspection, minimal exploration
    case complex     // Multi-operation, dependency graph, workers if needed
    case heavy       // Project rewrite / scratch build, multi-milestone
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
