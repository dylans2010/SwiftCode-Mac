import Foundation

// MARK: - Shared helpers for Assist tools (artifacts-intro expansion)
//
// Dependency-free utilities shared by the single-tool files:
// workspace containment, artifact naming, display titles, formatting,
// and bounded workspace scans. This file declares no tools.

public enum AssistWorkspacePaths {
    /// Resolve a workspace-relative (or workspace-root-prefixed absolute)
    /// path to a URL, refusing anything outside the workspace root.
    public static func resolve(_ raw: String, workspaceRoot: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0"), !trimmed.hasPrefix("~"), !trimmed.contains("..") else {
            return nil
        }
        let rootPath = workspaceRoot.standardized.path
        let candidate: URL
        if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed).standardized
        } else {
            candidate = workspaceRoot.appendingPathComponent(trimmed).standardized
        }
        let candidatePath = candidate.path
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            return nil
        }
        return candidate
    }

    /// Workspace-relative display path for a resolved URL.
    public static func relative(_ url: URL, workspaceRoot: URL) -> String {
        let rootPath = workspaceRoot.standardized.path
        let path = url.standardized.path
        if path == rootPath { return "." }
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return path
    }

    public static func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}

public enum AssistArtifactNaming {
    /// Normalize a requested artifact name: trim, lowercase, convert
    /// spaces/hyphens to underscores, enforce the `.md` extension and the
    /// `^[a-z0-9_]+\.md$` shape. Returns nil for unsafe/empty names.
    public static func normalize(_ raw: String) -> String? {
        var stem = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !stem.isEmpty, !stem.contains("\0") else { return nil }
        guard !stem.contains("/") && !stem.contains("\\") && !stem.contains("..") else { return nil }
        if stem.hasSuffix(".md") {
            stem = String(stem.dropLast(3))
        } else if stem.hasSuffix(".markdown") {
            stem = String(stem.dropLast(9))
        }
        stem = stem.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        while stem.contains("__") { stem = stem.replacingOccurrences(of: "__", with: "_") }
        stem = stem.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        guard !stem.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        guard stem.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard stem.count <= 120 else { return nil }
        return stem + ".md"
    }

    /// Human-readable title for any valid snake_case artifact filename.
    /// `agent_notes.md` -> `Agent Notes`. The stored filename is untouched.
    public static func displayTitle(for filename: String) -> String {
        var stem = filename
        for ext in [".md", ".markdown", ".png", ".mov", ".mp4", ".jpg", ".jpeg"] {
            if stem.lowercased().hasSuffix(ext) {
                stem = String(stem.dropLast(ext.count))
                break
            }
        }
        let words = stem.split(separator: "_").map { part -> String in
            guard let first = part.first else { return "" }
            return String(first).uppercased() + part.dropFirst()
        }.filter { !$0.isEmpty }
        let title = words.joined(separator: " ")
        return title.isEmpty ? filename : title
    }
}

public enum AssistTextFormat {
    /// Truncate text to a maximum number of characters, marking truncation.
    public static func truncated(_ text: String, limit: Int, label: String = "truncated") -> (String, Bool) {
        guard text.count > limit else { return (text, false) }
        let prefix = String(text.prefix(limit))
        return (prefix + "\n… [\(label): showing first \(limit) of \(text.count) characters]", true)
    }

    /// Render a simple Markdown table from headers + rows.
    public static func markdownTable(headers: [String], rows: [[String]]) -> String {
        var lines: [String] = []
        lines.append("| " + headers.joined(separator: " | ") + " |")
        lines.append("| " + headers.map { _ in "---" }.joined(separator: " | ") + " |")
        for row in rows {
            let cells = (0..<headers.count).map { i in
                i < row.count ? row[i].replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") : ""
            }
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }
}

/// Bounded workspace file enumeration shared by analysis tools.
public enum AssistWorkspaceScan {
    public static let skippedDirs: Set<String> = [
        ".git", ".build", "build", "DerivedData", ".swiftpm",
        "Pods", "Carthage", "node_modules", ".venv"
    ]
    public static let sourceExts: Set<String> = ["swift", "m", "mm", "h", "c", "cpp", "hpp"]

    /// Enumerate files under root, skipping VCS/build/dependency dirs.
    public static func files(under root: URL, extensions: Set<String>? = nil, maxFiles: Int = 20000) -> [URL] {
        var results: [URL] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return results
        }
        let rootPath = root.standardized.path
        while let url = enumerator.nextObject() as? URL, results.count < maxFiles {
            let rel = url.standardized.path.replacingOccurrences(of: rootPath + "/", with: "")
            if skippedDirs.contains(rel.split(separator: "/").first.map(String.init) ?? "") { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { continue }
            if let exts = extensions, !exts.contains(url.pathExtension.lowercased()) { continue }
            results.append(url)
        }
        return results
    }

    public static func swiftFiles(under root: URL, maxFiles: Int = 8000) -> [URL] {
        files(under: root, extensions: ["swift"], maxFiles: maxFiles)
    }

    public static func readLines(_ url: URL) -> [String]? {
        (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: .newlines)
    }

    public static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    public static func fileSize(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    /// Function name declared on a `func ` line (strips generics/params).
    public static func declaredFuncName(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("func ") || t.contains(" func ") else { return nil }
        guard let r = t.range(of: "func ") else { return nil }
        let rest = String(t[r.upperBound...])
        let name = rest.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" }).first.map(String.init) ?? ""
        return name.isEmpty ? nil : name
    }

    /// Locate the first .pbxproj under the workspace root.
    public static func findPbxproj(in root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }
        return enumerator.compactMap { $0 as? URL }.first { $0.pathExtension == "pbxproj" }
    }
}
