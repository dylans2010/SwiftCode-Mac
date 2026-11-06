import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore

/// The ported Legacy core file-reading tools (Wave 1, slice B).
///
/// Behaviour source: Legacy's `AssistReadDirectoryTool`,
/// `AssistTreeViewTool`, `AssistChangeDirectoryTool` /
/// `AssistPrintWorkingDirectoryTool`, `AssistDirSizeReportTool`,
/// `AssistFileMetadataTool`, `AssistFileHeadPreviewTool` and
/// `AssistCountFileLinesTool` (Dylan's own code, ported under MIT), as
/// specified in `specs/ide/assist-tool-catalogue.md` (§§3–8, 14, 18).
/// Paths resolve with `resolveFileReadingPath` (the shared helper in
/// `SwiftCodeTools+FileReadingSupport.swift`): a leading `/` is
/// workspace-root-relative, anything else is relative to the session
/// working directory `dir_cd` sets, and `..` past the workspace root is
/// an error, never a clamp.
///
/// Legacy's structured results carry every value as a string; this port
/// uses typed JSON values (integers and booleans) the way SwiftCode's other
/// tools do (`file_read` and friends) — the keys are Legacy's verbatim.
extension SwiftCodeMCPHost {
    var fileReadingTools: [MCPTool] {
        [
            tool("dir_read", "Read Directory",
                 "Lists the contents of a directory (native ls equivalent). Returns sorted entries with directory markers, entry count, and the resolved path. Non-recursive — use tree_view for a recursive listing.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the directory to list. Use \".\" for the session working directory.")],
                                      required: ["path"]),
                 output: Schema.output(["contents": Schema.str, "count": Schema.int, "path": Schema.str])) { h, call in
                let s = try h.session(for: call)
                let raw = try h.fileReadingRequiredString(call, "path")
                let url = try h.resolveFileReadingPath(raw, in: s)
                let contents: [String]
                do {
                    contents = try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
                } catch {
                    throw MCPToolError("Failed to read directory at \(raw): \(error.localizedDescription)")
                }
                // Directory entries carry a trailing "/", as in Legacy; a
                // child that resolves outside the workspace (a symlink
                // pointing out) is listed without the marker.
                var annotated: [String] = []
                for entry in contents {
                    let child = url.appendingPathComponent(entry)
                    var isDir: ObjCBool = false
                    var isDirectory = FileManager.default.fileExists(atPath: child.path, isDirectory: &isDir) && isDir.boolValue
                    if isDirectory, (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                        isDirectory = Self.isInside(child, Self.folder(of: s.model))
                    }
                    annotated.append(isDirectory ? entry + "/" : entry)
                }
                let message = "Successfully read directory: \(raw) (\(contents.count) entries)"
                return .structured(["contents": .string(annotated.joined(separator: "\n")), "count": .int(contents.count), "path": .string(url.path)],
                                   summary: message)
            },
            tool("dir_pwd", "Print Working Directory",
                 "Reports the session working directory (native pwd equivalent).",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["path": Schema.str])) { h, call in
                let dir = h.fileReadingDirectory(in: try h.session(for: call))
                return .structured(["path": .string(dir.path)], summary: "Working directory: \(dir.path)")
            },
            tool("dir_cd", "Change Directory",
                 "Changes the session working directory (native cd equivalent). Subsequent plain relative paths resolve against it; use_terminal defaults to it when workingDirectory is omitted. Validates existence, directory-ness, and workspace containment.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Directory to change to, relative to the current directory (or workspace-root-relative with a leading '/').")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str, "previousPath": Schema.str, "contents": Schema.str, "count": Schema.int])) { h, call in
                let s = try h.session(for: call)
                let raw = try h.fileReadingRequiredString(call, "path")
                let previous = h.fileReadingDirectory(in: s)
                let target = try h.resolveFileReadingPath(raw, in: s)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir) else {
                    throw MCPToolError("Failed to change directory to \(raw): No such file or directory")
                }
                guard isDir.boolValue else {
                    throw MCPToolError("Failed to change directory to \(raw): Not a directory")
                }
                // Only set the session directory once the target is known
                // good: on failure the working directory is unchanged.
                h.currentDirectory = target
                let contents = (try? FileManager.default.contentsOfDirectory(atPath: target.path))?.sorted() ?? []
                return .structured(["path": .string(target.path), "previousPath": .string(previous.path),
                                    "contents": .string(contents.joined(separator: "\n")), "count": .int(contents.count)],
                                   summary: "Working directory changed to \(target.path)")
            },
            tool("dir_size_report", "Directory Size Report",
                 "Reports recursive disk usage per immediate subdirectory of a directory, largest first.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative directory. Default: workspace root (.)."),
                                       "limit": Schema.integer("Maximum subdirectories. Default 30, max 200.", minimum: 1)]),
                 output: Schema.output(["totalBytes": Schema.int, "entryCount": Schema.int])) { h, call in
                let s = try h.session(for: call)
                let raw = call.arguments["path"]?.string ?? "."
                let limit = max(1, min(200, call.int("limit") ?? 30))
                let url = try h.resolveFileReadingPath(raw, in: s)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                    throw MCPToolError("Not a directory: \(raw)")
                }
                let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                                              options: [.skipsHiddenFiles])) ?? []
                var rows: [(name: String, size: Int64)] = []
                for child in children {
                    let childIsDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    var size: Int64 = 0
                    if childIsDir {
                        // Recursive size of the subdirectory (hidden
                        // files skipped, as in Legacy).
                        if let enumerator = FileManager.default.enumerator(at: child, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                                                                            options: [.skipsHiddenFiles]) {
                            while let grand = enumerator.nextObject() as? URL {
                                let grandIsDir = (try? grand.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                                if !grandIsDir { size += h.fileReadingFileSize(of: grand) }
                            }
                        }
                    } else {
                        size = h.fileReadingFileSize(of: child)
                    }
                    rows.append((child.lastPathComponent + (childIsDir ? "/" : ""), size))
                }
                rows.sort { $0.size > $1.size }
                let relative = h.fileReadingRelativePath(of: url, in: s)
                var lines = ["Directory sizes under \(relative):"]
                for (name, size) in rows.prefix(limit) {
                    lines.append(String(format: "- %@ — %lld bytes (%.2f MB)", name, size, Double(size) / 1_048_576.0))
                }
                // Totals cover every immediate child, not just the shown rows.
                let total = rows.reduce(0) { $0 + $1.size }
                return .structured(["totalBytes": .int(Int(total)), "entryCount": .int(rows.count)], summary: lines.joined(separator: "\n"))
            },
            tool("file_metadata", "File Metadata",
                 "Returns size, dates, permissions, type, and directory status for a file or directory inside the workspace.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the file or directory.")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str, "fileName": Schema.str, "extension": Schema.str, "isDirectory": Schema.bool,
                                        "fileType": Schema.str, "size": Schema.int, "creationDate": Schema.str, "modificationDate": Schema.str,
                                        "permissions": Schema.str, "permissionsOctal": Schema.str])) { h, call in
                let s = try h.session(for: call)
                let raw = try h.fileReadingRequiredString(call, "path")
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw MCPToolError("Missing required parameter: path") }
                let url = try h.resolveFileReadingPath(trimmed, in: s)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                    throw MCPToolError("No file or directory at path: \(raw)")
                }
                let attributes: [FileAttributeKey: Any]
                do {
                    attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                } catch {
                    throw MCPToolError("Failed to read metadata for \(raw): \(error.localizedDescription)")
                }
                let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let creation = (attributes[.creationDate] as? Date).map { formatter.string(from: $0) } ?? ""
                let modification = (attributes[.modificationDate] as? Date).map { formatter.string(from: $0) } ?? ""
                let permissionsValue = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
                let permissionsOctal = String(permissionsValue, radix: 8)
                let fileType = (attributes[.type] as? FileAttributeType)?.rawValue ?? "unknown"
                let relative = h.fileReadingRelativePath(of: url, in: s)
                let output = """
                Metadata for \(relative):
                - File name: \(url.lastPathComponent)
                - Extension: \(url.pathExtension.isEmpty ? "(none)" : url.pathExtension)
                - Is directory: \(isDirectory.boolValue)
                - File type: \(fileType)
                - Size: \(size) bytes
                - Created: \(creation.isEmpty ? "(unknown)" : creation)
                - Modified: \(modification.isEmpty ? "(unknown)" : modification)
                - Permissions (octal): \(permissionsOctal)
                """
                return .structured(["path": .string(relative), "fileName": .string(url.lastPathComponent), "extension": .string(url.pathExtension),
                                    "isDirectory": .bool(isDirectory.boolValue), "fileType": .string(fileType), "size": .int(size),
                                    "creationDate": .string(creation), "modificationDate": .string(modification),
                                    "permissions": .string(permissionsOctal), "permissionsOctal": .string(permissionsOctal)],
                                   summary: output)
            },
            tool("file_head_preview", "File Head Preview",
                 "Previews the first N lines of a file with encoding detection. Never dumps whole files.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative file path."),
                                       "lines": Schema.integer("Lines to preview. Default 20, max 100.", minimum: 1)],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str, "encoding": Schema.str, "totalLines": Schema.int, "shownLines": Schema.int,
                                        "truncated": Schema.bool])) { h, call in
                let s = try h.session(for: call)
                let raw = try h.fileReadingRequiredString(call, "path")
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw MCPToolError("Missing required parameter: path") }
                let n = max(1, min(100, call.int("lines") ?? 20))
                let url = try h.resolveFileReadingPath(trimmed, in: s)
                guard let data = try? Data(contentsOf: url) else {
                    throw MCPToolError("Cannot read file: \(raw)")
                }
                // Encoding detection, in Legacy's order; ISO Latin-1
                // decodes any byte sequence, so this only fails for a
                // file no decoder accepts (which the fallback makes
                // unreachable in practice — kept for parity).
                var encoding = "utf-8"
                var text: String? = String(data: data, encoding: .utf8)
                if text == nil {
                    text = String(data: data, encoding: .utf16)
                    if text != nil { encoding = "utf-16" }
                }
                if text == nil {
                    text = String(data: data, encoding: .isoLatin1)
                    if text != nil { encoding = "iso-latin-1" }
                }
                guard let content = text else {
                    throw MCPToolError("File is not decodable text (likely binary): \(raw)")
                }
                // Unlike file_read, no phantom trailing line is stripped:
                // a file ending in a newline counts one extra line here.
                let allLines = content.components(separatedBy: .newlines)
                let head = allLines.prefix(n)
                let numbered = head.enumerated().map { "\($0.offset + 1): \($0.element)" }.joined(separator: "\n")
                let truncated = allLines.count > n
                let output = "Preview of \(raw) [\(encoding), \(allLines.count) total lines]:\n\(numbered)"
                    + (truncated ? "\n… [truncated: showing \(n) of \(allLines.count) lines]" : "")
                return .structured(["path": .string(raw), "encoding": .string(encoding), "totalLines": .int(allLines.count),
                                    "shownLines": .int(min(n, allLines.count)), "truncated": .bool(truncated)],
                                   summary: output)
            },
            tool("count_file_lines", "Count File Lines and Code Metrics",
                 "Calculates total lines, code lines, comment lines, and blank lines across workspace files.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to a file or directory to analyze."),
                                       "extension": Schema.string("Optional extension filter when analyzing directory (e.g. 'swift', 'm', 'h').")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str, "fileCount": Schema.int, "totalLines": Schema.int, "codeLines": Schema.int,
                                        "commentLines": Schema.int, "blankLines": Schema.int, "totalBytes": Schema.int])) { h, call in
                let s = try h.session(for: call)
                // NOTE: Legacy's handler also accepted a `targetPath`
                // alias for `path`, but it is not in Legacy's schema and
                // SwiftCode's argument validation rejects unknown arguments
                // before the handler runs, so the alias is intentionally
                // not supported here.
                guard let pathRaw = call.arguments["path"]?.string, !pathRaw.isEmpty else { throw MCPToolError("Missing required parameter: path") }
                let targetURL = try h.resolveFileReadingPath(pathRaw, in: s)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir) else {
                    throw MCPToolError("Path not found: \(pathRaw)")
                }
                let extFilter = call.arguments["extension"]?.string?.lowercased()
                var fileURLs: [URL] = []
                if isDir.boolValue {
                    let enumerator = FileManager.default.enumerator(at: targetURL, includingPropertiesForKeys: [.isRegularFileKey],
                                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants])
                    while let url = enumerator?.nextObject() as? URL {
                        if let ext = extFilter, url.pathExtension.lowercased() != ext { continue }
                        var isReg: AnyObject?
                        try? (url as NSURL).getResourceValue(&isReg, forKey: .isRegularFileKey)
                        if (isReg as? Bool) == true { fileURLs.append(url) }
                    }
                } else {
                    // A single file is analysed regardless of the filter.
                    fileURLs.append(targetURL)
                }
                var totalLines = 0, totalBlank = 0, totalComment = 0, totalCode = 0
                var totalBytes: Int64 = 0
                for fileURL in fileURLs {
                    // Files that do not decode as UTF-8 are silently
                    // skipped from the counts (but still count as files).
                    guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                    totalBytes += h.fileReadingFileSize(of: fileURL)
                    for line in content.components(separatedBy: .newlines) {
                        totalLines += 1
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty {
                            totalBlank += 1
                        } else if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") || trimmed.hasPrefix("#") {
                            totalComment += 1
                        } else {
                            totalCode += 1
                        }
                    }
                }
                let output = """
                Code Metrics for \(pathRaw) (\(fileURLs.count) file(s)):
                - Total Lines: \(totalLines)
                - Code Lines: \(totalCode)
                - Comment Lines: \(totalComment)
                - Blank Lines: \(totalBlank)
                - Total File Size: \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)) (\(totalBytes) bytes)
                """
                return .structured(["path": .string(pathRaw), "fileCount": .int(fileURLs.count), "totalLines": .int(totalLines),
                                    "codeLines": .int(totalCode), "commentLines": .int(totalComment), "blankLines": .int(totalBlank),
                                    "totalBytes": .int(Int(totalBytes))],
                                   summary: output)
            },
            tool("tree_view", "Tree View",
                 "Generates a tree-like representation of the project structure.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to render. Default: \".\" (workspace root)."),
                                       "maxDepth": Schema.integer("Maximum tree depth. Clamped to 1...10. Default: 3.", minimum: 1)]),
                 output: Schema.output(["tree": Schema.str, "path": Schema.str, "entries": Schema.int, "truncated": Schema.bool])) { h, call in
                let s = try h.session(for: call)
                var maxDepth = 3
                if let raw = call.arguments["maxDepth"] {
                    guard let parsed = h.fileReadingParseDepth(raw) else {
                        throw MCPToolError("Invalid maxDepth: must be an integer >= 1 (got '\(h.fileReadingDepthDescription(raw))').")
                    }
                    maxDepth = min(max(parsed, 1), 10)
                }
                let path = call.arguments["path"]?.string ?? "."
                let rootURL = try h.resolveFileReadingPath(path, in: s)
                var visited = Set<String>()
                var entryCount = 0
                var truncated = false
                let tree = h.fileReadingTree(at: rootURL, depth: 0, maxDepth: maxDepth, visited: &visited, entryCount: &entryCount, truncated: &truncated)
                let suffix = truncated ? "\n… [truncated at 2000 entries]" : ""
                return .structured(["tree": .string(tree + suffix), "path": .string(rootURL.path), "entries": .int(entryCount),
                                    "truncated": .bool(truncated)],
                                   summary: "Project Tree generated")
            },
        ]
    }

    // MARK: - Shared helpers for the file-reading tools

    /// A required string argument; Legacy's missing-argument message.
    func fileReadingRequiredString(_ call: MCPToolCall, _ key: String) throws -> String {
        guard let s = call.arguments[key]?.string, !s.isEmpty else { throw MCPToolError("Missing required parameter: \(key)") }
        return s
    }

    /// `"."` for the workspace root itself, else the path relative to it.
    func fileReadingRelativePath(of url: URL, in s: WorkspaceSession) -> String {
        let root = Self.folder(of: s.model)
        if url.standardizedFileURL.path == root.path { return "." }
        return relative(url.path, in: s)
    }

    /// A file's size in bytes (0 when it cannot be read), as Legacy's
    /// workspace scan reports it.
    func fileReadingFileSize(of url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Legacy `tree_view`'s depth parser: an integer (also from a whole
    /// number or an integer string) of at least 1; `nil` otherwise.
    func fileReadingParseDepth(_ value: AnyJSON) -> Int? {
        if let i = value.int, i >= 1 { return i }
        if let s = value.string, let i = Int(s.trimmingCharacters(in: .whitespaces)), i >= 1 { return i }
        return nil
    }

    /// How a bad `maxDepth` value reads in the error message: the string
    /// itself for a string, the JSON rendering otherwise.
    func fileReadingDepthDescription(_ value: AnyJSON) -> String {
        value.string ?? value.text
    }

    /// Renders the tree rooted at `url`: `📂` for the root and each
    /// directory, `📄` for files, `🔗` for symlinks (listed as leaves,
    /// never followed, so a symlink cycle cannot recurse). A directory
    /// whose canonical path was already visited renders as an
    /// already-visited marker instead of recursing. Stops at 2000
    /// entries, setting `truncated`.
    func fileReadingTree(at url: URL, depth: Int, maxDepth: Int, visited: inout Set<String>, entryCount: inout Int, truncated: inout Bool) -> String {
        guard depth <= maxDepth, !truncated else { return "" }
        let indent = String(repeating: "  ", count: depth)
        var lines = "\(indent)📂 \(url.lastPathComponent)\n"
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard !visited.contains(canonical) else {
            return lines + "\(indent)  ↩︎ [already visited: \(url.lastPathComponent)]\n"
        }
        visited.insert(canonical)
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            return lines + "\(indent)  ⚠️ Error reading directory: \(error.localizedDescription)\n"
        }
        for child in children {
            guard entryCount < 2000 else { truncated = true; break }
            entryCount += 1
            let isSymlink = (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
            if isSymlink {
                lines += "\(indent)  🔗 \(child.lastPathComponent)\n"
                continue
            }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue {
                lines += fileReadingTree(at: child, depth: depth + 1, maxDepth: maxDepth, visited: &visited, entryCount: &entryCount, truncated: &truncated)
            } else {
                lines += "\(indent)  📄 \(child.lastPathComponent)\n"
            }
        }
        return lines
    }
}
