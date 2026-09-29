import Foundation

public struct AgentContext: Sendable, Codable {
    public let repoManifestSummary: String
    public let taskObjective: String
    public let currentPlan: AssistExecutionPlan?
    public let completedActions: [String]
    public let remainingActions: [String]
    public let activeFileContents: [String: String]
    public let recentToolResults: [String]
    public let recentBuildErrors: [String]
    public let repositoryInstructions: String
    public let failureHistorySummary: String
    public let verificationStatusSummary: String

    public init(
        repoManifestSummary: String,
        taskObjective: String,
        currentPlan: AssistExecutionPlan? = nil,
        completedActions: [String] = [],
        remainingActions: [String] = [],
        activeFileContents: [String: String] = [:],
        recentToolResults: [String] = [],
        recentBuildErrors: [String] = [],
        repositoryInstructions: String = "",
        failureHistorySummary: String = "",
        verificationStatusSummary: String = ""
    ) {
        self.repoManifestSummary = repoManifestSummary
        self.taskObjective = taskObjective
        self.currentPlan = currentPlan
        self.completedActions = completedActions
        self.remainingActions = remainingActions
        self.activeFileContents = activeFileContents
        self.recentToolResults = recentToolResults
        self.recentBuildErrors = recentBuildErrors
        self.repositoryInstructions = repositoryInstructions
        self.failureHistorySummary = failureHistorySummary
        self.verificationStatusSummary = verificationStatusSummary
    }
}

// MARK: - Context Engine

public final class AssistContextEngine: @unchecked Sendable {
    private let context: AssistContext
    private let lock = NSLock()
    private var _pressureState: ContextPressureState
    private var _compactionLog: [CompactionRecord] = []
    private var _hierarchicalSummaries: [HierarchicalSummary] = []
    private var _compactedToolResults: [String: CompactedToolResult] = [:]
    private var _sourceSizes: [String: Int] = [:]

    private var fileContentCache: [String: (mtime: Date, content: String)] = [:]

    public init(context: AssistContext) {
        self.context = context
        self._pressureState = ContextPressureState(
            capacity: 128_000,
            estimatedUsage: 0,
            safetyMargin: 2048,
            compactionStatus: .none,
            summaryDepth: 0,
            lastCompaction: nil,
            sourceSizes: [:]
        )
    }

    // MARK: - Token Estimation

    public func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }

    public func estimateTokens(for sections: [ModelContextSection]) -> Int {
        sections.reduce(0) { $0 + $1.estimatedTokens }
    }

    // MARK: - Context Budget

    public func calculateBudget(modelId: String, systemPromptLength: Int) -> ContextBudget {
        let overhead = max(1, systemPromptLength / 4)
        let capacity = modelContextWindow(for: modelId)
        return ContextBudget(
            modelCapacity: capacity,
            systemPromptOverhead: overhead,
            responseReserve: 4096,
            toolCallReserve: 2048,
            safetyMargin: 2048
        )
    }

    private func modelContextWindow(for modelId: String) -> Int {
        switch modelId.lowercased() {
        case let id where id.contains("claude"): return 200_000
        case let id where id.contains("gpt-4o"): return 128_000
        case let id where id.contains("gemini"): return 1_000_000
        case let id where id.contains("codex"): return 32_000
        case let id where id.contains("apple"): return 8192
        default: return 128_000
        }
    }

    // MARK: - Context Pressure Monitor

    public func updatePressureState(estimatedUsage: Int, capacity: Int) {
        let ratio = capacity > 0 ? Double(estimatedUsage) / Double(capacity) : 0
        let status: ContextPressureState.CompactionStatus
        if ratio > 0.9 {
            status = .aggressive
        } else if ratio > 0.75 {
            status = .moderate
        } else if ratio > 0.5 {
            status = .light
        } else {
            status = .none
        }

        lock.lock()
        defer { lock.unlock() }
        _pressureState = ContextPressureState(
            capacity: capacity,
            estimatedUsage: estimatedUsage,
            safetyMargin: _pressureState.safetyMargin,
            compactionStatus: status,
            summaryDepth: _pressureState.summaryDepth,
            lastCompaction: _pressureState.lastCompaction,
            sourceSizes: _sourceSizes
        )
    }

    public func getPressureState() -> ContextPressureState {
        lock.lock()
        defer { lock.unlock() }
        return _pressureState
    }

    // MARK: - Tool Output Compaction

    public func compactToolResult(_ result: AssistToolResult, toolId: String) -> CompactedToolResult {
        lock.lock()
        if let existing = _compactedToolResults[toolId] {
            lock.unlock()
            return existing
        }
        lock.unlock()

        let output = result.output
        let errors = extractErrors(from: output)
        let warnings = extractWarnings(from: output)
        let keyOutput = extractKeyOutput(from: output, success: result.success)
        let summary = generateToolSummary(toolId: toolId, result: result, errors: errors, warnings: warnings)

        let compacted = CompactedToolResult(
            toolId: toolId,
            success: result.success,
            summary: summary,
            errors: errors,
            warnings: warnings,
            keyOutput: keyOutput,
            filesChanged: result.filesChanged,
            exitCode: result.exitCode,
            originalOutput: output.count > 10_000 ? nil : output
        )

        lock.lock()
        _compactedToolResults[toolId] = compacted
        lock.unlock()
        return compacted
    }

    private func extractErrors(from output: String) -> [String] {
        var errors: [String] = []
        for line in output.components(separatedBy: "\n") {
            let lower = line.lowercased()
            if lower.contains("error:") || lower.contains("failed") || lower.contains("fatal") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && trimmed.count < 500 {
                    errors.append(trimmed)
                }
            }
            if errors.count >= 5 { break }
        }
        return errors
    }

    private func extractWarnings(from output: String) -> [String] {
        var warnings: [String] = []
        for line in output.components(separatedBy: "\n") {
            let lower = line.lowercased()
            if lower.contains("warning:") || lower.contains("deprecated") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && trimmed.count < 300 {
                    warnings.append(trimmed)
                }
            }
            if warnings.count >= 3 { break }
        }
        return warnings
    }

    private func extractKeyOutput(from output: String, success: Bool) -> String {
        let lines = output.components(separatedBy: "\n")
        let maxLines = success ? 10 : 20

        var keyLines: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("+") || trimmed.hasPrefix("-") || trimmed.hasPrefix("@@") {
                keyLines.append(trimmed)
            } else if trimmed.contains("Build") || trimmed.contains("Test") || trimmed.contains("passed") || trimmed.contains("failed") {
                keyLines.append(trimmed)
            }
            if keyLines.count >= maxLines { break }
        }

        if keyLines.isEmpty {
            return String(output.prefix(500))
        }
        return keyLines.joined(separator: "\n")
    }

    private func generateToolSummary(toolId: String, result: AssistToolResult, errors: [String], warnings: [String]) -> String {
        var parts: [String] = []
        parts.append("\(toolId): \(result.success ? "SUCCESS" : "FAILED")")

        if let exitCode = result.exitCode {
            parts.append("exit=\(exitCode)")
        }
        if !result.filesChanged.isEmpty {
            parts.append("files=[\(result.filesChanged.joined(separator: ", "))]")
        }
        if !errors.isEmpty {
            parts.append("\(errors.count) error(s)")
        }
        if !warnings.isEmpty {
            parts.append("\(warnings.count) warning(s)")
        }
        if !result.diagnostics.isEmpty {
            parts.append("diagnostics=[\(result.diagnostics.prefix(2).joined(separator: "; "))]")
        }

        return parts.joined(separator: " | ")
    }

    // MARK: - Hierarchical Summaries

    public func addHierarchicalSummary(_ summary: HierarchicalSummary) {
        lock.lock()
        _hierarchicalSummaries.append(summary)
        if _hierarchicalSummaries.count > 50 {
            _hierarchicalSummaries.removeFirst(_hierarchicalSummaries.count - 50)
        }
        lock.unlock()
    }

    public func getSummaries(at level: HierarchicalSummary.SummaryLevel) -> [HierarchicalSummary] {
        lock.lock()
        defer { lock.unlock() }
        return _hierarchicalSummaries.filter { $0.level == level }
    }

    public func compactRecentEvents(events: [AgentEvent]) -> HierarchicalSummary {
        let content = events.map { event in
            "[\(event.state.rawValue)] \(event.summary)"
        }.joined(separator: "\n")

        let summary = HierarchicalSummary(
            level: .recentWindow,
            content: content,
            sourceEventCount: events.count
        )
        addHierarchicalSummary(summary)
        return summary
    }

    public func compactActionSummaries(actions: [String]) -> HierarchicalSummary {
        let content = actions.joined(separator: "\n- ")
        let summary = HierarchicalSummary(
            level: .actionSummary,
            content: "Completed actions:\n- \(content)",
            sourceEventCount: actions.count
        )
        addHierarchicalSummary(summary)
        return summary
    }

    // MARK: - Priority-Based Context Building

    public func buildPrioritizedContext(
        for objective: String,
        plan: AssistExecutionPlan? = nil,
        completedActions: [String] = [],
        remainingActions: [String] = [],
        recentResults: [AssistToolResult] = [],
        recentErrors: [String] = [],
        failureSummary: String = "",
        verificationSummary: String = "",
        activeFiles: [String] = [],
        skillsBlock: String = "",
        toolSchemas: String = "",
        attachmentsBlock: String = ""
    ) -> [ModelContextSection] {
        var sections: [ModelContextSection] = []

        // P0: Always preserve
        sections.append(contentsOf: buildP0Sections(
            objective: objective,
            recentErrors: recentErrors,
            failureSummary: failureSummary,
            verificationSummary: verificationSummary
        ))

        // P1: Important context
        sections.append(contentsOf: buildP1Sections(
            plan: plan,
            completedActions: completedActions,
            remainingActions: remainingActions,
            activeFiles: activeFiles,
            recentResults: recentResults,
            skillsBlock: skillsBlock,
            toolSchemas: toolSchemas,
            attachmentsBlock: attachmentsBlock
        ))

        // P2: Useful but compressible
        sections.append(contentsOf: buildP2Sections())

        return sections.sorted { $0.priority < $1.priority }
    }

    private func buildP0Sections(
        objective: String,
        recentErrors: [String],
        failureSummary: String,
        verificationSummary: String
    ) -> [ModelContextSection] {
        var sections: [ModelContextSection] = []

        let objectiveContent = """
        # ACTIVE OBJECTIVE
        \(objective)

        # CRITICAL CONSTRAINTS
        - Never use relative traversal (e.g. "..") or root paths (e.g. "/").
        - Always double check file paths before reading/writing.
        - Respond ONLY with valid JSON tool calls or finalResponse.
        """
        sections.append(ModelContextSection(
            priority: .p0,
            title: "Objective & Constraints",
            content: objectiveContent,
            estimatedTokens: estimateTokens(objectiveContent)
        ))

        if !recentErrors.isEmpty {
            let errorContent = """
            # UNRESOLVED ERRORS (MUST FIX)
            \(recentErrors.suffix(5).joined(separator: "\n"))
            """
            sections.append(ModelContextSection(
                priority: .p0,
                title: "Unresolved Errors",
                content: errorContent,
                estimatedTokens: estimateTokens(errorContent)
            ))
        }

        if !failureSummary.isEmpty {
            let failureContent = """
            # ACTIVE FAILURE OBSERVATIONS
            \(failureSummary)
            """
            sections.append(ModelContextSection(
                priority: .p0,
                title: "Failure History",
                content: failureContent,
                estimatedTokens: estimateTokens(failureContent)
            ))
        }

        if !verificationSummary.isEmpty {
            let verifyContent = """
            # VERIFICATION STATE
            \(verificationSummary)
            """
            sections.append(ModelContextSection(
                priority: .p0,
                title: "Verification State",
                content: verifyContent,
                estimatedTokens: estimateTokens(verifyContent)
            ))
        }

        return sections
    }

    private func buildP1Sections(
        plan: AssistExecutionPlan?,
        completedActions: [String],
        remainingActions: [String],
        activeFiles: [String],
        recentResults: [AssistToolResult],
        skillsBlock: String,
        toolSchemas: String,
        attachmentsBlock: String
    ) -> [ModelContextSection] {
        var sections: [ModelContextSection] = []

        let projectName = context.project?.name ?? "SwiftCode"
        let manifestContent = """
        # WORKSPACE
        Root: \(context.workspaceRoot.path)
        Project: \(projectName)
        """
        sections.append(ModelContextSection(
            priority: .p1,
            title: "Workspace",
            content: manifestContent,
            estimatedTokens: estimateTokens(manifestContent)
        ))

        if let plan = plan {
            let planContent = formatPlan(plan)
            sections.append(ModelContextSection(
                priority: .p1,
                title: "Current Plan",
                content: planContent,
                estimatedTokens: estimateTokens(planContent)
            ))
        }

        if !completedActions.isEmpty {
            let actionsContent = """
            # COMPLETED ACTIONS
            \(completedActions.suffix(10).joined(separator: "\n- "))
            """
            sections.append(ModelContextSection(
                priority: .p1,
                title: "Completed Actions",
                content: actionsContent,
                estimatedTokens: estimateTokens(actionsContent)
            ))
        }

        if !remainingActions.isEmpty {
            let remainingContent = """
            # REMAINING ACTIONS
            \(remainingActions.joined(separator: "\n- "))
            """
            sections.append(ModelContextSection(
                priority: .p1,
                title: "Remaining Actions",
                content: remainingContent,
                estimatedTokens: estimateTokens(remainingContent)
            ))
        }

        if !activeFiles.isEmpty {
            let filesContent = buildActiveFilesContent(activeFiles)
            sections.append(ModelContextSection(
                priority: .p1,
                title: "Active Files",
                content: filesContent,
                estimatedTokens: estimateTokens(filesContent)
            ))
        }

        if !recentResults.isEmpty {
            let resultsContent = buildCompactToolResults(recentResults)
            sections.append(ModelContextSection(
                priority: .p1,
                title: "Recent Tool Results",
                content: resultsContent,
                estimatedTokens: estimateTokens(resultsContent)
            ))
        }

        if !skillsBlock.isEmpty {
            sections.append(ModelContextSection(
                priority: .p1,
                title: "Skills",
                content: skillsBlock,
                estimatedTokens: estimateTokens(skillsBlock)
            ))
        }

        if !toolSchemas.isEmpty {
            sections.append(ModelContextSection(
                priority: .p1,
                title: "Tool Schemas",
                content: toolSchemas,
                estimatedTokens: estimateTokens(toolSchemas)
            ))
        }

        if !attachmentsBlock.isEmpty {
            sections.append(ModelContextSection(
                priority: .p1,
                title: "Attachments",
                content: attachmentsBlock,
                estimatedTokens: estimateTokens(attachmentsBlock)
            ))
        }

        return sections
    }

    private func buildP2Sections() -> [ModelContextSection] {
        var sections: [ModelContextSection] = []

        lock.lock()
        let summaries = _hierarchicalSummaries
        lock.unlock()

        if !summaries.isEmpty {
            let summaryContent = summaries.suffix(5).map { "[\($0.level.rawValue)] \($0.content)" }.joined(separator: "\n\n")
            sections.append(ModelContextSection(
                priority: .p2,
                title: "Historical Summaries",
                content: summaryContent,
                estimatedTokens: estimateTokens(summaryContent),
                isCompacted: true
            ))
        }

        return sections
    }

    private func formatPlan(_ plan: AssistExecutionPlan) -> String {
        var lines = ["# EXECUTION PLAN: \(plan.goal)"]
        for (index, step) in plan.steps.enumerated() {
            let status = step.status.rawValue.uppercased()
            lines.append("\(index + 1). [\(status)] \(step.description)")
        }
        return lines.joined(separator: "\n")
    }

    private func buildActiveFilesContent(_ files: [String]) -> String {
        var parts: [String] = ["# ACTIVE FILE CONTENTS"]
        for file in files.prefix(6) {
            if context.fileSystem.exists(at: file) {
                if let content = cachedFileContent(at: file, maxChars: 4000) {
                    parts.append("\n--- \(file) ---\n\(content)")
                }
            }
        }
        return parts.joined(separator: "\n")
    }

    private func buildCompactToolResults(_ results: [AssistToolResult]) -> String {
        var parts: [String] = ["# RECENT TOOL RESULTS"]
        for result in results.suffix(5) {
            let compacted = compactToolResult(result, toolId: UUID().uuidString)
            var entry = "- \(compacted.summary)"
            if !compacted.errors.isEmpty {
                entry += "\n  Errors: \(compacted.errors.prefix(2).joined(separator: "; "))"
            }
            if !compacted.keyOutput.isEmpty && compacted.keyOutput.count < 500 {
                entry += "\n  Output: \(compacted.keyOutput)"
            }
            parts.append(entry)
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - Context Compaction

    public func compactContext(
        sections: [ModelContextSection],
        budget: ContextBudget
    ) -> [ModelContextSection] {
        var compacted = sections
        var currentUsage = estimateTokens(for: compacted)

        guard currentUsage > budget.usableBudget else {
            updatePressureState(estimatedUsage: currentUsage, capacity: budget.modelCapacity)
            return compacted
        }

        // Phase 1: Compact P2 sections
        compacted = compactP2Sections(compacted)
        currentUsage = estimateTokens(for: compacted)

        // Phase 2: Compact P1 tool results
        if currentUsage > budget.usableBudget {
            compacted = compactP1ToolResults(compacted)
            currentUsage = estimateTokens(for: compacted)
        }

        // Phase 3: Compact P1 file contents
        if currentUsage > budget.usableBudget {
            compacted = compactP1FileContents(compacted)
            currentUsage = estimateTokens(for: compacted)
        }

        // Phase 4: Aggressive - compact everything except P0
        if currentUsage > budget.usableBudget {
            compacted = compactAggressive(compacted, budget: budget)
            currentUsage = estimateTokens(for: compacted)
        }

        let record = CompactionRecord(
            timestamp: Date(),
            originalTokens: estimateTokens(for: sections),
            compactedTokens: currentUsage,
            phasesApplied: determinePhasesApplied(original: sections, compacted: compacted)
        )
        lock.lock()
        _compactionLog.append(record)
        lock.unlock()

        updatePressureState(estimatedUsage: currentUsage, capacity: budget.modelCapacity)

        return compacted
    }

    private func compactP2Sections(_ sections: [ModelContextSection]) -> [ModelContextSection] {
        sections.map { section in
            guard section.priority == .p2 else { return section }
            let compactedContent = String(section.content.prefix(500)) + "\n... [SUMMARIZED]"
            return ModelContextSection(
                priority: section.priority,
                title: section.title,
                content: compactedContent,
                estimatedTokens: estimateTokens(compactedContent),
                isCompacted: true
            )
        }
    }

    private func compactP1ToolResults(_ sections: [ModelContextSection]) -> [ModelContextSection] {
        sections.map { section in
            guard section.priority == .p1 && section.title == "Recent Tool Results" else { return section }
            let lines = section.content.components(separatedBy: "\n")
            let compactedLines = Array(lines.prefix(3)) + ["... [TOOL RESULTS COMPACTED]"]
            let compactedContent = compactedLines.joined(separator: "\n")
            return ModelContextSection(
                priority: section.priority,
                title: section.title,
                content: compactedContent,
                estimatedTokens: estimateTokens(compactedContent),
                isCompacted: true
            )
        }
    }

    private func compactP1FileContents(_ sections: [ModelContextSection]) -> [ModelContextSection] {
        sections.map { section in
            guard section.priority == .p1 && section.title == "Active Files" else { return section }
            let fileMarker = "--- "
            var compactedParts: [String] = ["# ACTIVE FILE CONTENTS (COMPACTED)"]
            var currentFile = ""
            var currentContent: [String] = []

            for line in section.content.components(separatedBy: "\n") {
                if line.hasPrefix(fileMarker) && line.hasSuffix(" ---") {
                    if !currentFile.isEmpty {
                        let content = currentContent.joined(separator: "\n")
                        let truncated = content.count > 1000 ? String(content.prefix(1000)) + "\n... [TRUNCATED]" : content
                        compactedParts.append("\n--- \(currentFile) ---\n\(truncated)")
                    }
                    currentFile = String(line.dropFirst(4).dropLast(4))
                    currentContent = []
                } else {
                    currentContent.append(line)
                }
            }
            if !currentFile.isEmpty {
                let content = currentContent.joined(separator: "\n")
                let truncated = content.count > 1000 ? String(content.prefix(1000)) + "\n... [TRUNCATED]" : content
                compactedParts.append("\n--- \(currentFile) ---\n\(truncated)")
            }

            let compactedContent = compactedParts.joined(separator: "\n")
            return ModelContextSection(
                priority: section.priority,
                title: section.title,
                content: compactedContent,
                estimatedTokens: estimateTokens(compactedContent),
                isCompacted: true
            )
        }
    }

    private func compactAggressive(_ sections: [ModelContextSection], budget: ContextBudget) -> [ModelContextSection] {
        var result: [ModelContextSection] = []
        var remaining = budget.usableBudget

        let sorted = sections.sorted(by: { $0.priority < $1.priority })
        let p0Sections = sorted.filter { $0.priority == .p0 }
        let otherSections = sorted.filter { $0.priority != .p0 }

        for section in p0Sections {
            result.append(section)
        }

        for section in otherSections {
            let tokens = section.estimatedTokens
            if tokens <= remaining {
                result.append(section)
                remaining -= tokens
            }
        }

        return result
    }

    private func determinePhasesApplied(original: [ModelContextSection], compacted: [ModelContextSection]) -> [String] {
        var phases: [String] = []
        let origTokens = estimateTokens(for: original)
        let compactTokens = estimateTokens(for: compacted)

        if compactTokens < origTokens {
            phases.append("p2_summaries")
        }
        if compactTokens < origTokens / 2 {
            phases.append("p1_tool_results")
        }
        if compactTokens < origTokens / 3 {
            phases.append("p1_file_contents")
        }
        if compactTokens < origTokens / 4 {
            phases.append("aggressive")
        }

        return phases
    }

    // MARK: - Context Recovery

    public func recoverFromContextPressure(
        originalPrompt: String,
        error: Error,
        modelId: String,
        maxRetries: Int = 2
    ) async -> ContextRecoveryResult {
        let errorDesc = error.localizedDescription.lowercased()
        let isContextError = errorDesc.contains("context") || errorDesc.contains("token") || errorDesc.contains("too long") || errorDesc.contains("maximum")

        guard isContextError else {
            return ContextRecoveryResult(success: false, originalError: error.localizedDescription, compactionApplied: false, retryCount: 0)
        }

        var retryCount = 0
        var currentPrompt = originalPrompt

        while retryCount < maxRetries {
            retryCount += 1

            // Aggressive compaction: keep only P0 + most recent P1
            let lines = currentPrompt.components(separatedBy: "\n")
            var compactedLines: [String] = []
            var inP0 = false
            var p1Count = 0

            for line in lines {
                if line.contains("ACTIVE OBJECTIVE") || line.contains("CRITICAL CONSTRAINTS") || line.contains("UNRESOLVED ERRORS") {
                    inP0 = true
                } else if line.contains("# ") && !line.contains("ACTIVE") && !line.contains("CRITICAL") && !line.contains("UNRESOLVED") {
                    inP0 = false
                    p1Count += 1
                }

                if inP0 || p1Count <= 3 {
                    compactedLines.append(line)
                }
            }

            currentPrompt = compactedLines.joined(separator: "\n")

            // Add compaction notice
            currentPrompt += "\n\n[SYSTEM: Context compacted due to pressure. Focus on unresolved errors and active objective.]"

            let capacity = modelContextWindow(for: modelId)
            if estimateTokens(currentPrompt) < capacity - 6144 {
                return ContextRecoveryResult(
                    success: true,
                    originalError: error.localizedDescription,
                    compactionApplied: true,
                    retryCount: retryCount,
                    finalPrompt: currentPrompt
                )
            }
        }

        return ContextRecoveryResult(
            success: false,
            originalError: error.localizedDescription,
            compactionApplied: true,
            retryCount: retryCount
        )
    }

    // MARK: - File Content Cache

    private func cachedFileContent(at path: String, maxChars: Int) -> String? {
        if let cached = fileContentCache[path] {
            let currentMtime = (try? context.workspaceRoot.appendingPathComponent(path).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let current = currentMtime, current == cached.mtime {
                return cached.content.count > maxChars ? String(cached.content.prefix(maxChars)) + "\n... [TRUNCATED]" : cached.content
            }
        }
        guard let raw = try? context.fileSystem.readFile(at: path) else { return nil }
        let mtime = (try? context.workspaceRoot.appendingPathComponent(path).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        fileContentCache[path] = (mtime: mtime, content: raw)
        return raw.count > maxChars ? String(raw.prefix(maxChars)) + "\n... [TRUNCATED]" : raw
    }

    // MARK: - Compaction Record

    public struct CompactionRecord: Sendable {
        public let timestamp: Date
        public let originalTokens: Int
        public let compactedTokens: Int
        public let phasesApplied: [String]
    }

    public func getCompactionLog() -> [CompactionRecord] {
        lock.lock()
        defer { lock.unlock() }
        return _compactionLog
    }
}

// MARK: - Legacy AgentContextManager (wrapper for backward compatibility)

public final class AgentContextManager: @unchecked Sendable {
    private let context: AssistContext
    private var fileContentCache: [String: (mtime: Date, content: String)] = [:]

    public init(context: AssistContext) {
        self.context = context
    }

    public var engine: AssistContextEngine { AssistContextEngine(context: context) }

    public func buildContext(
        for objective: String,
        plan: AssistExecutionPlan? = nil,
        completedActions: [String] = [],
        remainingActions: [String] = [],
        recentResults: [AssistToolResult] = [],
        recentErrors: [String] = [],
        failureSummary: String = "",
        verificationSummary: String = "",
        activeFiles: [String] = []
    ) async -> AgentContext {
        let projectName = context.project?.name ?? "SwiftCode"
        let manifest = "Workspace root: \(context.workspaceRoot.path)\nActive project: \(projectName)"

        var repoInstructions = ""
        let discoveredInstructions = AgentRepositoryScanner.shared.discoverInstructions(in: context.workspaceRoot)
        if !discoveredInstructions.isEmpty {
            repoInstructions = AgentRepositoryScanner.shared.formatInstructionsForPrompt(instructions: discoveredInstructions, targetFiles: activeFiles)
        } else {
            let groundingFiles = ["CLAUDE.md", "README.md", "Package.swift"]
            for gFile in groundingFiles {
                if context.fileSystem.exists(at: gFile) {
                    if let raw = try? context.fileSystem.readFile(at: gFile) {
                        let maxChars = 3000
                        let snippet = raw.count > maxChars ? String(raw.prefix(maxChars)) + "\n... [TRUNCATED]" : raw
                        repoInstructions += "\n--- [GROUNDING: \(gFile)] ---\n\(snippet)\n"
                        break
                    }
                }
            }
        }

        var activeContents: [String: String] = [:]
        for file in activeFiles.prefix(6) {
            if context.fileSystem.exists(at: file) {
                if let content = cachedFileContent(at: file, maxChars: 4000) {
                    activeContents[file] = content
                }
            }
        }

        var compactResults: [String] = []
        for res in recentResults.suffix(5) {
            let maxOutput = 1200
            let body = res.output.count > maxOutput ? String(res.output.prefix(maxOutput)) + "\n... [OUTPUT TRUNCATED]" : res.output
            var item = "Status: \(res.success ? "SUCCESS" : "FAILED")\nOutput: \(body)"
            if let diff = res.diff, !diff.isEmpty {
                let maxDiff = 800
                let diffSummary = diff.count > maxDiff ? String(diff.prefix(maxDiff)) + "\n... [DIFF TRUNCATED]" : diff
                item += "\nDiff:\n\(diffSummary)"
            }
            if !res.diagnostics.isEmpty {
                item += "\nDiagnostics: \(res.diagnostics.prefix(3).joined(separator: "; "))"
            }
            compactResults.append(item)
        }

        return AgentContext(
            repoManifestSummary: manifest,
            taskObjective: objective,
            currentPlan: plan,
            completedActions: completedActions,
            remainingActions: remainingActions,
            activeFileContents: activeContents,
            recentToolResults: compactResults,
            recentBuildErrors: Array(recentErrors.suffix(5)),
            repositoryInstructions: repoInstructions,
            failureHistorySummary: failureSummary,
            verificationStatusSummary: verificationSummary
        )
    }

    private func cachedFileContent(at path: String, maxChars: Int) -> String? {
        if let cached = fileContentCache[path] {
            let currentMtime = (try? context.workspaceRoot.appendingPathComponent(path).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let current = currentMtime, current == cached.mtime {
                return cached.content.count > maxChars ? String(cached.content.prefix(maxChars)) + "\n... [TRUNCATED]" : cached.content
            }
        }
        guard let raw = try? context.fileSystem.readFile(at: path) else { return nil }
        let mtime = (try? context.workspaceRoot.appendingPathComponent(path).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        fileContentCache[path] = (mtime: mtime, content: raw)
        return raw.count > maxChars ? String(raw.prefix(maxChars)) + "\n... [TRUNCATED]" : raw
    }
}
