import Foundation
import os

// MARK: - System Asset Category

public enum SystemAssetCategory: String, Sendable, Codable, CaseIterable {
    case foundation
    case tooling
    case toolReference
    case interaction
    case orchestration
    case planning
    case model
    case security
    case reliability
    case memory
    case integration
    case engineering
}

// MARK: - System Asset Entity

public struct SystemAsset: Sendable, Identifiable {
    public let id: String
    public let filename: String
    public let category: SystemAssetCategory
    public let title: String
    public var characterCount: Int
    public var estimatedTokenCount: Int
    public let priority: Int
    public let isMandatory: Bool
    public let keywords: [String]
    public let toolsCovered: [String]
    public var content: String

    public init(
        id: String,
        filename: String,
        category: SystemAssetCategory,
        title: String,
        characterCount: Int = 0,
        estimatedTokenCount: Int = 0,
        priority: Int,
        isMandatory: Bool,
        keywords: [String],
        toolsCovered: [String] = [],
        content: String = ""
    ) {
        self.id = id
        self.filename = filename
        self.category = category
        self.title = title
        self.characterCount = characterCount
        self.estimatedTokenCount = estimatedTokenCount
        self.priority = priority
        self.isMandatory = isMandatory
        self.keywords = keywords
        self.toolsCovered = toolsCovered
        self.content = content
    }
}

// MARK: - LoadUpSystemAssets Singleton

public final class LoadUpSystemAssets: @unchecked Sendable {
    public static let shared = LoadUpSystemAssets()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "LoadUpSystemAssets")
    private let lock = NSLock()
    private var assetCache: [String: SystemAsset] = [:]
    private var toolToAssetId: [String: String] = [:]
    private var isInitialized = false

    /// Canonical, deterministic catalog metadata for all modular system prompt assets.
    public let assetCatalog: [SystemAsset] = [
        SystemAsset(
            id: "CoreRules",
            filename: "CoreRules.md",
            category: .foundation,
            title: "System Identity & Architectural Boundaries",
            priority: 100,
            isMandatory: true,
            keywords: ["system", "identity", "antigravity", "swiftcode", "ground", "mutate", "concurrency", "speculative", "framework", "architecture", "core operating policy", "corerules"],
            toolsCovered: []
        ),
        SystemAsset(
            id: "Identity",
            filename: "Identity.md",
            category: .foundation,
            title: "SwiftCode Assist Identity & Operating Directive",
            priority: 98,
            isMandatory: false,
            keywords: ["identity", "persona", "refusal", "obedience", "environment", "capabilities", "directive", "guardrails", "memory off", "assist"],
            toolsCovered: []
        ),
        SystemAsset(
            id: "SystemAsset",
            filename: "SystemAsset.md",
            category: .foundation,
            title: "System Asset Master Directory & Knowledge Map",
            priority: 92,
            isMandatory: false,
            keywords: ["system asset", "catalog", "directory", "map", "routing", "knowledge", "manifest"],
            toolsCovered: []
        ),
        SystemAsset(
            id: "SecurityAndPrivacy",
            filename: "SecurityAndPrivacy.md",
            category: .security,
            title: "Security, Privacy & Guardrails",
            priority: 95,
            isMandatory: true,
            keywords: ["security", "keychain", "token", "credential", "sandbox", "prompt injection", "privacy", "untrusted", "path"],
            toolsCovered: []
        ),
        SystemAsset(
            id: "ToolCalling",
            filename: "ToolCalling.md",
            category: .tooling,
            title: "Tool Calling Protocol & Decision Tree",
            priority: 90,
            isMandatory: false,
            keywords: ["tool", "decision", "protocol", "sdk", "json", "capability", "action", "tree", "hierarchy"],
            toolsCovered: []
        ),
        SystemAsset(
            id: "ToolSchemasAndParameters",
            filename: "ToolSchemasAndParameters.md",
            category: .tooling,
            title: "Tool Schemas, Parameters & Path Security",
            priority: 85,
            isMandatory: false,
            keywords: ["schema", "parameter", "path", "relative", "argument", "traversal", "type", "validation"],
            toolsCovered: []
        ),
        SystemAsset(
            id: "UsingTools",
            filename: "UsingTools.md",
            category: .tooling,
            title: "Tool Selection Principles & Risk Categories",
            priority: 80,
            isMandatory: false,
            keywords: ["minimum", "necessary", "risk", "saferead", "safemutation", "execution", "destructive", "chains", "dependencies"],
            toolsCovered: []
        ),
        SystemAsset(
            id: "ToolRouting",
            filename: "ToolRouting.md",
            category: .tooling,
            title: "Assist Toolkit Architecture & Routing",
            priority: 75,
            isMandatory: false,
            keywords: ["toolkit", "picker", "routing", "system", "cloud", "ipc", "dispatch", "transport"],
            toolsCovered: []
        ),
        SystemAsset(
            id: "ToolResultsAndErrors",
            filename: "ToolResultsAndErrors.md",
            category: .tooling,
            title: "Tool Results Authority & Error Classification",
            priority: 70,
            isMandatory: false,
            keywords: ["result", "error", "authority", "cache", "retry", "invalidation", "classification", "recovery"],
            toolsCovered: []
        ),
        SystemAsset(
            id: "UserRequests",
            filename: "UserRequests.md",
            category: .interaction,
            title: "User Requests, Intent Triage & Attachments",
            priority: 70,
            isMandatory: false,
            keywords: ["greeting", "hello", "hi", "request", "triage", "attachment", "interruption", "pivot", "user"],
            toolsCovered: []
        ),
        SystemAsset(
            id: "OutputtingWork",
            filename: "OutputtingWork.md",
            category: .interaction,
            title: "Outputting Work & Telemetry Presentation",
            priority: 65,
            isMandatory: false,
            keywords: ["output", "telemetry", "presentation", "markdown", "badge", "clean", "format", "chat"],
            toolsCovered: []
        ),
        SystemAsset(
            id: "FileOperations",
            filename: "FileOperations.md",
            category: .toolReference,
            title: "File Operations & Directory Management",
            priority: 60,
            isMandatory: false,
            keywords: ["file", "directory", "folder", "read", "write", "append", "delete", "move", "copy", "rename", "create", "tree"],
            toolsCovered: ["file_read", "file_write", "file_append", "file_delete", "file_move", "file_copy", "file_rename", "dir_create", "file_create", "code_generate", "dir_delete", "dir_read", "tree_view", "view_file", "create_file", "edit_file", "list_directory"]
        ),
        SystemAsset(
            id: "SearchAndContext",
            filename: "SearchAndContext.md",
            category: .toolReference,
            title: "Codebase Search & Context Discovery",
            priority: 60,
            isMandatory: false,
            keywords: ["search", "find", "grep", "symbol", "regex", "dependency", "graph", "web", "url", "lookup"],
            toolsCovered: ["search_text", "search_regex", "search_symbol", "dependency_graph", "search_directory", "search_web", "read_url_content"]
        ),
        SystemAsset(
            id: "EditingAndPatching",
            filename: "EditingAndPatching.md",
            category: .toolReference,
            title: "Code Editing, Patching & Mutation",
            priority: 60,
            isMandatory: false,
            keywords: ["edit", "replace", "patch", "modify", "insert", "format", "refactor", "mutation", "diff"],
            toolsCovered: ["code_replace", "code_multi_edit", "code_refactor", "code_format", "code_insert", "code_mutation_engine", "patch_application_engine"]
        ),
        SystemAsset(
            id: "BuildTestValidation",
            filename: "BuildTestValidation.md",
            category: .toolReference,
            title: "Build, Test & Diagnostics Validation",
            priority: 60,
            isMandatory: false,
            keywords: ["build", "compile", "test", "lint", "diagnostics", "review", "xcodebuild", "swiftc", "exit code 0", "passed"],
            toolsCovered: ["project_build", "project_test", "safe_validate_changes", "compiler_diagnostics_engine", "automated_repair_engine", "dependency_resolution_engine", "autonomous_review_engine", "code_review", "code_lint", "complexity_analysis", "code_summary"]
        ),
        SystemAsset(
            id: "TerminalAndCommandSafety",
            filename: "TerminalAndCommandSafety.md",
            category: .toolReference,
            title: "Terminal Execution & Command Safety",
            priority: 55,
            isMandatory: false,
            keywords: ["terminal", "command", "shell", "run", "process", "approval", "bash", "zsh", "sandbox", "terminal & command safety"],
            toolsCovered: ["use_terminal", "run_command"]
        ),
        SystemAsset(
            id: "PlanningAndTaskComplexity",
            filename: "PlanningAndTaskComplexity.md",
            category: .planning,
            title: "Execution Planning & Task Complexity",
            priority: 55,
            isMandatory: false,
            keywords: ["plan", "planning", "complexity", "tier", "steps", "task", "ask user", "intel", "roadmap"],
            toolsCovered: ["execution_plan", "plan-AskUser", "intel_plan_task", "intel_breakdown_task", "intel_autofix", "intel_generate_tests", "intel_explain_code", "create_new_app"]
        ),
        SystemAsset(
            id: "GitAndVersionControl",
            filename: "GitAndVersionControl.md",
            category: .toolReference,
            title: "Git & Version Control Management",
            priority: 50,
            isMandatory: false,
            keywords: ["git", "version control", "snapshot", "restore", "diff", "undo", "commit", "branch", "rollback", "changelog", "merge conflict"],
            toolsCovered: ["version_control_operator", "project_snapshot", "project_restore", "project_diff", "project_changelog", "safe_undo"]
        ),
        SystemAsset(
            id: "UsingWorkers",
            filename: "UsingWorkers.md",
            category: .orchestration,
            title: "Worker & Subagent Delegation Policy",
            priority: 50,
            isMandatory: false,
            keywords: ["worker", "subagent", "delegate", "parallel", "swarm", "delegation", "workstream"],
            toolsCovered: ["use_workers", "start_subagent"]
        ),
        SystemAsset(
            id: "MCPAndSkills",
            filename: "MCPAndSkills.md",
            category: .integration,
            title: "Agent Skills, MCP & Composio Integration",
            priority: 55,
            isMandatory: false,
            keywords: ["skill", "mcp", "composio", "slash", "at", "integration", "playbook", "server"],
            toolsCovered: ["search_skills", "use_mcp", "use_composio"]
        ),
        SystemAsset(
            id: "ParallelWork",
            filename: "ParallelWork.md",
            category: .orchestration,
            title: "Parallel Work & Concurrency Discipline",
            priority: 45,
            isMandatory: false,
            keywords: ["parallel", "concurrency", "sequential", "race condition", "scope", "isolation", "discipline"],
            toolsCovered: []
        ),
        SystemAsset(
            id: "RetryAndRecovery",
            filename: "RetryAndRecovery.md",
            category: .reliability,
            title: "Retry Discipline & Fault Recovery",
            priority: 50,
            isMandatory: false,
            keywords: ["retry", "recovery", "oscillation", "loop", "stagnation", "fault", "transient", "stability"],
            toolsCovered: []
        ),
        SystemAsset(
            id: "Memory",
            filename: "Memory.md",
            category: .memory,
            title: "User Memory & Persistent Fact System",
            priority: 50,
            isMandatory: false,
            keywords: ["user memory", "memory", "capture_memory", "retrieve_memory", "manage_memory", "usermemory.md", "preference", "fact"],
            toolsCovered: ["capture_memory", "retrieve_memory", "manage_memory"]
        ),
        SystemAsset(
            id: "Context",
            filename: "Context.md",
            category: .memory,
            title: "Workspace Context Management & Persistence",
            priority: 45,
            isMandatory: false,
            keywords: ["context", "workspace topology", "ast symbols", "token budgeting", "persistence", "source graph", "snapshot", "diagnostics"],
            toolsCovered: ["context_persistence_store", "source_graph_builder", "semantic_query_engine", "env_capture_logs", "env_info", "runtime_diagnostics_engine"]
        ),
        SystemAsset(
            id: "MemoryAndContext",
            filename: "MemoryAndContext.md",
            category: .memory,
            title: "Agent Memory & Context Persistence (Legacy Combined)",
            priority: 40,
            isMandatory: false,
            keywords: ["memory", "context", "legacy", "persistence"],
            toolsCovered: ["mem_store", "mem_retrieve", "mem_clear", "mem_context_snapshot"]
        ),
        SystemAsset(
            id: "ModelCompatibility",
            filename: "ModelCompatibility.md",
            category: .model,
            title: "Multi-Provider Model Compatibility",
            priority: 45,
            isMandatory: false,
            keywords: ["model", "provider", "claude", "gemini", "openai", "fallback", "router", "key", "failover"],
            toolsCovered: []
        ),
        SystemAsset(
            id: "SwiftAndConcurrency",
            filename: "SwiftAndConcurrency.md",
            category: .engineering,
            title: "Advanced Swift 6 Concurrency & macOS Architecture",
            priority: 45,
            isMandatory: false,
            keywords: ["swift", "concurrency", "actor", "sendable", "mainactor", "appkit", "swiftui", "nsviewrepresentable", "swift 6 concurrency"],
            toolsCovered: []
        ),
        SystemAsset(
            id: "StreamingAndProgress",
            filename: "StreamingAndProgress.md",
            category: .interaction,
            title: "Streaming Response & Progress Disclosure",
            priority: 40,
            isMandatory: false,
            keywords: ["stream", "progress", "badge", "latency", "disclosure", "status", "real-time"],
            toolsCovered: []
        )
    ]

    private init() {
        preloadAssets()
    }

    // MARK: - Asset Preloading & In-Memory Caching

    public func preloadAssets() {
        lock.lock()
        defer { lock.unlock() }

        toolToAssetId.removeAll()
        for var item in assetCatalog {
            let content = loadContent(for: item.filename)
            item.content = content
            item.characterCount = content.count
            item.estimatedTokenCount = max(1, content.count / 4)
            assetCache[item.id] = item

            for tool in item.toolsCovered {
                toolToAssetId[tool] = item.id
            }
        }
        isInitialized = true
    }

    /// Explicitly refreshes the cache from disk.
    public func reloadAssets() {
        preloadAssets()
    }

    /// Returns all loaded assets in catalog order.
    public func allAssets() -> [SystemAsset] {
        lock.lock()
        defer { lock.unlock() }
        return assetCatalog.compactMap { assetCache[$0.id] }
    }

    /// Retrieves an asset by its canonical ID or filename.
    public func asset(for identifier: String) -> SystemAsset? {
        lock.lock()
        defer { lock.unlock() }

        if let direct = assetCache[identifier] {
            return direct
        }
        return assetCatalog.first {
            $0.filename.caseInsensitiveCompare(identifier) == .orderedSame ||
            $0.id.caseInsensitiveCompare(identifier) == .orderedSame
        }.flatMap { assetCache[$0.id] }
    }

    /// Fast local retrieval of task/tool-relevant guidance for a specific tool ID.
    public func guidance(forTool toolId: String) -> String? {
        lock.lock()
        let assetId = toolToAssetId[toolId]
        let cached = assetId.flatMap { assetCache[$0] }
        let all = assetCatalog.compactMap { assetCache[$0.id] }
        lock.unlock()

        if let candidate = cached, let extracted = extractToolBlock(toolId: toolId, from: candidate.content) {
            return extracted
        }

        for item in all {
            if let extracted = extractToolBlock(toolId: toolId, from: item.content) {
                return extracted
            }
        }
        return nil
    }

    private func extractToolBlock(toolId: String, from text: String) -> String? {
        let pattern = "#### `\(toolId)`"
        guard let range = text.range(of: pattern) else { return nil }
        let after = text[range.lowerBound...]
        let lines = after.components(separatedBy: "\n")
        var collected: [String] = []
        for (idx, line) in lines.enumerated() {
            if idx > 0 && (line.hasPrefix("#### `") || line.hasPrefix("## ") || line.hasPrefix("# ")) {
                break
            }
            collected.append(line)
        }
        return collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Full Corpus Generation

    /// Loads and deterministically joins all catalog assets into the complete authoritative corpus.
    public func fullCorpusPrompt() -> String {
        let assets = allAssets()
        let sections = assets.map { asset in
            asset.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Budget-Constrained Adaptive System Prompt

    /// Generates a tailored system prompt for a specific task objective, toolkit, and token/character budget.
    ///
    /// - Parameters:
    ///   - objective: The user's prompt or task intent.
    ///   - toolkit: The active toolkit name ("System" or "Cloud").
    ///   - characterBudget: Maximum allowed character length (defaults to 16,000).
    /// - Returns: A coherent, structured, budget-enforced system prompt string.
    public func systemPrompt(
        for objective: String,
        toolkit: String = "System",
        characterBudget: Int = 16_000
    ) -> String {
        let assets = allAssets()
        let lowerObjective = objective.lowercased()
        let isCloud = toolkit.caseInsensitiveCompare("cloud") == .orderedSame

        // Check for simple conversational greetings
        if isSimpleGreeting(lowerObjective) {
            return greetingBoundedPrompt(toolkit: toolkit)
        }

        // 1. Core mandatory rules are always enforced
        var selectedAssets: [SystemAsset] = []
        if let coreRules = assets.first(where: { $0.id == "CoreRules" }) {
            selectedAssets.append(coreRules)
        }

        var currentLength = selectedAssets.reduce(0) { $0 + $1.content.count + 2 }

        // Security is included if budget permits or for any non-trivial task
        if let sec = assets.first(where: { $0.id == "SecurityAndPrivacy" }),
           currentLength + sec.content.count + 2 <= characterBudget + 3_000 {
            selectedAssets.append(sec)
            currentLength += sec.content.count + 2
        }

        // 2. Score candidate assets based on objective relevance, keywords, and active toolkit
        var candidateAssets = assets.filter { $0.id != "CoreRules" && $0.id != "SecurityAndPrivacy" }
        // Filter out legacy combined asset if distinct Memory and Context are present
        if candidateAssets.contains(where: { $0.id == "Memory" }) && candidateAssets.contains(where: { $0.id == "Context" }) {
            candidateAssets.removeAll(where: { $0.id == "MemoryAndContext" })
        }

        var scoredAssets: [(asset: SystemAsset, score: Double)] = []
        for asset in candidateAssets {
            var score = Double(asset.priority)

            // Toolkit alignment bonus
            if isCloud {
                if asset.id == "ToolRouting" || asset.toolsCovered.contains("view_file") {
                    score += 40.0
                }
            } else {
                if asset.id == "UsingTools" || asset.id == "FileOperations" || asset.id == "EditingAndPatching" {
                    score += 25.0
                }
            }

            // Keyword matching bonus
            for keyword in asset.keywords {
                if lowerObjective.contains(keyword.lowercased()) {
                    score += 35.0
                }
            }

            // Direct tool coverage matching bonus
            for tool in asset.toolsCovered {
                if lowerObjective.contains(tool.lowercased()) {
                    score += 60.0
                }
            }

            scoredAssets.append((asset, score))
        }

        // Sort descending by relevance score
        scoredAssets.sort { $0.score > $1.score }

        // 3. Greedily pack highest scoring assets into character budget
        for item in scoredAssets {
            let assetLength = item.asset.content.count + 2
            if currentLength + assetLength <= characterBudget {
                selectedAssets.append(item.asset)
                currentLength += assetLength
            }
        }

        // 4. Sort selected assets into deterministic catalog order
        let catalogOrder = Dictionary(uniqueKeysWithValues: assetCatalog.enumerated().map { ($1.id, $0) })
        selectedAssets.sort {
            (catalogOrder[$0.id] ?? 0) < (catalogOrder[$1.id] ?? 0)
        }

        return selectedAssets
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// Overload accepting an optional tokenBudget alongside characterBudget.
    public func systemPrompt(
        for objective: String,
        toolkit: String = "System",
        tokenBudget: Int?,
        characterBudget: Int = 16_000
    ) -> String {
        let effectiveCharBudget = tokenBudget.map { min(characterBudget, $0 * 4) } ?? characterBudget
        return systemPrompt(for: objective, toolkit: toolkit, characterBudget: effectiveCharBudget)
    }

    private func isSimpleGreeting(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let greetings = ["hello", "hi", "hey", "good morning", "good afternoon", "good evening", "howdy", "greetings", "hello there", "hi there"]
        return greetings.contains(trimmed) || (trimmed.count < 25 && greetings.contains(where: { trimmed.hasPrefix($0) }))
    }

    private func greetingBoundedPrompt(toolkit: String) -> String {
        if let coreRules = asset(for: "CoreRules") {
            return coreRules.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return """
        # SwiftCode Assist
        You are SwiftCode Assist, an autonomous pair programmer for macOS. Answer ordinary conversational greetings politely and concisely without invoking tools or inflating context.
        """
    }

    // MARK: - Robust File Locator & Reader

    private func loadContent(for filename: String) -> String {
        if let url = locateAssetURL(filename: filename) {
            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                logger.error("Failed to read system asset at \(url.path): \(error.localizedDescription)")
            }
        }

        logger.warning("System asset \(filename) could not be located on disk or bundle; using fallback.")
        return fallbackContent(for: filename)
    }

    private func locateAssetURL(filename: String) -> URL? {
        let baseName = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension.isEmpty ? "md" : (filename as NSString).pathExtension

        // 1. Bundle.main "Assets" subdirectory
        if let url = Bundle.main.url(forResource: baseName, withExtension: ext, subdirectory: "Assets") {
            return url
        }

        // 2. Bundle.main flat
        if let url = Bundle.main.url(forResource: baseName, withExtension: ext) {
            return url
        }

        // 3. Bundle.main resourceURL / "Assets"
        if let resourceURL = Bundle.main.resourceURL {
            let candidate1 = resourceURL.appendingPathComponent("Assets").appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: candidate1.path) {
                return candidate1
            }
            let candidate2 = resourceURL.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: candidate2.path) {
                return candidate2
            }
        }

        // 4. Source tree fallback via #filePath
        let thisFile = URL(fileURLWithPath: #filePath)
        let backendAssistDir = thisFile.deletingLastPathComponent()
        let devAssetsDir = backendAssistDir.appendingPathComponent("Functions/Assets")
        let devFile = devAssetsDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: devFile.path) {
            return devFile
        }

        // 5. Common repo path fallbacks for runtime and test runner safety
        let fallbackPaths = [
            "/Users/dylan/SwiftCode-Mac/SwiftCode/Backend/Assist/Functions/Assets/\(filename)",
            "/Users/dylan/Library/Mobile Documents/com~apple~CloudDocs/Xcode Projects/SwiftCode-Mac/SwiftCode/Backend/Assist/Functions/Assets/\(filename)",
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("SwiftCode/Backend/Assist/Functions/Assets/\(filename)").path
        ]

        for path in fallbackPaths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    private func fallbackContent(for filename: String) -> String {
        "# System Asset: \(filename)\nAuthoritative documentation for \(filename)."
    }
}
