import Foundation
import os

// MARK: - Assist Prompt & Session Optimizer
/// High-performance subsystem for prompt assembly, schema memoization,
/// session reuse validation, and latency reduction across Assist and Antigravity.
@MainActor
public final class AssistPromptOptimizer: Sendable {
    public static let shared = AssistPromptOptimizer()
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistPromptOptimizer")

    // Thread-safe lock for internal memoization tables
    private let lock = NSLock()

    // 1. Tool Schemas Memoization
    private var phaseSchemasCache: [AgentSessionStatus: String] = [:]
    private var allToolSchemasJSONCache: [[String: Any]]? = nil
    private var allToolSchemasCompactCache: String? = nil
    private var toolSchemasVersion: Int = 0

    // 2. Repository Instructions Cache
    private struct CachedRepoInstructions {
        let rootPath: String
        let mtime: Date
        let rawContent: String
        var filteredByObjective: [String: String] = [:]
    }
    private var repoInstructionsCache: [String: CachedRepoInstructions] = [:]

    // 3. System Prompt Compaction Cache
    private struct CachedSystemPrompt {
        let key: String
        let prompt: String
        let timestamp: Date
    }
    private var systemPromptCache: [String: CachedSystemPrompt] = [:]

    // 4. Cached Context & Permission Structures
    private var cachedContext: (sessionId: UUID, context: AssistContext)?
    private var cachedContextWorkspaceURL: URL?

    private init() {}

    // MARK: - Cache Invalidation

    /// Invalidates cached tool schemas across all phases and formats.
    public func invalidateToolSchemas() {
        lock.lock()
        defer { lock.unlock() }
        phaseSchemasCache.removeAll()
        allToolSchemasJSONCache = nil
        allToolSchemasCompactCache = nil
        toolSchemasVersion += 1
        logger.debug("[AssistPromptOptimizer] Invalidated tool schema caches (v\(self.toolSchemasVersion)).")
    }

    /// Invalidates cached repository instructions.
    public func invalidateRepositoryCache() {
        lock.lock()
        defer { lock.unlock() }
        repoInstructionsCache.removeAll()
        logger.debug("[AssistPromptOptimizer] Invalidated repository instructions cache.")
    }

    /// Invalidates cached system prompts.
    public func invalidateSystemPromptCache() {
        lock.lock()
        defer { lock.unlock() }
        systemPromptCache.removeAll()
    }

    // MARK: - 1. Tool Schema Memoization

    /// Returns the cached, serialized string representation of tools for a specific session status/phase.
    public func cachedPhaseSchemas(
        for status: AgentSessionStatus,
        in registry: AssistToolRegistry
    ) -> String {
        lock.lock()
        if let cached = phaseSchemasCache[status] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let phaseTools = AssistToolRouter.shared.filterTools(for: status, in: registry)
        let serialized = AssistToolRouter.shared.serializeToolSchemas(phaseTools)

        lock.lock()
        phaseSchemasCache[status] = serialized
        lock.unlock()

        return serialized
    }

    /// Returns the cached dictionary representation of all registered tool schemas.
    /// This eliminates repeated JSONEncoder and JSONSerialization operations on 140+ tools.
    public func cachedToolSchemasJSON(in registry: AssistToolRegistry) -> [[String: Any]] {
        lock.lock()
        if let cached = allToolSchemasJSONCache {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let schemas = registry.getToolSchemas()

        lock.lock()
        allToolSchemasJSONCache = schemas
        lock.unlock()

        return schemas
    }

    /// Returns the compact text summary of all registered tools and their capabilities.
    public func cachedToolSchemasCompact(in registry: AssistToolRegistry) -> String {
        lock.lock()
        if let cached = allToolSchemasCompactCache {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let compact = AssistToolRouter.shared.compactCapabilitySummary(for: registry)

        lock.lock()
        allToolSchemasCompactCache = compact
        lock.unlock()

        return compact
    }

    // MARK: - 2. Repository Guidance Compaction & Caching

    /// Reads and caches repository instruction files (`AGENTS.md`, `Agent.md`),
    /// verifying modification times to avoid redundant filesystem operations.
    public func loadRepositoryInstructions(for workspaceRoot: URL) -> String? {
        let standardRoot = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = standardRoot.path

        let candidates = ["AGENTS.md", "Agents.md", "Agent.md"]
        let fm = FileManager.default

        for name in candidates {
            let candidateURL = standardRoot.appendingPathComponent(name)
            guard fm.fileExists(atPath: candidateURL.path) else { continue }

            let currentMtime = (try? candidateURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()

            lock.lock()
            if let cached = repoInstructionsCache[rootPath],
               cached.mtime == currentMtime {
                let content = cached.rawContent
                lock.unlock()
                return content
            }
            lock.unlock()

            if let content = try? String(contentsOf: candidateURL, encoding: .utf8),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lock.lock()
                repoInstructionsCache[rootPath] = CachedRepoInstructions(
                    rootPath: rootPath,
                    mtime: currentMtime,
                    rawContent: content,
                    filteredByObjective: [:]
                )
                lock.unlock()
                return content
            }
        }

        return nil
    }

    /// Extracts and caches task-relevant repository instructions based on objective keywords.
    public func optimizedRepositoryInstructions(
        for workspaceRoot: URL,
        objective: String
    ) -> String {
        guard let fullContent = loadRepositoryInstructions(for: workspaceRoot) else {
            return ""
        }

        let standardRoot = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = standardRoot.path
        let objectiveKey = objective.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        lock.lock()
        if var cached = repoInstructionsCache[rootPath] {
            if let existing = cached.filteredByObjective[objectiveKey] {
                lock.unlock()
                return existing
            }
            lock.unlock()

            let filtered = AssistSystemPromptSections.runtimeInstructions(
                from: "",
                repositoryInstructions: fullContent,
                toolkit: "System",
                objective: objective
            )

            lock.lock()
            cached.filteredByObjective[objectiveKey] = filtered
            repoInstructionsCache[rootPath] = cached
            lock.unlock()
            return filtered
        }
        lock.unlock()

        return fullContent
    }

    // MARK: - 3. System Prompt Compaction & Caching

    /// Returns an optimized, bounded system prompt for the specified objective and toolkit.
    /// Uses signature-based caching to avoid re-scoring the 24 system assets on every turn.
    public func optimizedSystemPrompt(
        for objective: String,
        toolkit: String = "System",
        characterBudget: Int = 16_000
    ) -> String {
        // Derive a coarse signature from primary keywords
        let signature = objectiveSignature(from: objective)
        let cacheKey = "\(toolkit)|\(characterBudget)|\(signature)"

        lock.lock()
        if let entry = systemPromptCache[cacheKey],
           Date().timeIntervalSince(entry.timestamp) < 300.0 {
            let prompt = entry.prompt
            lock.unlock()
            return prompt
        }
        lock.unlock()

        let prompt = LoadUpSystemAssets.shared.systemPrompt(
            for: objective,
            toolkit: toolkit,
            characterBudget: characterBudget
        )

        lock.lock()
        systemPromptCache[cacheKey] = CachedSystemPrompt(
            key: cacheKey,
            prompt: prompt,
            timestamp: Date()
        )
        lock.unlock()

        return prompt
    }

    private func objectiveSignature(from objective: String) -> String {
        let tokens = objective.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 }
        let unique = Array(Set(tokens)).sorted()
        return unique.prefix(8).joined(separator: "-")
    }

    // MARK: - 4. Turn History Compaction

    /// Compacts conversation history by truncating verbose tool outputs while
    /// preserving critical diagnostic error messages, diffs, and execution status.
    public func compactConversationHistory(
        _ history: [String],
        maxEntries: Int = 8,
        maxCharsPerEntry: Int = 1_500
    ) -> [String] {
        guard !history.isEmpty else { return [] }

        let window = history.suffix(maxEntries)
        return window.map { entry in
            guard entry.count > maxCharsPerEntry else { return entry }

            // Retain the head (command / purpose / status) and tail (errors / exit codes)
            let headSize = maxCharsPerEntry / 2
            let tailSize = maxCharsPerEntry / 2

            let head = entry.prefix(headSize)
            let tail = entry.suffix(tailSize)
            return "\(head)\n\n... [OUTPUT COMPACTED TO PRESERVE TOKEN BUDGET] ...\n\n\(tail)"
        }
    }

    // MARK: - 5. TTFT Structured Prompt Assembly

    /// Assembles an optimized full prompt engineered for Maximum Prefix Cache Reuse.
    /// Static content (policy, rules, tool schemas) is placed first, followed by
    /// dynamic, turn-specific content (objective, modified files, history).
    public func assembleStructuredAgentPrompt(
        assetSystemPrompt: String,
        objective: String,
        executionModeInstruction: String,
        groundingInstructions: String,
        attachmentsBlock: String,
        skillsBlock: String,
        manifest: String,
        activeFiles: String,
        toolSchemas: String,
        history: [String],
        failureSummary: String
    ) -> String {
        // --- SECTION A: IMMUTABLE PREFIX (Cacheable across turns) ---
        var prompt = """
        # SYSTEM PROMPT (OPERATING POLICY)
        \(assetSystemPrompt)

        \(executionModeInstruction)

        # TOOL SCHEMAS & PROTOCOL
        \(toolSchemas)
        """

        if !skillsBlock.isEmpty {
            prompt += "\n\n# DISCOVERED AGENT SKILLS\n\(skillsBlock)"
        }

        // --- SECTION B: REPOSITORY & WORKSPACE CONTEXT ---
        if !groundingInstructions.isEmpty {
            prompt += "\n\n# WORKSPACE GUIDANCE\n\(groundingInstructions)"
        }

        if !manifest.isEmpty {
            prompt += "\n\n# WORKSPACE STATE\n\(manifest)"
        }

        // --- SECTION C: CURRENT TASK OBJECTIVE ---
        prompt += """


        # ACTIVE TASK OBJECTIVE
        You are an autonomous Swift/macOS coding agent in SwiftCode.
        Goal: "\(objective)"

        Respond ONLY with valid JSON:
        {
          "toolId": "the_tool_id",
          "input": { "key": "value" },
          "explanation": "Human-readable purpose of this action"
        }
        OR:
        {
          "finalResponse": "Clear, detailed summary of completed achievements"
        }
        """

        if !attachmentsBlock.isEmpty {
            prompt += "\n\(attachmentsBlock)"
        }

        if !activeFiles.isEmpty {
            prompt += "\n\n# ACTIVE FILE CONTENTS\n\(activeFiles)"
        }

        // --- SECTION D: RECENT EXECUTION HISTORY (Dynamic suffix) ---
        if !history.isEmpty {
            let compacted = compactConversationHistory(history)
            prompt += "\n\n# HISTORY OF RECENT TOOL EXECUTION RESULTS\n"
            prompt += compacted.joined(separator: "\n")
        }

        if !failureSummary.isEmpty {
            prompt += "\n\n# ACTIVE FAILURE OBSERVATIONS\n\(failureSummary)"
        }

        prompt += "\n\nChoose the next best tool to run or provide finalResponse in valid JSON."
        return prompt
    }

    // MARK: - 6. Session Reuse Validator

    /// Determines whether an active GoogleCloudSDKSession can be safely reused for a new turn.
    ///
    /// Reusing the session preserves conversation history, active process state, and provider
    /// context caches, eliminating hundreds of milliseconds of bridge initialization.
    public func canReuseSDKSession(
        existing: GoogleCloudSDKSession,
        targetConfig: GoogleCloudSDKConfiguration
    ) -> Bool {
        // Model identifier must match
        guard existing.config.model == targetConfig.model else { return false }

        // Provider must match
        guard existing.config.provider == targetConfig.provider else { return false }

        // Endpoint baseURL must match
        guard existing.config.baseURL == targetConfig.baseURL else { return false }

        // API Key must match
        guard existing.config.apiKey == targetConfig.apiKey else { return false }

        // Workspaces must match
        guard existing.config.workspaces == targetConfig.workspaces else { return false }

        // Toolkit must match
        guard existing.config.toolkit == targetConfig.toolkit else { return false }

        // Subagent capabilities must match
        guard existing.config.enableSubagents == targetConfig.enableSubagents else { return false }

        return true
    }

    // MARK: - 7. Fast Execution Context Provider

    /// Provides or reuses an AssistContext for fast tool dispatch.
    /// Avoids reallocating filesystem, git, permission, and memory managers on every tool call.
    public func executionContext(for sessionId: UUID, workspaceRoot: URL) -> AssistContext {
        if let cached = cachedContext,
           cached.sessionId == sessionId,
           cachedContextWorkspaceURL == workspaceRoot {
            return cached.context
        }

        let project = ProjectSessionStore.shared.activeProject
        let permissions = AssistPermissionsManager()
        let memory = AssistMemoryGraph()
        let fileSystem = AssistFileSystem(workspaceRoot: workspaceRoot)
        let git = AssistGitManager(project: project)

        let executionModeRaw = UserDefaults.standard.string(forKey: "com.swiftcode.assist.executionMode") ?? ExecutionMode.autopilot.rawValue
        let executionMode = ExecutionMode(rawValue: executionModeRaw) ?? .autopilot

        let context = AssistContext(
            sessionId: sessionId,
            project: project,
            workspaceRoot: workspaceRoot,
            memory: memory,
            logger: AssistManager.shared.logger,
            fileSystem: fileSystem,
            git: git,
            permissions: permissions,
            safetyLevel: .balanced,
            isAutonomous: true,
            sessionExecutionMode: executionMode
        )

        cachedContext = (sessionId: sessionId, context: context)
        cachedContextWorkspaceURL = workspaceRoot
        return context
    }
}
