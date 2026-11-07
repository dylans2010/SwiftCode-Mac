import Foundation

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

    nonisolated static func relative(_ url: URL, root: URL) -> String {
        let rootPath = root.standardized.path
        let path = url.standardized.path
        if path == rootPath { return "." }
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return path
    }

    nonisolated static func isCodeFile(_ url: URL) -> Bool {
        codeExtensions.contains(url.pathExtension.lowercased())
    }

    nonisolated static func declaredFuncName(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("func ") || t.contains(" func ") else { return nil }
        guard let r = t.range(of: "func ") else { return nil }
        let rest = String(t[r.upperBound...])
        let name = rest.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" }).first.map(String.init) ?? ""
        return name.isEmpty ? nil : name
    }

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

struct SearchSkill: Sendable {
    var id: String
    var name: String
    var description: String
    var path: String
    var sourceKind: String
    var sourceDescription: String
    var tags: [String]
    var recommendedTools: [String]
    var searchableText: String
}

enum SearchSkillIndex {
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
