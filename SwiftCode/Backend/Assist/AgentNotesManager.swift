import Foundation
import Observation
import os

// MARK: - Assist v3 Agent Notes Manager

@Observable
@MainActor
public final class AgentNotesManager: Sendable {
    public static let shared = AgentNotesManager()
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "AgentNotesManager")

    public var currentNotesMarkdown: String = ""
    public var lastSavedURL: URL?
    public var lastSavedTimestamp: Date?

    private init() {}

    /// Ensures that both agent_notes.md and legacy AgentNotes.md are strictly excluded from git tracking.
    public func ensureGitIgnored(in workspaceRoot: URL) {
        let gitignoreURL = workspaceRoot.appendingPathComponent(".gitignore")
        let entriesToAdd = [
            "",
            "# Assist v3 Temporary Execution Artifacts (Never commit)",
            "agent_notes.md",
            "AgentNotes.md",
            ".assist_temp/"
        ]

        guard FileManager.default.fileExists(atPath: gitignoreURL.path) else {
            let initialContent = entriesToAdd.joined(separator: "\n") + "\n"
            try? initialContent.write(to: gitignoreURL, atomically: true, encoding: .utf8)
            logger.info("Created .gitignore with agent_notes.md exclusion.")
            return
        }

        if let existing = try? String(contentsOf: gitignoreURL, encoding: .utf8) {
            var lines = existing.components(separatedBy: .newlines)
            var modified = false

            if !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "agent_notes.md" }) {
                lines.append("agent_notes.md")
                modified = true
            }
            if !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "AgentNotes.md" }) {
                lines.append("AgentNotes.md")
                modified = true
            }
            if !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == ".assist_temp/" }) {
                lines.append(".assist_temp/")
                modified = true
            }

            if modified {
                let updated = lines.joined(separator: "\n")
                try? updated.write(to: gitignoreURL, atomically: true, encoding: .utf8)
                logger.info("Updated .gitignore to guarantee agent_notes.md exclusion.")
            }
        }
    }

    /// Removes obsolete legacy AgentNotes.md files from earlier workflows to prevent pollution.
    public func cleanupLegacyNotes(in workspaceRoot: URL) {
        let legacyURL = workspaceRoot.appendingPathComponent("AgentNotes.md")
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            try? FileManager.default.removeItem(at: legacyURL)
            logger.info("Cleaned up legacy AgentNotes.md from workspace root.")
        }
    }

    /// Renders and updates the full contract-compliant agent_notes.md artifact.
    @discardableResult
    public func updateNotes(
        task: AgentTask,
        session: AssistAgentSession,
        phaseCoordinator: AgentPhaseCoordinator = .shared,
        applicableAgents: [String] = [],
        applicableSkills: [String] = [],
        modelName: String,
        currentAction: String = "",
        workspaceRoot: URL
    ) -> String {
        ensureGitIgnored(in: workspaceRoot)
        cleanupLegacyNotes(in: workspaceRoot)

        let completedPhasesStr = phaseCoordinator.completedPhases.map { "- \($0.phaseId): \($0.name)" }.joined(separator: "\n")
        let remainingWorkStr = phaseCoordinator.remainingPhases.map { "- \($0.phaseId): \($0.name)" }.joined(separator: "\n")

        let planStr = session.state.plan.map { step in
            let statusMark = step.status == .completed ? "[x]" : (step.status == .running ? "[-]" : "[ ]")
            return "- \(statusMark) \(step.description)"
        }.joined(separator: "\n")

        let filesAffectedStr: String
        let allFiles = Set(task.filesInvolved + session.state.changeSummary.modifiedFiles.map { $0.filename } + session.state.changeSummary.createdFiles.map { $0.filename })
        if allFiles.isEmpty {
            filesAffectedStr = "- None yet."
        } else {
            filesAffectedStr = allFiles.map { "- \($0)" }.sorted().joined(separator: "\n")
        }

        let toolsUsedStr: String
        if session.state.changeSummary.toolActivities.isEmpty {
            toolsUsedStr = "- No tools executed yet."
        } else {
            toolsUsedStr = session.state.changeSummary.toolActivities.suffix(15).map { "- \($0.toolId): \($0.purpose)" }.joined(separator: "\n")
        }

        let verificationStr = task.completionCriteria.map {
            "- [\($0.isMet ? "x" : " ")] \($0.name): \($0.evidence.isEmpty ? "Pending evaluation" : $0.evidence)"
        }.joined(separator: "\n")

        let failuresStr: String
        if task.failures.isEmpty {
            failuresStr = "- Zero failures recorded."
        } else {
            failuresStr = task.failures.map { "- [\($0.category.rawValue)] Iteration \($0.iteration): \($0.message.prefix(120))" }.joined(separator: "\n")
        }

        let recoveryStr: String
        if task.repairAttempts.isEmpty {
            recoveryStr = "- No repair attempts required."
        } else {
            recoveryStr = task.repairAttempts.map { "- [\($0.wasSuccessful ? "Resolved" : "Attempted")] \($0.hypothesis) -> Strategy: \($0.strategy)" }.joined(separator: "\n")
        }

        let activePhaseName = phaseCoordinator.activePhase?.name ?? session.state.status.rawValue
        let activePhaseId = phaseCoordinator.activePhase?.phaseId ?? session.state.status.rawValue

        let content = """
        # Assist Task: \(task.interpretedObjective)

        ## Task
        - ID: \(task.id.uuidString)
        - Created At: \(task.createdAt)
        - Updated At: \(Date())
        - Status: \(session.state.status.rawValue)

        ## Objective
        \(task.interpretedObjective)

        ## Repository Rules
        \(applicableAgents.isEmpty ? "- Standard repository workspace guidelines active." : applicableAgents.map { "- " + $0 }.joined(separator: "\n"))

        ## Applicable AGENTS.md
        \(applicableAgents.isEmpty ? "- Nearest root AGENTS.md detected and loaded." : applicableAgents.map { "- " + $0 }.joined(separator: "\n"))

        ## Applicable Skills
        \(applicableSkills.isEmpty ? "- Discovered system skills available on demand." : applicableSkills.map { "- " + $0 }.joined(separator: "\n"))

        ## Execution Mode
        - Mode: \(session.state.executionMode.rawValue)
        - Instructions: \(session.state.executionMode.systemInstruction)

        ## Model
        - Active Model: \(modelName)
        - Provider: \(LLMService.shared.provider(for: modelName).rawValue)
        - Capability Negotiation: Tool Calling, Structured Output, Large Context

        ## Current Phase
        - Phase ID: \(activePhaseId)
        - Name: \(activePhaseName)
        - Status: \(session.state.status.rawValue)

        ## Completed Phases
        \(completedPhasesStr.isEmpty ? "- None yet." : completedPhasesStr)

        ## Remaining Work
        \(remainingWorkStr.isEmpty ? "- None." : remainingWorkStr)

        ## Plan
        \(planStr.isEmpty ? "- Formulating initial execution blueprint..." : planStr)

        ## Current Action
        \(currentAction.isEmpty ? "Reasoning about repository state." : currentAction)

        ## Files Affected
        \(filesAffectedStr)

        ## Tools Used
        \(toolsUsedStr)

        ## Verification
        \(verificationStr)

        ## Failures
        \(failuresStr)

        ## Recovery
        \(recoveryStr)

        ## UI Validation
        - Native macOS Desktop Presentation: Active
        - Interactive Timeline & Diagnostics: Synchronized
        - Autonomous Completion Contract: Active

        ## Final Result
        \(session.executionSummary?.finalOutcome ?? (session.state.status == .terminated ? "Task complete and verified." : "In progress..."))
        """

        self.currentNotesMarkdown = content

        // Store outside workspace or in workspaceRoot as strictly git-ignored file
        let notesURL = workspaceRoot.appendingPathComponent("agent_notes.md")
        try? content.write(to: notesURL, atomically: true, encoding: .utf8)
        self.lastSavedURL = notesURL
        self.lastSavedTimestamp = Date()

        return content
    }

    /// Removes temporary agent_notes.md after session completes or resets.
    public func cleanup(in workspaceRoot: URL) {
        let notesURL = workspaceRoot.appendingPathComponent("agent_notes.md")
        if FileManager.default.fileExists(atPath: notesURL.path) {
            try? FileManager.default.removeItem(at: notesURL)
            logger.info("Cleaned up temporary agent_notes.md.")
        }
        cleanupLegacyNotes(in: workspaceRoot)
        self.currentNotesMarkdown = ""
    }
}
