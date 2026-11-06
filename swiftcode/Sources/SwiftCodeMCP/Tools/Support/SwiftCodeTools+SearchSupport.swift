import Foundation

/// Shared workspace scanning for the ported Legacy search tools (Wave 3).
///
/// Behaviour source: Legacy's `AssistSearchFunctions`,
/// `AssistWorkspaceScan` / `AssistWorkspacePaths` /
/// `AssistToolingSupport` (Dylan's own code, ported under MIT), as
/// specified in `specs/ide/assist-search-git-tools.md`. The rules that
/// matter:
///
/// * `files(under:)` skips hidden files and any file whose *first*
///   path component (relative to the root) is a skipped directory
///   (`.git`, `.build`, `DerivedData`, …) — only the first component
///   is checked, as in Legacy.
/// * `searchText` skips hidden files, files over 1 MB, binary-extension
///   files, and files that do not decode as UTF-8. Literal matches are
///   case-insensitive; regex matches use a case-insensitive
///   `NSRegularExpression`, one match per matching line.
/// * `enumeratedFiles` (Legacy's `AssistToolingSupport` variant) keeps
///   regular files only, skips hidden files, and drops files over
///   `maxFileSize` (default 300 KB).
enum SearchWorkspace {
    static let skippedDirs: Set<String> = [
        ".git", ".build", "build", "DerivedData", ".swiftpm",
        "Pods", "Carthage", "node_modules", ".venv",
    ]
    static let sourceExts: Set<String> = ["swift", "m", "mm", "h", "c", "cpp", "hpp"]
    static let binaryExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "pdf", "zip", "exe", "dylib", "a"]
    static let codeExtensions: Set<String> = [
        "swift", "m", "mm", "h", "hpp", "c", "cpp", "js", "ts", "tsx", "jsx", "py", "rb", "java", "kt", "go", "rs",
    ]

    /// Enumerate files under `root`, skipping hidden files and skipped
    /// top-level directories. Directories are never returned.
    nonisolated static func files(under root: URL, extensions: Set<String>? = nil, maxFiles: Int = 20000) -> [URL] {
        var results: [URL] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return results
        }
        let rootPath = root.standardized.path
        while let url = enumerator.nextObject() as? URL, results.count < maxFiles {
            let rel: String
            if url.standardized.path.hasPrefix(rootPath + "/") {
                rel = String(url.standardized.path.dropFirst(rootPath.count + 1))
            } else {
                rel = url.standardized.path
            }
            if skippedDirs.contains(rel.split(separator: "/").first.map(String.init) ?? "") { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { continue }
            if let exts = extensions, !exts.contains(url.pathExtension.lowercased()) { continue }
            results.append(url)
        }
        return results
    }

    nonisolated static func swiftFiles(under root: URL, maxFiles: Int = 8000) -> [URL] {
        files(under: root, extensions: ["swift"], maxFiles: maxFiles)
    }

    /// Regular files only, hidden files skipped, files over
    /// `maxFileSize` dropped. No skipped-directory rule (Legacy's
    /// `AssistToolingSupport.enumeratedFiles` has none).
    nonisolated static func enumeratedFiles(at root: URL, allowedExtensions: Set<String>? = nil, maxFileSize: Int = 300_000) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                             options: [.skipsHiddenFiles]) else { return [] }
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            if let size = values.fileSize, size > maxFileSize { continue }
            if let allowedExtensions, !allowedExtensions.contains(fileURL.pathExtension.lowercased()) { continue }
            files.append(fileURL)
        }
        return files
    }

    nonisolated static func readLines(_ url: URL) -> [String]? {
        (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: .newlines)
    }

    /// Workspace-relative display path (`"."` for the root itself).
    nonisolated static func relative(_ url: URL, root: URL) -> String {
        let rootPath = root.standardized.path
        let path = url.standardized.path
        if path == rootPath { return "." }
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return path
    }

    /// `true` for the extensions Legacy counts as code files.
    nonisolated static func isCodeFile(_ url: URL) -> Bool {
        codeExtensions.contains(url.pathExtension.lowercased())
    }

    /// Function name declared on a `func ` line (strips generics and
    /// parameters), mirroring Legacy's `AssistWorkspaceScan`.
    nonisolated static func declaredFuncName(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("func ") || t.contains(" func ") else { return nil }
        guard let r = t.range(of: "func ") else { return nil }
        let rest = String(t[r.upperBound...])
        let name = rest.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" }).first.map(String.init) ?? ""
        return name.isEmpty ? nil : name
    }

    /// Searches every eligible file under `directory` for `pattern`,
    /// returning matching lines as `"<line>: <text>"` per file, sorted
    /// by path. Literal matches are case-insensitive; regex matches use
    /// a case-insensitive `NSRegularExpression` (an invalid pattern
    /// throws, as in Legacy).
    nonisolated static func searchText(in directory: URL, pattern: String, isRegex: Bool) throws -> [(url: URL, matches: [String])] {
        let fm = FileManager.default
        let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                       options: [.skipsHiddenFiles])
        var results: [(url: URL, matches: [String])] = []
        let regex = try isRegex ? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) : nil
        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            if let size = values?.fileSize, size > 1_000_000 { continue }
            if binaryExtensions.contains(fileURL.pathExtension.lowercased()) { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)
            var matches: [String] = []
            if let regex {
                for (index, line) in lines.enumerated() {
                    let range = NSRange(location: 0, length: line.utf16.count)
                    if regex.firstMatch(in: line, options: [], range: range) != nil {
                        matches.append("\(index + 1): \(line)")
                    }
                }
            } else {
                for (index, line) in lines.enumerated() where line.localizedCaseInsensitiveContains(pattern) {
                    matches.append("\(index + 1): \(line)")
                }
            }
            if !matches.isEmpty { results.append((fileURL, matches)) }
        }
        return results.sorted { $0.url.path < $1.url.path }
    }
}

/// One skill in the workspace's local skills library: a `SKILL.md` (or
/// `SKILLS.md` / `*.SKILL.md`) file, usually under
/// `.claude/skills/<name>/` or `.agents/skills/<name>/`.
///
/// SwiftCode has no equivalent of Legacy's `SkillIndex` (which indexed
/// `~/Library/Application Support/SwiftCode/Skills/` plus imported
/// Claude/Codex/VSCode/Antigravity libraries, with enable/disable
/// toggles and a disk cache). The port indexes the workspace's own
/// skill files instead — the surface SwiftCode actually has (its own
/// installed skill lives at `.claude/skills/swiftcode/SKILL.md` and
/// `.agents/skills/swiftcode/SKILL.md`; see `AgentSkill.swift`). Metadata
/// parsing and scoring mirror Legacy's `SkillIndex` behaviour only.
struct SearchSkill: Sendable {
    var id: String
    var name: String
    var description: String
    /// Absolute path of the skill file.
    var path: String
    /// Display name of the source (`"SwiftCode"`, `"Claude"`, …).
    var sourceKind: String
    var sourceDescription: String
    var tags: [String]
    var recommendedTools: [String]
    var searchableText: String
}

enum SearchSkillIndex {
    /// Token-scored search over the workspace's skill files, highest
    /// score first (Legacy's scoring: exact name +100, name contains
    /// +50, per token name +20, description +10, tag +15, body +5).
    /// An empty query returns the first `limit` skills by name.
    nonisolated static func search(query: String, limit: Int, in root: URL) -> [SearchSkill] {
        let skills = collectSkills(in: root)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return Array(skills.prefix(limit)) }
        let tokens = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var scored: [(skill: SearchSkill, score: Int)] = []
        for skill in skills {
            var score = 0
            let nameLower = skill.name.lowercased()
            let descLower = skill.description.lowercased()
            let textLower = skill.searchableText.lowercased()
            if nameLower == trimmed {
                score += 100
            } else if nameLower.contains(trimmed) {
                score += 50
            }
            for token in tokens {
                if nameLower.contains(token) { score += 20 }
                if descLower.contains(token) { score += 10 }
                if skill.tags.contains(where: { $0.lowercased().contains(token) }) { score += 15 }
                if textLower.contains(token) { score += 5 }
            }
            if score > 0 { scored.append((skill, score)) }
        }
        scored.sort { $0.score > $1.score }
        return scored.prefix(limit).map(\.skill)
    }

    /// Every skill file under `root`, by name. One descriptor per
    /// containing directory (the first skill file found there wins).
    /// Unlike Legacy's `SkillIndex` (whose library root is not
    /// hidden), this walk does NOT skip hidden files: SwiftCode's own
    /// skill lives under `.claude/skills/`. Only `.git` is skipped.
    nonisolated static func collectSkills(in root: URL) -> [SearchSkill] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return [] }
        var results: [SearchSkill] = []
        var visitedPaths = Set<String>()
        while let fileURL = enumerator.nextObject() as? URL {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue, fileURL.lastPathComponent == ".git" {
                enumerator.skipDescendants()
                continue
            }
            let filename = fileURL.lastPathComponent
            let isSkillFile = filename.caseInsensitiveCompare("SKILL.md") == .orderedSame
                || filename.caseInsensitiveCompare("SKILLS.md") == .orderedSame
                || filename.hasSuffix(".SKILL.md")
                || filename.hasSuffix(".SKILLS.md")
            guard isSkillFile else { continue }
            let skillDirectory = fileURL.deletingLastPathComponent()
            let skillPath = skillDirectory.path
            if visitedPaths.contains(skillPath) { continue }
            visitedPaths.insert(skillPath)
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            results.append(parseSkillMetadata(from: content, filename: filename, directoryURL: skillDirectory, fileURL: fileURL))
        }
        results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return results
    }

    /// Legacy's `SkillIndex.parseSkillMetadata`, adapted: the default
    /// source is the workspace library (`"SwiftCode"`), and a path under
    /// `.claude/skills` or `.agents/skills` takes that source unless
    /// the frontmatter `source:` says otherwise.
    nonisolated static func parseSkillMetadata(from markdown: String, filename: String, directoryURL: URL, fileURL: URL) -> SearchSkill {
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
        var sourceKind = "SwiftCode"
        var sourceDescription = "SwiftCode Workspace Skills"
        if fileURL.path.contains("/.claude/skills/") {
            sourceKind = "Claude"
            sourceDescription = "Claude Skills"
        } else if fileURL.path.contains("/.agents/skills/") {
            sourceKind = "Project"
            sourceDescription = "Project Skills"
        }

        if markdown.hasPrefix("---") {
            let parts = markdown.components(separatedBy: "---")
            if parts.count >= 3 {
                for line in parts[1].components(separatedBy: .newlines) {
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
                        if val.contains("claude") { sourceKind = "Claude"; sourceDescription = "Claude Skills" }
                        else if val.contains("codex") { sourceKind = "Codex"; sourceDescription = "Codex Skills" }
                        else if val.contains("vscode") { sourceKind = "VS Code"; sourceDescription = "VS Code Skills" }
                        else if val.contains("antigravity") { sourceKind = "Antigravity"; sourceDescription = "Antigravity Skills" }
                        else if val.contains("project") { sourceKind = "Project"; sourceDescription = "Project Skills" }
                        else if val.contains("user") { sourceKind = "User"; sourceDescription = "User Skills" }
                    }
                }
            }
        }

        let metadataSidecar = directoryURL.appendingPathComponent("metadata.json")
        if let data = try? Data(contentsOf: metadataSidecar),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let jName = json["name"] as? String, !jName.isEmpty { name = jName }
            if let jDesc = json["description"] as? String, !jDesc.isEmpty { description = jDesc }
            if let jTags = json["tags"] as? [String] { tags = jTags }
            if let jTools = json["recommendedTools"] as? [String] { recommendedTools = jTools }
            if let jSource = json["source"] as? String {
                sourceDescription = jSource
                let lower = jSource.lowercased()
                if lower.contains("claude") { sourceKind = "Claude" }
                else if lower.contains("codex") { sourceKind = "Codex" }
                else if lower.contains("vscode") { sourceKind = "VS Code" }
                else if lower.contains("antigravity") { sourceKind = "Antigravity" }
            }
        }

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
        return SearchSkill(
            id: cleanId.isEmpty ? String(UUID().uuidString.prefix(8)).lowercased() : cleanId,
            name: name,
            description: description,
            path: fileURL.path,
            sourceKind: sourceKind,
            sourceDescription: sourceDescription,
            tags: tags,
            recommendedTools: recommendedTools,
            searchableText: "\(name) \(description) \(tags.joined(separator: " ")) \(markdown.prefix(2000))"
        )
    }
}
