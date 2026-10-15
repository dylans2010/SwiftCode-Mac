//
//  AssistConversationMemory.swift
//  SwiftCode
//
//  Authoritative multi-turn conversation memory and context persistence for SwiftCode Assist.
//  Preserves turn history, inspected files, user decisions, build states, and rolling summaries
//  scoped to the active conversation and project workspace.
//

import Foundation

public struct ConversationTurnRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let userPrompt: String
    public let intentSummary: String
    public var executedTools: [String]
    public var filesInspected: [String]
    public var filesModified: [String]
    public var buildOutcome: String?
    public var finalSummary: String?
    public var keyDecisions: [String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        userPrompt: String,
        intentSummary: String,
        executedTools: [String] = [],
        filesInspected: [String] = [],
        filesModified: [String] = [],
        buildOutcome: String? = nil,
        finalSummary: String? = nil,
        keyDecisions: [String] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.userPrompt = userPrompt
        self.intentSummary = intentSummary
        self.executedTools = executedTools
        self.filesInspected = filesInspected
        self.filesModified = filesModified
        self.buildOutcome = buildOutcome
        self.finalSummary = finalSummary
        self.keyDecisions = keyDecisions
    }
}

@MainActor
public final class AssistConversationMemory: Sendable {
    public static let shared = AssistConversationMemory()

    private var activeConversationId: UUID?
    private var workspaceRootPath: String = ""
    public private(set) var turns: [ConversationTurnRecord] = []
    public private(set) var inspectedFiles: Set<String> = []
    public private(set) var modifiedFiles: Set<String> = []
    public private(set) var establishedDecisions: [String] = []
    public private(set) var rollingSummary: String = ""
    public private(set) var lastVerifiedBuildOutcome: String?

    private init() {}

    /// Binds memory to the active conversation and workspace root. Clears state only if switching to an unrelated conversation.
    public func bindConversation(id: UUID, workspaceRoot: URL) {
        let rootPath = workspaceRoot.path
        if activeConversationId != id || workspaceRootPath != rootPath {
            activeConversationId = id
            workspaceRootPath = rootPath
            turns = []
            inspectedFiles = []
            modifiedFiles = []
            establishedDecisions = []
            rollingSummary = ""
            lastVerifiedBuildOutcome = nil
        }
    }

    /// Records the start of a new turn in the active conversation.
    public func recordTurnStart(prompt: String, intent: String) -> UUID {
        let turn = ConversationTurnRecord(userPrompt: prompt, intentSummary: intent)
        turns.append(turn)
        return turn.id
    }

    /// Records an inspected file.
    public func recordFileInspected(_ path: String) {
        inspectedFiles.insert(path)
        if let idx = turns.indices.last {
            if !turns[idx].filesInspected.contains(path) {
                turns[idx].filesInspected.append(path)
            }
        }
    }

    /// Records a modified file.
    public func recordFileModified(_ path: String) {
        modifiedFiles.insert(path)
        if let idx = turns.indices.last {
            if !turns[idx].filesModified.contains(path) {
                turns[idx].filesModified.append(path)
            }
        }
    }

    /// Records a tool execution in the active turn.
    public func recordToolExecution(toolId: String) {
        if let idx = turns.indices.last {
            turns[idx].executedTools.append(toolId)
        }
    }

    /// Records a build outcome.
    public func recordBuildOutcome(_ outcome: String) {
        lastVerifiedBuildOutcome = outcome
        if let idx = turns.indices.last {
            turns[idx].buildOutcome = outcome
        }
    }

    /// Records a key decision or constraint established by the user.
    public func recordDecision(_ decision: String) {
        if !establishedDecisions.contains(decision) {
            establishedDecisions.append(decision)
        }
        if let idx = turns.indices.last {
            turns[idx].keyDecisions.append(decision)
        }
    }

    /// Finalizes the current turn with a summary and updates the rolling summary.
    public func finalizeTurn(summary: String) {
        guard let idx = turns.indices.last else { return }
        turns[idx].finalSummary = summary
        updateRollingSummary()
    }

    private func updateRollingSummary() {
        var lines: [String] = []
        if !establishedDecisions.isEmpty {
            lines.append("Established Constraints: " + establishedDecisions.joined(separator: "; "))
        }
        if !modifiedFiles.isEmpty {
            lines.append("Modified Files: " + Array(modifiedFiles).sorted().joined(separator: ", "))
        }
        if let build = lastVerifiedBuildOutcome {
            lines.append("Last Build Status: " + build)
        }
        let completedSummaries = turns.compactMap { turn -> String? in
            guard let s = turn.finalSummary else { return nil }
            return "Turn '\(turn.userPrompt.prefix(40))': \(s.prefix(120))"
        }
        if !completedSummaries.isEmpty {
            lines.append("Prior Completed Milestones: " + completedSummaries.joined(separator: " | "))
        }
        rollingSummary = lines.joined(separator: "\n")
    }

    /// Assembles compact historical context suitable for prompt injection.
    public func buildHistoricalContextPrompt() -> String {
        guard turns.count > 1 || !rollingSummary.isEmpty else { return "" }

        var prompt = "# CONVERSATION CONTINUITY & HISTORICAL CONTEXT\n"
        if !rollingSummary.isEmpty {
            prompt += "## Rolling Summary of Completed Decisions & Work\n\(rollingSummary)\n\n"
        }

        let priorTurns = turns.dropLast()
        if !priorTurns.isEmpty {
            prompt += "## Recent Turn Context (Chronological)\n"
            for turn in priorTurns.suffix(4) {
                prompt += "- User: \"\(turn.userPrompt)\"\n"
                if !turn.executedTools.isEmpty {
                    prompt += "  Executed: \(turn.executedTools.joined(separator: ", "))\n"
                }
                if let outcome = turn.finalSummary {
                    prompt += "  Result: \(outcome.prefix(160))\n"
                }
            }
        }
        return prompt
    }

    /// Resets all memory (e.g. when clearing the chat completely).
    public func reset() {
        activeConversationId = nil
        workspaceRootPath = ""
        turns = []
        inspectedFiles = []
        modifiedFiles = []
        establishedDecisions = []
        rollingSummary = ""
        lastVerifiedBuildOutcome = nil
    }
}
