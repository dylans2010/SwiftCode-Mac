import Foundation
import os

// MARK: - Assist v3 Skill Entity Model

public struct DiscoveredSkill: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let description: String
    public let filePath: String
    public let author: String
    public let version: String
    public let tags: [String]
    public let recommendedTools: [String]
    public let guidance: [String]
    public let fullContent: String

    public init(
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

// MARK: - Agent Skill Resolver

public final class AgentSkillResolver: Sendable {
    public static let shared = AgentSkillResolver()
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "AgentSkillResolver")

    private init() {}

    /// Recursively discovers all available skills in workspace, configuration roots, and bundled resources.
    public func discoverSkills(in workspaceRoot: URL) async -> [DiscoveredSkill] {
        var results: [DiscoveredSkill] = []
        let fileManager = FileManager.default

        // Standard discovery search roots
        let searchDirectories = [
            workspaceRoot.appendingPathComponent(".agents/skills"),
            workspaceRoot.appendingPathComponent(".skills"),
            workspaceRoot.appendingPathComponent("skills"),
            workspaceRoot.appendingPathComponent("SwiftCode/Views/Settings/Skills/Presets"),
            Bundle.main.resourceURL?.appendingPathComponent("Skills"),
            Bundle.main.resourceURL?.appendingPathComponent("Presets")
        ]

        logger.info("Initiating skills discovery across \(searchDirectories.count) potential roots...")

        for dir in searchDirectories {
            guard let dir = dir, fileManager.fileExists(atPath: dir.path) else { continue }
            discoverSkillsRecursively(in: dir, results: &results)
        }

        DiagnosticEventBus.shared.logEvent(
            component: "AgentSkillResolver",
            severity: "INFO",
            category: "skills",
            message: "Discovered \(results.count) available skills across workspace and bundle."
        )

        return results
    }

    private func discoverSkillsRecursively(in directory: URL, results: inout [DiscoveredSkill]) {
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
    public func matchSkills(for objective: String, in skills: [DiscoveredSkill]) -> [DiscoveredSkill] {
        let lowerObjective = objective.lowercased()
        var matched: [DiscoveredSkill] = []

        for skill in skills {
            let lowerName = skill.name.lowercased()
            let lowerDesc = skill.description.lowercased()

            // Check name, description, and tags against objective tokens
            let nameMatch = lowerObjective.contains(lowerName)
            let descMatch = skill.tags.contains { tag in lowerObjective.contains(tag.lowercased()) }

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
    private func parseSkill(from content: String, filePath: String) -> DiscoveredSkill? {
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

        return DiscoveredSkill(
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
    public func formatSkillsBlock(matched: [DiscoveredSkill], totalDiscovered: Int) -> String {
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
