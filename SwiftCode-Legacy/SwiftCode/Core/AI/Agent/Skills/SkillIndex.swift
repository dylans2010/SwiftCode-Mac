//
//  SkillIndex.swift
//  SwiftCode
//
//  In-memory, indexed representation and cache of authoritative SwiftCode agent skills.
//

import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.Skills", category: "SkillIndex")

@MainActor
public final class SkillIndex: ObservableObject {
    public static let shared = SkillIndex()

    @Published public private(set) var skills: [SkillDescriptor] = []
    @Published public private(set) var isIndexing: Bool = false
    @Published public private(set) var lastIndexedDate: Date? = nil

    private let fileManager = FileManager.default
    private var directoryMonitorSource: DispatchSourceFileSystemObject?
    private var monitorFileDescriptor: Int32 = -1

    public var authoritativeSkillsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let swiftCodeDir = appSupport.appendingPathComponent("SwiftCode", isDirectory: true)
        let skillsDir = swiftCodeDir.appendingPathComponent("Skills", isDirectory: true)
        try? fileManager.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        return skillsDir
    }

    private var indexCacheFileURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let swiftCodeDir = appSupport.appendingPathComponent("SwiftCode", isDirectory: true)
        try? fileManager.createDirectory(at: swiftCodeDir, withIntermediateDirectories: true)
        return swiftCodeDir.appendingPathComponent("skills_index.json")
    }

    private init() {
        loadCachedIndex()
        startDirectoryMonitoring()
        Task {
            await self.rebuildIndex()
        }
    }

    // MARK: - Fast In-Memory Search (Sub-millisecond)

    /// Instantly queries indexed skills by token matching across name, description, tags, and searchableText.
    public func search(query: String, limit: Int = 10) -> [SkillDescriptor] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return Array(skills.prefix(limit))
        }

        let tokens = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        var scoredSkills: [(skill: SkillDescriptor, score: Int)] = []

        for skill in skills {
            var score = 0
            let nameLower = skill.name.lowercased()
            let descLower = skill.description.lowercased()
            let textLower = skill.searchableText.lowercased()

            // Exact match bonus
            if nameLower == trimmed {
                score += 100
            } else if nameLower.contains(trimmed) {
                score += 50
            }

            for token in tokens {
                if nameLower.contains(token) {
                    score += 20
                }
                if descLower.contains(token) {
                    score += 10
                }
                if skill.tags.contains(where: { $0.lowercased().contains(token) }) {
                    score += 15
                }
                if textLower.contains(token) {
                    score += 5
                }
            }

            if score > 0 {
                scoredSkills.append((skill, score))
            }
        }

        scoredSkills.sort { $0.score > $1.score }
        return scoredSkills.prefix(limit).map { $0.skill }
    }

    public func allSkills() -> [SkillDescriptor] {
        return skills
    }

    public func skill(for id: String) -> SkillDescriptor? {
        return skills.first { $0.id == id }
    }

    /// Reads the actual markdown instructions (SKILL.md) for a given skill on demand.
    public func loadSkillContent(for id: String) -> String? {
        guard let item = skill(for: id) else { return nil }
        let targetURL = URL(fileURLWithPath: item.path)
        var fileToRead = targetURL

        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: targetURL.path, isDirectory: &isDir), isDir.boolValue {
            let candidate1 = targetURL.appendingPathComponent("SKILL.md")
            let candidate2 = targetURL.appendingPathComponent("SKILLS.md")
            if fileManager.fileExists(atPath: candidate1.path) {
                fileToRead = candidate1
            } else if fileManager.fileExists(atPath: candidate2.path) {
                fileToRead = candidate2
            }
        }

        return try? String(contentsOf: fileToRead, encoding: .utf8)
    }

    public func toggleSkill(id: String) {
        if let idx = skills.firstIndex(where: { $0.id == id }) {
            skills[idx].isEnabled.toggle()
            UserDefaults.standard.set(skills[idx].isEnabled, forKey: "skill_enabled_\(id)")
            saveIndexCache()
        }
    }

    public func toggleSkillEnabled(id: String, enabled: Bool) {
        if let idx = skills.firstIndex(where: { $0.id == id }) {
            skills[idx].isEnabled = enabled
            UserDefaults.standard.set(enabled, forKey: "skill_enabled_\(id)")
            saveIndexCache()
        }
    }

    public func deleteSkill(id: String) throws {
        if let idx = skills.firstIndex(where: { $0.id == id }) {
            let item = skills[idx]
            let path = item.path
            if fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(atPath: path)
            }
            skills.remove(at: idx)
            saveIndexCache()
        }
    }

    // MARK: - Index Rebuilding

    public func rebuildIndex() async {
        guard !isIndexing else { return }
        isIndexing = true
        defer { isIndexing = false }

        let baseDir = authoritativeSkillsDirectory
        let descriptors = await Task.detached(priority: .utility) { () -> [SkillDescriptor] in
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: baseDir,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            var results: [SkillDescriptor] = []
            var visitedPaths = Set<String>()

            while let fileURL = enumerator.nextObject() as? URL {
                let filename = fileURL.lastPathComponent
                let isSkillFile = filename.caseInsensitiveCompare("SKILL.md") == .orderedSame
                    || filename.caseInsensitiveCompare("SKILLS.md") == .orderedSame
                    || filename.hasSuffix(".SKILL.md")
                    || filename.hasSuffix(".SKILLS.md")

                guard isSkillFile else { continue }

                // The containing directory is usually the skill directory unless it's a standalone skill file
                let skillDirectory = fileURL.deletingLastPathComponent()
                let skillPath = skillDirectory.path
                if visitedPaths.contains(skillPath) { continue }
                visitedPaths.insert(skillPath)

                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

                let parsed = Self.parseSkillMetadata(from: content, filename: filename, directoryURL: skillDirectory)
                let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()

                let isEnabled = UserDefaults.standard.bool(forKey: "skill_enabled_\(parsed.id)")
                let finalEnabled = UserDefaults.standard.object(forKey: "skill_enabled_\(parsed.id)") == nil ? true : isEnabled

                let descriptor = SkillDescriptor(
                    id: parsed.id,
                    name: parsed.name,
                    description: parsed.description,
                    path: fileURL.path,
                    sourceKind: parsed.sourceKind,
                    sourceDescription: parsed.sourceDescription,
                    originalPath: parsed.originalPath,
                    tags: parsed.tags,
                    recommendedTools: parsed.recommendedTools,
                    searchableText: "\(parsed.name) \(parsed.description) \(parsed.tags.joined(separator: " ")) \(content.prefix(2000))",
                    lastModified: modDate,
                    isEnabled: finalEnabled
                )
                results.append(descriptor)
            }

            results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return results
        }.value

        self.skills = descriptors
        self.lastIndexedDate = Date()
        saveIndexCache()
        logger.info("Successfully rebuilt SkillIndex with \(descriptors.count) authoritative skills.")
    }

    // MARK: - Metadata Extraction

    public struct ParsedSkillMetadata {
        public let id: String
        public let name: String
        public let description: String
        public let tags: [String]
        public let recommendedTools: [String]
        public let sourceKind: SkillSourceKind
        public let sourceDescription: String
        public let originalPath: String?
    }

    nonisolated public static func parseSkillMetadata(from markdown: String, filename: String, directoryURL: URL) -> ParsedSkillMetadata {
        var name = directoryURL.lastPathComponent
        if name.isEmpty || name == "." || name == "/" {
            name = filename.replacingOccurrences(of: ".SKILL.md", with: "")
                .replacingOccurrences(of: ".SKILLS.md", with: "")
                .replacingOccurrences(of: "SKILL.md", with: "")
                .replacingOccurrences(of: "SKILLS.md", with: "")
        }

        var description = "No description provided."
        var tags: [String] = []
        var recommendedTools: [String] = []
        var sourceKind: SkillSourceKind = .swiftcode
        var sourceDescription = "SwiftCode Local Library"
        var originalPath: String? = nil

        // 1. Check YAML frontmatter (between --- and ---)
        if markdown.hasPrefix("---") {
            let parts = markdown.components(separatedBy: "---")
            if parts.count >= 3 {
                let frontmatter = parts[1]
                let lines = frontmatter.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("name:") {
                        let val = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        if !val.isEmpty { name = val }
                    } else if trimmed.hasPrefix("description:") {
                        let val = trimmed.dropFirst(12).trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        if !val.isEmpty { description = val }
                    } else if trimmed.hasPrefix("tags:") {
                        let val = trimmed.dropFirst(5).trimmingCharacters(in: CharacterSet(charactersIn: " []\"'"))
                        tags = val.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    } else if trimmed.hasPrefix("tools:") {
                        let val = trimmed.dropFirst(6).trimmingCharacters(in: CharacterSet(charactersIn: " []\"'"))
                        recommendedTools = val.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    } else if trimmed.hasPrefix("source:") {
                        let val = trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces).lowercased()
                        if val.contains("claude") { sourceKind = .claude }
                        else if val.contains("codex") { sourceKind = .codex }
                        else if val.contains("vscode") { sourceKind = .vscode }
                        else if val.contains("antigravity") { sourceKind = .antigravity }
                        else if val.contains("project") { sourceKind = .project }
                        else if val.contains("user") { sourceKind = .user }
                    } else if trimmed.hasPrefix("original_path:") {
                        originalPath = trimmed.dropFirst(14).trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }

        // 2. Look for JSON metadata if sidecar exists
        let metadataSidecar = directoryURL.appendingPathComponent("metadata.json")
        if let data = try? Data(contentsOf: metadataSidecar),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let jName = json["name"] as? String, !jName.isEmpty { name = jName }
            if let jDesc = json["description"] as? String, !jDesc.isEmpty { description = jDesc }
            if let jTags = json["tags"] as? [String] { tags = jTags }
            if let jTools = json["recommendedTools"] as? [String] { recommendedTools = jTools }
            if let jSource = json["source"] as? String {
                sourceDescription = jSource
                if jSource.lowercased().contains("claude") { sourceKind = .claude }
                else if jSource.lowercased().contains("codex") { sourceKind = .codex }
                else if jSource.lowercased().contains("vscode") { sourceKind = .vscode }
                else if jSource.lowercased().contains("antigravity") { sourceKind = .antigravity }
            }
            if let jOrig = json["originalPath"] as? String { originalPath = jOrig }
        }

        // 3. Fallback extraction from leading markdown heading
        if description == "No description provided." {
            for line in markdown.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("# ") && name == directoryURL.lastPathComponent {
                    name = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                } else if !trimmed.isEmpty && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("---") {
                    description = String(trimmed.prefix(200))
                    break
                }
            }
        }

        let cleanId = directoryURL.lastPathComponent
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")

        return ParsedSkillMetadata(
            id: cleanId.isEmpty ? UUID().uuidString.prefix(8).lowercased() : cleanId,
            name: name,
            description: description,
            tags: tags,
            recommendedTools: recommendedTools,
            sourceKind: sourceKind,
            sourceDescription: sourceDescription,
            originalPath: originalPath
        )
    }

    // MARK: - Persistence Cache

    private func loadCachedIndex() {
        guard fileManager.fileExists(atPath: indexCacheFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: indexCacheFileURL)
            let decoded = try JSONDecoder().decode([SkillDescriptor].self, from: data)
            self.skills = decoded
            logger.info("Loaded \(decoded.count) cached skills from disk index.")
        } catch {
            logger.warning("Failed to load skills index cache: \(error.localizedDescription)")
        }
    }

    private func saveIndexCache() {
        do {
            let data = try JSONEncoder().encode(skills)
            try data.write(to: indexCacheFileURL, options: .atomic)
        } catch {
            logger.error("Failed to save skills index cache: \(error.localizedDescription)")
        }
    }

    // MARK: - File System Monitoring

    private func startDirectoryMonitoring() {
        stopDirectoryMonitoring()
        let dirPath = authoritativeSkillsDirectory.path
        let fd = Darwin.open(dirPath, O_EVTONLY)
        guard fd >= 0 else { return }

        self.monitorFileDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .extend, .attrib, .link, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                await self?.rebuildIndex()
            }
        }

        source.setCancelHandler { [fd] in
            Darwin.close(fd)
        }

        self.directoryMonitorSource = source
        source.resume()
    }

    private func stopDirectoryMonitoring() {
        if let source = directoryMonitorSource {
            source.cancel()
            directoryMonitorSource = nil
        }
        monitorFileDescriptor = -1
    }
}
