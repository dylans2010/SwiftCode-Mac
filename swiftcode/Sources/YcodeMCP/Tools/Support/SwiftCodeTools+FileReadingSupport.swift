import Crypto
import Foundation
import YcodeIDECore

extension SwiftCodeMCPHost {
    func fileReadingDirectory(in s: WorkspaceSession) -> URL {
        let root = Self.folder(of: s.model)
        guard let dir = currentDirectory?.standardizedFileURL, Self.isInside(dir, root) else { return root }
        return dir
    }

    func resolveFileReadingPath(_ path: String, in s: WorkspaceSession) throws -> URL {
        let root = Self.folder(of: s.model)
        let url: URL
        if path.hasPrefix("~") {
            url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        } else if path.hasPrefix("/") {
            let absolute = URL(fileURLWithPath: path).standardizedFileURL
            if Self.isInside(absolute, root) {
                url = absolute
            } else {
                let rel = String(path.drop(while: { $0 == "/" }))
                url = root.appendingPathComponent(rel).standardizedFileURL
            }
        } else {
            url = fileReadingDirectory(in: s).appendingPathComponent(path).standardizedFileURL
        }
        guard Self.isInside(url, root) else { throw MCPToolError("\(path) is outside the workspace folder \(root.path)") }
        return url
    }

    func artifactDirectory(in s: WorkspaceSession) -> URL {
        Self.folder(of: s.model).appendingPathComponent(".assist_temp/artifacts", isDirectory: true)
    }

    func backupDirectory(in s: WorkspaceSession) -> URL {
        Self.folder(of: s.model).appendingPathComponent(".assist_temp/backups", isDirectory: true)
    }

    func artifactIndexURL(in s: WorkspaceSession) -> URL {
        artifactDirectory(in: s).appendingPathComponent(".artifacts_index.json")
    }

    func loadFileReadingArtifactIndex(in s: WorkspaceSession) -> [String: FileReadingArtifactIndexEntry] {
        guard let data = try? Data(contentsOf: artifactIndexURL(in: s)),
              let index = try? JSONDecoder().decode([String: FileReadingArtifactIndexEntry].self, from: data) else { return [:] }
        return index
    }

    func saveFileReadingArtifactIndex(_ index: [String: FileReadingArtifactIndexEntry], in s: WorkspaceSession) {
        let dir = artifactDirectory(in: s)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: artifactIndexURL(in: s), options: .atomic)
    }

    func listFileReadingArtifacts(in s: WorkspaceSession) -> [FileReadingArtifact] {
        let root = Self.folder(of: s.model)
        let fm = FileManager.default
        let index = loadFileReadingArtifactIndex(in: s)
        let dir = artifactDirectory(in: s)
        var found: [FileReadingArtifact] = []
        let mediaExtensions = ["md", "png", "mov", "mp4", "jpg", "jpeg"]
        if let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
                                                      options: [.skipsHiddenFiles]) {
            for url in entries where mediaExtensions.contains(url.pathExtension.lowercased()) {
                let filename = url.lastPathComponent
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
                let modified = values?.contentModificationDate ?? Date()
                let entry = index[filename]
                let ext = url.pathExtension.lowercased()
                let description = entry?.description ?? (ext == "md" ? (Self.firstMeaningfulLine(of: url) ?? "") : "\(ext.uppercased()) media artifact")
                let kind: String
                if let entry { kind = entry.kind } else if ext == "png" || ext == "jpg" || ext == "jpeg" { kind = "image" }
                else if ext == "mov" || ext == "mp4" { kind = "screen_recording" }
                else { kind = FileReadingArtifactNaming.inferredKind(for: filename) }
                found.append(FileReadingArtifact(filename: filename, title: FileReadingArtifactNaming.displayTitle(for: filename),
                                                 description: description, kind: kind,
                                                 relativePath: ".assist_temp/artifacts/\(filename)", modifiedAt: modified))
            }
        }
        let notesURL = root.appendingPathComponent("agent_notes.md")
        if fm.fileExists(atPath: notesURL.path) {
            let values = try? notesURL.resourceValues(forKeys: [.contentModificationDateKey])
            found.append(FileReadingArtifact(filename: "agent_notes.md", title: "Agent Notes",
                                             description: "Live agent notes and execution plan for the active task.",
                                             kind: "agent_notes", relativePath: "agent_notes.md",
                                             modifiedAt: values?.contentModificationDate ?? Date()))
        }
        found.sort { $0.modifiedAt > $1.modifiedAt }
        return found
    }

    func readFileReadingArtifact(named name: String, in s: WorkspaceSession) throws -> (record: FileReadingArtifact, content: String, truncated: Bool) {
        guard let filename = FileReadingArtifactNaming.normalize(name) else {
            throw MCPToolError("Invalid artifact name '\(name)'. Use snake_case with a .md extension (e.g. repository_analysis.md).")
        }
        let matches = listFileReadingArtifacts(in: s).filter { $0.filename.lowercased() == filename.lowercased() }
        guard let record = matches.first else { throw MCPToolError("No artifact named '\(filename)' exists in the artifact store.") }
        let url = Self.folder(of: s.model).appendingPathComponent(record.relativePath)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw MCPToolError("Failed to read artifact: could not decode \(filename) as UTF-8")
        }
        let maxCharacters = 60_000
        if content.count > maxCharacters {
            return (record, String(content.prefix(maxCharacters))
                + "\n… [truncated: showing first \(maxCharacters) of \(content.count) characters. The recommended write ceiling for new artifacts is ~25,000 characters — link workspace files instead of pasting them whole.]", true)
        }
        return (record, content, false)
    }

    nonisolated static func firstMeaningfulLine(of url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in content.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return String(t.prefix(140)) }
        }
        return nil
    }

    nonisolated static func isBinary(_ data: Data) -> Bool {
        data.prefix(8_192).contains(0)
    }

    nonisolated static func humanSize(_ bytes: Int) -> String {
        if bytes < 1_024 { return "\(bytes) B" }
        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(bytes), unit = 0
        while value >= 1_024, unit < units.count - 1 { value /= 1_024; unit += 1 }
        return String(format: "%.1f %@", value, units[unit])
    }
}

struct FileReadingArtifact: Sendable {
    var filename: String
    var title: String
    var description: String
    var kind: String
    var relativePath: String
    var modifiedAt: Date
}

struct FileReadingArtifactIndexEntry: Codable, Sendable {
    var id: UUID
    var description: String
    var kind: String
    var createdAt: Date
    var sourceMessageID: UUID?
}

enum FileReadingArtifactNaming {
    static let protectedFilename = "agent_notes.md"

    static func normalize(_ raw: String) -> String? {
        var stem = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !stem.isEmpty, !stem.contains("\0") else { return nil }
        guard !stem.contains("/"), !stem.contains("\\"), !stem.contains("..") else { return nil }
        if stem.hasSuffix(".md") { stem = String(stem.dropLast(3)) }
        else if stem.hasSuffix(".markdown") { stem = String(stem.dropLast(9)) }
        stem = stem.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
        while stem.contains("__") { stem = stem.replacingOccurrences(of: "__", with: "_") }
        stem = stem.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        guard !stem.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        guard stem.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard stem.count <= 120 else { return nil }
        return stem + ".md"
    }

    static func displayTitle(for filename: String) -> String {
        var stem = filename
        for ext in [".md", ".markdown", ".png", ".mov", ".mp4", ".jpg", ".jpeg"] where stem.lowercased().hasSuffix(ext) {
            stem = String(stem.dropLast(ext.count))
            break
        }
        let words = stem.split(separator: "_").map { part -> String in
            guard let first = part.first else { return "" }
            return String(first).uppercased() + part.dropFirst()
        }.filter { !$0.isEmpty }
        let title = words.joined(separator: " ")
        return title.isEmpty ? filename : title
    }

    static func inferredKind(for filename: String) -> String {
        var stem = filename.lowercased()
        if stem.hasSuffix(".md") { stem = String(stem.dropLast(3)) }
        if stem.contains("_plan") || stem.hasPrefix("plan_") || stem.hasSuffix("_plan") { return "execution_plan" }
        return "artifact"
    }
}

enum FileHashAlgorithm: String, CaseIterable, Sendable {
    case sha256
    case sha1
    case md5

    var hexLength: Int {
        switch self {
        case .sha256: 64
        case .sha1: 40
        case .md5: 32
        }
    }

    func digestHex(of data: Data) -> String {
        switch self {
        case .sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .sha1: Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .md5: Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    func hashFile(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        switch self {
        case .sha256:
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        case .sha1:
            var hasher = Insecure.SHA1()
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        case .md5:
            var hasher = Insecure.MD5()
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }
}
