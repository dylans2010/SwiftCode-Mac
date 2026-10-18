//
//  AssistIntentClassifier.swift
//  SwiftCode
//
//  Authoritative intent classification and tool routing engine for SwiftCode Assist.
//  Identifies primary user intent, extracts explicitly requested tools, determines task
//  complexity budgets, and provides deterministic fast-path execution routes.
//

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

@MainActor
public final class AssistIntentClassifier: Sendable {
    public static let shared = AssistIntentClassifier()

    private init() {}

    /// Classifies user text into structured intent, profile, and routing recommendations.
    public func classify(prompt: String, activeFile: String? = nil) -> IntentClassificationResult {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // 1. Check for explicit tool priority requests
        let explicit = detectExplicitTool(lower: lower, original: trimmed, activeFile: activeFile)

        // 1a. Explicit `@Reverse` invocation: deterministic route to the
        // native Reverse subsystem. The parser only fires when the
        // message STARTS with @Reverse, so incidental prose mentions
        // never reach this branch. A missing/invalid target is NOT
        // filtered here: the adapter returns an actionable error
        // instead of silence.
        if let reverse = ReverseCommandParser.parse(message: trimmed) {
            var input: [String: Any] = [
                "targetPath": reverse.targetPath ?? "",
                "operation": reverse.operation.rawValue,
                "task": reverse.task,
            ]
            if let objdump = reverse.objdumpOperation {
                input["objdumpOperation"] = objdump.rawValue
            }
            if let symbol = reverse.symbol {
                input["symbol"] = symbol
            }
            return IntentClassificationResult(
                primaryIntent: .complexEngineering(goal: trimmed),
                profile: .moderate,
                explicitTool: ExplicitToolRequest(toolId: "reverse_analyze", suggestedInput: input, explanation: "Explicit @Reverse investigation routed to the native Reverse subsystem"),
                deterministicToolId: "reverse_analyze",
                deterministicInput: input,
                confidence: 0.99,
                explanation: "Explicit @Reverse command routed to reverse_analyze"
            )
        }

        // 2. High-confidence Git Operations
        if isGitStatusRequest(lower) {
            return IntentClassificationResult(
                primaryIntent: .git(action: .status, details: [:]),
                profile: .simple,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "version_control_operator", suggestedInput: ["action": "status"], explanation: "Inspect git working tree status"),
                deterministicToolId: "version_control_operator",
                deterministicInput: ["action": "status"],
                confidence: 0.98,
                explanation: "Direct Git status request routed to native version control operator"
            )
        }

        if isGitDiffRequest(lower) {
            return IntentClassificationResult(
                primaryIntent: .git(action: .diff, details: [:]),
                profile: .simple,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "version_control_operator", suggestedInput: ["action": "diff"], explanation: "Inspect working tree diff"),
                deterministicToolId: "version_control_operator",
                deterministicInput: ["action": "diff"],
                confidence: 0.95,
                explanation: "Direct Git diff request routed to native version control operator"
            )
        }

        if isGitCommitRequest(lower) {
            let msg = extractCommitMessage(from: trimmed) ?? "Assist automated commit"
            return IntentClassificationResult(
                primaryIntent: .git(action: .commit, details: ["message": msg]),
                profile: .moderate,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "version_control_operator", suggestedInput: ["action": "commit", "message": msg], explanation: "Commit changes using git"),
                deterministicToolId: "version_control_operator",
                deterministicInput: ["action": "commit", "message": msg],
                confidence: 0.95,
                explanation: "Git commit request routed to native version control operator"
            )
        }

        if isGitBranchRequest(lower) {
            let branch = extractBranchName(from: trimmed) ?? "status"
            return IntentClassificationResult(
                primaryIntent: .git(action: .branch, details: ["name": branch]),
                profile: .simple,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "version_control_operator", suggestedInput: ["action": "branch", "name": branch], explanation: "Inspect or manage git branch"),
                deterministicToolId: "version_control_operator",
                deterministicInput: ["action": "branch", "name": branch],
                confidence: 0.92,
                explanation: "Git branch request routed to native version control operator"
            )
        }

        // 3. High-confidence Build Operations
        if isBuildRequest(lower) {
            let scheme = extractScheme(from: trimmed)
            let config = lower.contains("release") ? "Release" : "Debug"
            var input: [String: Any] = ["configuration": config]
            if let s = scheme { input["scheme"] = s }

            return IntentClassificationResult(
                primaryIntent: .build(scheme: scheme, configuration: config),
                profile: .simple,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "project_build", suggestedInput: input, explanation: "Build active project"),
                deterministicToolId: "project_build",
                deterministicInput: input,
                confidence: 0.95,
                explanation: "Direct build request routed to native project build tool"
            )
        }

        // 4. High-confidence Test Operations
        if isTestRequest(lower) {
            return IntentClassificationResult(
                primaryIntent: .test(target: nil),
                profile: .moderate,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "project_test", suggestedInput: [:], explanation: "Run project tests"),
                deterministicToolId: "project_test",
                deterministicInput: [:],
                confidence: 0.92,
                explanation: "Test request routed to native test runner"
            )
        }

        // 5. High-confidence Finder Operations
        if isFinderOpenRequest(lower) {
            let path = extractPath(from: trimmed) ?? activeFile ?? "."
            return IntentClassificationResult(
                primaryIntent: .fileOperation(action: .openInFinder, path: path),
                profile: .simple,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "open_in_finder", suggestedInput: ["path": path], explanation: "Open item in Finder"),
                deterministicToolId: "open_in_finder",
                deterministicInput: ["path": path],
                confidence: 0.95,
                explanation: "Finder open request routed to native open_in_finder tool"
            )
        }

        if isFinderRevealRequest(lower) {
            let path = extractPath(from: trimmed) ?? activeFile ?? "."
            return IntentClassificationResult(
                primaryIntent: .fileOperation(action: .revealInFinder, path: path),
                profile: .simple,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "reveal_in_finder", suggestedInput: ["path": path], explanation: "Reveal item in Finder"),
                deterministicToolId: "reveal_in_finder",
                deterministicInput: ["path": path],
                confidence: 0.95,
                explanation: "Finder reveal request routed to native reveal_in_finder tool"
            )
        }

        // 6. High-confidence Symbol Search
        if isSymbolSearchRequest(lower) {
            let sym = extractSymbolName(from: trimmed)
            return IntentClassificationResult(
                primaryIntent: .codeSearch(type: .symbol, query: sym),
                profile: .simple,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "search_symbol", suggestedInput: ["symbolName": sym], explanation: "Locate symbol definition"),
                deterministicToolId: "search_symbol",
                deterministicInput: ["symbolName": sym],
                confidence: 0.90,
                explanation: "Symbol search routed to native symbol search tool"
            )
        }

        // 7. Explicit Worker Delegation Request
        if lower.contains("use_workers") || lower.contains("delegate to workers") || lower.contains("parallel workers") {
            return IntentClassificationResult(
                primaryIntent: .workerDelegation(tasks: []),
                profile: .complex,
                explicitTool: explicit ?? ExplicitToolRequest(toolId: "use_workers", suggestedInput: [:], explanation: "Coordinate subagent workers"),
                deterministicToolId: nil,
                deterministicInput: nil,
                confidence: 0.92,
                explanation: "Worker delegation request detected"
            )
        }

        // 8. Conversational greetings
        if isPureGreeting(lower) {
            return IntentClassificationResult(
                primaryIntent: .conversational(text: trimmed),
                profile: .simple,
                explicitTool: nil,
                deterministicToolId: nil,
                deterministicInput: nil,
                confidence: 0.99,
                explanation: "Standard conversational greeting"
            )
        }

        // 9. Complex multi-phase engineering tasks
        let isHeavy = lower.contains("rewrite") || lower.contains("from scratch") || lower.contains("create an app") || lower.contains("refactor the whole")
        let profile: TaskExecutionProfile = isHeavy ? .heavy : .complex

        return IntentClassificationResult(
            primaryIntent: .complexEngineering(goal: trimmed),
            profile: profile,
            explicitTool: explicit,
            deterministicToolId: nil,
            deterministicInput: nil,
            confidence: 0.75,
            explanation: "Multi-stage autonomous engineering task"
        )
    }

    // MARK: - Explicit Tool Request Detection

    private func detectExplicitTool(lower: String, original: String, activeFile: String?) -> ExplicitToolRequest? {
        if lower.contains("use the git tool") || lower.contains("use git tool") || lower.contains("run git status") {
            return ExplicitToolRequest(toolId: "version_control_operator", suggestedInput: ["action": "status"], explanation: "Explicitly requested Git tool")
        }
        if lower.contains("run the build tool") || lower.contains("use the build tool") || lower.contains("run build tool") {
            return ExplicitToolRequest(toolId: "project_build", suggestedInput: [:], explanation: "Explicitly requested build tool")
        }
        if lower.contains("use the test tool") || lower.contains("run the test tool") {
            return ExplicitToolRequest(toolId: "project_test", suggestedInput: [:], explanation: "Explicitly requested test tool")
        }
        if lower.contains("use use_workers") || lower.contains("use the worker tool") || lower.contains("use workers tool") {
            return ExplicitToolRequest(toolId: "use_workers", suggestedInput: [:], explanation: "Explicitly requested use_workers tool")
        }
        if lower.contains("use the file-search tool") || lower.contains("use search tool") || lower.contains("use file search tool") {
            let q = extractQuery(from: original) ?? ""
            return ExplicitToolRequest(toolId: "search_text", suggestedInput: ["query": q], explanation: "Explicitly requested search tool")
        }
        if lower.contains("open in finder") || lower.contains("open this in finder") {
            let p = extractPath(from: original) ?? activeFile ?? "."
            return ExplicitToolRequest(toolId: "open_in_finder", suggestedInput: ["path": p], explanation: "Explicitly requested open in Finder")
        }
        if lower.contains("reveal in finder") {
            let p = extractPath(from: original) ?? activeFile ?? "."
            return ExplicitToolRequest(toolId: "reveal_in_finder", suggestedInput: ["path": p], explanation: "Explicitly requested reveal in Finder")
        }
        return nil
    }

    // MARK: - Pattern Matching Helpers

    private func isGitStatusRequest(_ lower: String) -> Bool {
        return lower == "git status" ||
               lower == "check git status" ||
               lower == "check the current git status" ||
               lower == "check current git status" ||
               lower == "show git status" ||
               lower == "git state" ||
               lower.contains("check git status") ||
               lower.contains("check the git status") ||
               lower.contains("what is the git status") ||
               (lower.contains("git") && lower.contains("status"))
    }

    private func isGitDiffRequest(_ lower: String) -> Bool {
        return lower == "git diff" ||
               lower == "show git diff" ||
               lower.contains("git diff") ||
               lower.contains("check git diff") ||
               lower.contains("show working tree diff")
    }

    private func isGitCommitRequest(_ lower: String) -> Bool {
        return lower.hasPrefix("git commit") ||
               lower.contains("commit these changes") ||
               lower.contains("commit all changes") ||
               lower.contains("commit the changes")
    }

    private func isGitBranchRequest(_ lower: String) -> Bool {
        return lower == "git branch" ||
               lower.contains("current branch") ||
               lower.contains("which branch") ||
               lower.contains("show the current branch") ||
               lower.contains("create branch") ||
               lower.contains("checkout branch")
    }

    private func isBuildRequest(_ lower: String) -> Bool {
        return lower == "build this project" ||
               lower == "build project" ||
               lower == "run build" ||
               lower == "build the app" ||
               lower == "compile this project" ||
               lower == "compile project" ||
               lower.contains("build the project") ||
               lower.contains("build this project") ||
               lower.contains("run the project build")
    }

    private func isTestRequest(_ lower: String) -> Bool {
        return lower == "run tests" ||
               lower == "run the tests" ||
               lower == "test this project" ||
               lower.contains("execute unit tests") ||
               lower.contains("run the test suite")
    }

    private func isFinderOpenRequest(_ lower: String) -> Bool {
        return lower.contains("open in finder") ||
               lower.contains("open this file in finder") ||
               lower.contains("open the directory in finder")
    }

    private func isFinderRevealRequest(_ lower: String) -> Bool {
        return lower.contains("reveal in finder") ||
               lower.contains("reveal this file in finder") ||
               lower.contains("show in finder")
    }

    private func isSymbolSearchRequest(_ lower: String) -> Bool {
        return lower.contains("find the definition of") ||
               lower.contains("find symbol") ||
               lower.contains("where is") && (lower.contains("defined") || lower.contains("declared"))
    }

    private func isPureGreeting(_ lower: String) -> Bool {
        let greetings = ["hello", "hi", "hey", "good morning", "good afternoon", "howdy", "sup"]
        let words = lower.split(separator: " ").map { String($0) }
        guard let first = words.first else { return false }
        return greetings.contains(first) && words.count <= 3
    }

    private func extractCommitMessage(from text: String) -> String? {
        if let range = text.range(of: "message:") {
            return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = text.range(of: "-m ") {
            return String(text[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'\n\r\t "))
        }
        return nil
    }

    private func extractBranchName(from text: String) -> String? {
        let components = text.components(separatedBy: .whitespaces)
        if let idx = components.firstIndex(of: "branch"), idx + 1 < components.count {
            let candidate = components[idx + 1].trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if !candidate.isEmpty && candidate != "name" && candidate != "called" {
                return candidate
            }
        }
        return nil
    }

    private func extractScheme(from text: String) -> String? {
        let components = text.components(separatedBy: .whitespaces)
        if let idx = components.firstIndex(of: "scheme"), idx + 1 < components.count {
            return components[idx + 1].trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        }
        return nil
    }

    private func extractPath(from text: String) -> String? {
        let words = text.components(separatedBy: .whitespaces)
        for word in words {
            let clean = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`.,;()"))
            if clean.contains("/") || clean.hasSuffix(".swift") || clean.hasSuffix(".json") || clean.hasSuffix(".md") {
                return clean
            }
        }
        return nil
    }

    private func extractSymbolName(from text: String) -> String {
        let words = text.components(separatedBy: .whitespaces)
        if let idx = words.firstIndex(of: "function"), idx + 1 < words.count {
            return words[idx + 1].trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        }
        if let idx = words.firstIndex(of: "symbol"), idx + 1 < words.count {
            return words[idx + 1].trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        }
        if let idx = words.firstIndex(of: "of"), idx + 1 < words.count {
            return words[idx + 1].trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        }
        return words.last?.trimmingCharacters(in: CharacterSet.alphanumerics.inverted) ?? ""
    }

    private func extractQuery(from text: String) -> String? {
        if let range = text.range(of: "for ") {
            return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
