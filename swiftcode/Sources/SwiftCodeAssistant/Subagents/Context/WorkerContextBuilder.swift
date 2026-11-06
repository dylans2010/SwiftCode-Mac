import Foundation
import os

// MARK: - Skill discovery (ported from Legacy `AgentSkillResolver`)
//
// Legacy's `WorkerContextBuilder` called `AgentSkillResolver.shared` for
// skill discovery / matching / prompt formatting. That resolver is not in
// this target, so its three algorithms are ported here as file-private
// helpers over a file-private skill value — same search roots, same
// `SKILL.md` filename rules, same YAML-frontmatter parsing, same
// name/description/tag/keyword matching, same prompt block format — so
// the builder's behaviour is unchanged without depending on a type that
// does not exist yet. When `AgentSkillResolver` (or the destination's
// `SkillDiscoveryService`/`SkillIndex`) is wired for workers, these
// helpers can be replaced; the prompt this builder produces stays the same.

/// A skill discovered from a `SKILL.md` file on disk.
private struct WorkerDiscoveredSkill: Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let description: String
    let filePath: String
    let author: String
    let version: String
    let tags: [String]
    let recommendedTools: [String]
    let guidance: [String]
    let fullContent: String

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        filePath: String,
        author: String = "SwiftCode",
        version: String = "1.0.0",
        tags: [String] = [],
        recommendedTools: [String] = [],
        guidance: [String] = [],
        fullContent: String = ""
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.filePath = filePath
        self.author = author
        self.version = version
        self.tags = tags
        self.recommendedTools = recommendedTools
        self.guidance = guidance
        self.fullContent = fullContent
    }
}

@MainActor
public final class WorkerContextBuilder: Sendable {
    public static let shared = WorkerContextBuilder()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerContextBuilder")
    private var lastSkillScan: (root: String, timestamp: Date, skills: [WorkerDiscoveredSkill])?

    private init() {}

    public func buildWorkerPrompt(
        for worker: Worker,
        assignment: WorkerAssignment,
        context: WorkerExecutionContext,
        dependencyResults: [WorkerResult] = []
    ) async -> String {
        let discoveredSkills = await discoverSkills(in: context.workspaceRoot)
        let matchedSkills = matchSkills(for: "\(worker.role) \(worker.scope)", in: discoveredSkills)
        let skillsBlock = formatSkillsBlock(matched: matchedSkills, totalDiscovered: discoveredSkills.count)

        let agentsInstructions = loadWorkspaceRules(root: context.workspaceRoot)
        let scopedRules = filterRelevantRules(agentsInstructions, for: worker.scope)

        let relevantFileContents = await loadRelevantFiles(
            targetFiles: assignment.targetFiles,
            scope: worker.scope,
            workspaceRoot: context.workspaceRoot
        )

        var dependencyContext = ""
        if !dependencyResults.isEmpty {
            dependencyContext = "## DEPENDENCY OUTPUTS FROM PRIOR WORKERS\n"
            for result in dependencyResults {
                dependencyContext += "- Worker '\(result.workerName)': \(result.summary)\n"
                if !result.modifiedFiles.isEmpty {
                    dependencyContext += "  Modified Files: \(result.modifiedFiles.joined(separator: ", "))\n"
                }
                if !result.completedWork.isEmpty {
                    dependencyContext += "  Milestones: \(result.completedWork.joined(separator: " | "))\n"
                }
            }
        }

        let excludedFiles = await identifyExcludedFiles(
            targetFiles: assignment.targetFiles,
            workspaceRoot: context.workspaceRoot
        )

        let prompt = """
        # ASSIST WORKER OPERATING POLICY (ISOLATED EXECUTION)

        You are an autonomous Assist Worker executing as part of the SwiftCode development team.
        You are operating in ISOLATION under the direction of the Parent Assist Orchestrator.

        ## WORKER IDENTITY & CONTRACT
        - Worker ID: \(worker.id.uuidString)
        - Worker Name: "\(worker.name)"
        - Assigned Role: "\(worker.role)"
        - Parent Task ID: \(worker.parentTaskID.uuidString)

        ## MANDATORY SCOPE BOUNDARIES (INV-6, INV-8)
        - YOUR SCOPE: "\(worker.scope)"
        - YOUR RESPONSIBILITIES: "\(worker.task)"
        - YOUR TARGET FILES: \(assignment.targetFiles.isEmpty ? "None specified - infer from scope" : assignment.targetFiles.joined(separator: ", "))
        - YOUR EXCLUSIONS: Do NOT modify files outside your declared scope. Never attempt global task completion. Report any adjacent discovered work back to the orchestrator rather than absorbing it.

        ## CONTEXT ISOLATION
        You receive ONLY the context relevant to your assignment. Other workers are handling other parts of the codebase.
        Relevant files for your scope:
        \(relevantFileContents.isEmpty ? "No pre-loaded file contents. Inspect files as needed within your scope." : relevantFileContents)

        Files explicitly excluded from your scope:
        \(excludedFiles.isEmpty ? "None" : excludedFiles.joined(separator: ", "))

        ## NON-CONVERSATIONAL INVARIANT (INV-2)
        - NEVER ask the user questions or request clarification/approval/choices.
        - Infer from context -> inspect repo -> inspect AGENTS.md -> make the best engineering choice -> execute.
        - If fundamentally blocked, declare BLOCKED with a clear diagnostic explanation.

        ## WORKSPACE INSTRUCTIONS (AGENTS.MD - FILTERED FOR YOUR SCOPE)
        \(scopedRules.isEmpty ? "No specific workspace AGENTS.md rules declared for your scope." : scopedRules)

        ## RELEVANT SKILLS
        \(skillsBlock)

        \(dependencyContext)

        ## EXECUTION INSTRUCTIONS
        Fulfill your assigned task thoroughly. Make atomic, correct, and self-verifying changes.
        """

        return prompt
    }

    private func loadWorkspaceRules(root: URL) -> String {
        let candidates = ["AGENTS.md", "Agents.md", "Agent.md"]
        for candidate in candidates {
            let fileURL = root.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    return String(content.prefix(4000))
                }
            }
        }
        return ""
    }

    private func filterRelevantRules(_ rules: String, for scope: String) -> String {
        guard !rules.isEmpty else { return "" }
        let scopeKeywords = scope.lowercased().split(separator: " ").map(String.init)
        let lines = rules.components(separatedBy: .newlines)
        var relevantLines: [String] = []
        var currentSection = ""
        var currentSectionRelevant = true

        for line in lines {
            if line.hasPrefix("#") {
                currentSection = line
                currentSectionRelevant = scopeKeywords.contains { keyword in
                    line.lowercased().contains(keyword)
                } || scopeKeywords.contains { keyword in
                    scope.lowercased().contains(keyword) && line.lowercased().contains("worker")
                }
                if currentSectionRelevant {
                    relevantLines.append(line)
                }
            } else if currentSectionRelevant {
                relevantLines.append(line)
            }
        }

        return relevantLines.isEmpty ? rules : relevantLines.joined(separator: "\n")
    }

    private func loadRelevantFiles(
        targetFiles: [String],
        scope: String,
        workspaceRoot: URL
    ) async -> String {
        if targetFiles.isEmpty { return "" }

        var contents: [String] = []
        for filePath in targetFiles.prefix(10) {
            let fullPath = workspaceRoot.appendingPathComponent(filePath)
            guard FileManager.default.fileExists(atPath: fullPath.path) else { continue }
            guard let content = try? String(contentsOf: fullPath, encoding: .utf8) else { continue }
            let capped = String(content.prefix(2000))
            contents.append("### \(filePath)\n```\n\(capped)\n```")
        }
        return contents.joined(separator: "\n\n")
    }

    private func identifyExcludedFiles(
        targetFiles: [String],
        workspaceRoot: URL
    ) async -> [String] {
        let allSwiftFiles = FileManager.default.enumerator(
            at: workspaceRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        )?.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { $0.lastPathComponent } ?? []

        let targetSet = Set(targetFiles.map { URL(fileURLWithPath: $0).lastPathComponent })
        return allSwiftFiles.filter { !targetSet.contains($0) }.sorted()
    }

    // MARK: - Skill discovery (Legacy `AgentSkillResolver` algorithms)

    /// Recursively discovers all available skills in workspace, configuration roots, and bundled resources.
    private func discoverSkills(in workspaceRoot: URL) async -> [WorkerDiscoveredSkill] {
        let rootKey = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath().path
        if let cached = lastSkillScan,
           cached.root == rootKey,
           Date().timeIntervalSince(cached.timestamp) < 10.0 {
            return cached.skills
        }

        var results: [WorkerDiscoveredSkill] = []
        let fileManager = FileManager.default

        // Standard discovery search roots
        let searchDirectories = [
            workspaceRoot.appendingPathComponent(".agents/skills"),
            workspaceRoot.appendingPathComponent(".skills"),
            workspaceRoot.appendingPathComponent("skills"),
            workspaceRoot.appendingPathComponent("SwiftCode/Views/Settings/Skills/Presets"),
            Bundle.main.resourceURL?.appendingPathComponent("Skills"),
            Bundle.main.resourceURL?.appendingPathComponent("Presets"),
        ]

        logger.info("Initiating skills discovery across \(searchDirectories.count) potential roots...")

        for dir in searchDirectories {
            guard let dir = dir, fileManager.fileExists(atPath: dir.path) else { continue }
            discoverSkillsRecursively(in: dir, results: &results)
        }

        logger.info("Discovered \(results.count) available skills across workspace and bundle.")

        lastSkillScan = (root: rootKey, timestamp: Date(), skills: results)
        return results
    }

    private func discoverSkillsRecursively(in directory: URL, results: inout [WorkerDiscoveredSkill]) {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: []) else {
            return
        }

        for case let fileURL as URL in enumerator {
            let filename = fileURL.lastPathComponent
            if filename == "SKILL.md" || filename == "SKILLS.md" || filename.hasSuffix(".SKILL.md") || filename.hasSuffix(".SKILLS.md") {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    if let skill = parseSkill(from: content, filePath: fileURL.path) {
                        if !results.contains(where: { $0.name == skill.name }) {
                            results.append(skill)
                        }
                    }
                }
            }
        }
    }

    /// Evaluates which discovered skills are relevant to the active objective.
    private func matchSkills(for objective: String, in skills: [WorkerDiscoveredSkill]) -> [WorkerDiscoveredSkill] {
        let lowerObjective = objective.lowercased()
        var matched: [WorkerDiscoveredSkill] = []

        for skill in skills {
            let lowerName = skill.name.lowercased()
            let lowerDesc = skill.description.lowercased()

            // Check name, description, and tags against objective tokens
            let nameMatch = lowerObjective.contains(lowerName)
            let descMatch = lowerObjective.contains(lowerDesc) || skill.tags.contains { tag in lowerObjective.contains(tag.lowercased()) }

            if nameMatch || descMatch {
                matched.append(skill)
            } else {
                // Secondary check: keyword overlap
                let keywords = lowerName.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 3 }
                if keywords.contains(where: { lowerObjective.contains($0) }) {
                    matched.append(skill)
                }
            }
        }

        return matched
    }

    /// Parses YAML frontmatter and markdown sections from a SKILL.md file.
    private func parseSkill(from content: String, filePath: String) -> WorkerDiscoveredSkill? {
        let lines = content.components(separatedBy: .newlines)

        var metadata: [String: String] = [:]
        var bodyContent = content

        // Extract YAML frontmatter if present
        if content.hasPrefix("---") {
            let parts = content.components(separatedBy: "---")
            if parts.count >= 3 {
                let yaml = parts[1]
                bodyContent = parts.dropFirst(2).joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)

                for line in yaml.components(separatedBy: .newlines) {
                    let kv = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                    if kv.count == 2 {
                        metadata[kv[0]] = kv[1]
                    }
                }
            }
        }

        let name = metadata["name"] ?? lines.first(where: { $0.hasPrefix("# ") })?.dropFirst(2).trimmingCharacters(in: .whitespaces) ?? URL(fileURLWithPath: filePath).deletingLastPathComponent().lastPathComponent
        let description = metadata["description"] ?? lines.first(where: { !$0.isEmpty && !$0.hasPrefix("#") })?.trimmingCharacters(in: .whitespaces) ?? "Skill for \(name)"
        let author = metadata["author"] ?? "SwiftCode"
        let version = metadata["version"] ?? "1.0.0"

        let rawTags = metadata["tags"] ?? metadata["keywords"] ?? ""
        let tags = rawTags.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { !$0.isEmpty }

        let tools = metadata["recommendedTools"]?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        let guidance = metadata["guidance"]?.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) } ?? []

        return WorkerDiscoveredSkill(
            name: name,
            description: description,
            filePath: filePath,
            author: author,
            version: version,
            tags: tags,
            recommendedTools: tools,
            guidance: guidance,
            fullContent: bodyContent
        )
    }

    /// Formats matching skills for system prompt context injection.
    private func formatSkillsBlock(matched: [WorkerDiscoveredSkill], totalDiscovered: Int) -> String {
        if matched.isEmpty {
            return """
            # DISCOVERED SYSTEM SKILLS
            Skill discovery completed (\(totalDiscovered) available skills scanned).
            No applicable Skill was identified for this specific objective.
            """
        }

        var block = "# APPLICABLE AGENT SKILLS (\(matched.count) MATCHED)\n"
        for s in matched {
            block += "## Skill: \(s.name)\n"
            block += "- Description: \(s.description)\n"
            if !s.recommendedTools.isEmpty {
                block += "- Recommended Tools: \(s.recommendedTools.joined(separator: ", "))\n"
            }
            if !s.guidance.isEmpty {
                block += "- Guidance: \(s.guidance.joined(separator: "; "))\n"
            }
            if !s.fullContent.isEmpty {
                block += "\nInstructions:\n\(s.fullContent.prefix(1500))\n"
            }
            block += "----------------------------------------\n"
        }
        return block
    }
}
