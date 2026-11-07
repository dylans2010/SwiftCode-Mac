import Foundation
import YcodeAssistant
import YcodeIDECore

extension SwiftCodeMCPHost {
    var agenticFilesTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        return [
            tool("read_multiple_files", "Read Multiple Files",
                 "Reads the content of multiple files.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "paths": Schema.array(Schema.str, "Workspace-relative paths of the files to read, in the order to read them.")],
                                      required: ["paths"]),
                 output: Schema.output(["files": Schema.array(Schema.object(["path": Schema.str, "content": Schema.str]),
                                                               "The files read, in the order requested.")])) { h, call in
                try h.agenticFilesReadMultipleFiles(call)
            },
            tool("search_files", "Search Files",
                 "Searches for files matching a pattern in a directory.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "directory": Schema.string("Workspace-relative directory to search under."),
                                       "pattern": Schema.string("Substring the file name must contain (case-sensitive).")],
                                      required: ["directory", "pattern"]),
                 output: Schema.output(["files": Schema.array(Schema.str, "Workspace-relative paths of the matching files, sorted."),
                                        "count": Schema.int])) { h, call in
                try h.agenticFilesSearchFiles(call)
            },
            tool("find_text", "Find Text",
                 "Searches for text in a directory.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "directory": Schema.string("Workspace-relative directory to search under."),
                                       "text": Schema.string("Literal text to find (case-sensitive).")],
                                      required: ["directory", "text"]),
                 output: Schema.output(["results": Schema.str])) { h, call in
                try h.agenticFilesFindText(call)
            },
            tool("replace_text", "Replace Text",
                 "Replaces text in a file.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the file to modify."),
                                       "target": Schema.string("The exact text to replace (literal, not a regular expression)."),
                                       "replacement": Schema.string("The text to put in place of the target.")],
                                      required: ["path", "target", "replacement"]),
                 output: Schema.output(["path": Schema.str, "replacementCount": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.agenticFilesReplaceText(call)
            },
            tool("grep", "Grep",
                 "Searches for a pattern in a directory using grep.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "pattern": Schema.string("Regular expression to search for (case-sensitive)."),
                                       "directory": Schema.string("Workspace-relative directory to search under.")],
                                      required: ["pattern", "directory"]),
                 output: Schema.output(["results": Schema.str])) { h, call in
                try h.agenticFilesGrep(call)
            },
            tool("glob_search", "Glob Search",
                 "Searches for files matching a glob pattern.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "pattern": Schema.string("Glob pattern the file name must match (fnmatch, e.g. \"*.swift\").")],
                                      required: ["pattern"]),
                 output: Schema.output(["files": Schema.array(Schema.str, "Workspace-relative paths of the matching files, sorted."),
                                        "count": Schema.int])) { h, call in
                try h.agenticFilesGlobSearch(call)
            },
        ]
    }

    func agenticFilesDirectory(_ call: MCPToolCall, _ key: String, in s: WorkspaceSession) throws -> URL {
        let raw = try fileReadingRequiredString(call, key)
        let url = try resolveFileReadingPath(raw, in: s)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw MCPToolError("Directory not found: \(raw)")
        }
        guard isDir.boolValue else {
            throw MCPToolError("Not a directory: \(raw)")
        }
        return url
    }

    nonisolated static func agenticFilesRegularFiles(under root: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                             options: [.skipsHiddenFiles]) else { return [] }
        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            var isReg: AnyObject?
            try? (url as NSURL).getResourceValue(&isReg, forKey: .isRegularFileKey)
            if (isReg as? Bool) == true { files.append(url) }
        }
        return files.sorted { $0.path < $1.path }
    }

    nonisolated static func agenticFilesMatchesGlob(_ pattern: String, _ name: String) -> Bool {
        fnmatch(pattern, name, 0) == 0
    }

    func agenticFilesReadMultipleFiles(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        guard let paths = call.arguments["paths"]?.array else { throw MCPToolError("Missing required parameter: paths") }
        var files: [AnyJSON] = []
        var blocks: [String] = []
        for (index, entry) in paths.enumerated() {
            guard let raw = entry.string, !raw.isEmpty else {
                throw MCPToolError("paths[\(index)] must be a non-empty string path.")
            }
            let url = try resolveFileReadingPath(raw, in: s)
            let content: String
            do {
                content = try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw MCPToolError("Failed to read file at \(raw): \(error.localizedDescription)")
            }
            files.append(["path": .string(raw), "content": .string(content)])
            blocks.append("--- FILE: \(raw) ---\n\(content)\n\n")
        }
        return .structured(["files": .array(files)], summary: blocks.joined())
    }

    func agenticFilesSearchFiles(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let directory = try fileReadingRequiredString(call, "directory")
        let pattern = try fileReadingRequiredString(call, "pattern")
        let root = try agenticFilesDirectory(call, "directory", in: s)
        let matches = Self.agenticFilesRegularFiles(under: root)
            .filter { $0.lastPathComponent.contains(pattern) }
            .map { fileReadingRelativePath(of: $0, in: s) }
        let summary = matches.isEmpty
            ? "No files matching '\(pattern)' found in \(directory)."
            : "Found \(matches.count) file(s) matching '\(pattern)' in \(directory)."
        return .structured(["files": .strings(matches), "count": .int(matches.count)], summary: summary)
    }

    func agenticFilesFindText(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let directory = try fileReadingRequiredString(call, "directory")
        let text = try fileReadingRequiredString(call, "text")
        let root = try agenticFilesDirectory(call, "directory", in: s)
        var lines: [String] = []
        for fileURL in Self.agenticFilesRegularFiles(under: root) {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            var matching: [Int] = []
            for (index, line) in content.components(separatedBy: .newlines).enumerated() where line.contains(text) {
                matching.append(index + 1)
            }
            guard !matching.isEmpty else { continue }
            let rel = fileReadingRelativePath(of: fileURL, in: s)
            lines.append("\(rel): \(matching.map(String.init).joined(separator: ", "))")
        }
        let results = lines.joined(separator: "\n")
        let summary = results.isEmpty ? "No matches found." : "Text search results for '\(text)' in \(directory):"
        return .structured(["results": .string(results)], summary: summary)
    }

    func agenticFilesReplaceText(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "path")
        guard let target = call.arguments["target"]?.string else { throw MCPToolError("Missing required parameter: target") }
        guard let replacement = call.arguments["replacement"]?.string else { throw MCPToolError("Missing required parameter: replacement") }
        guard !target.isEmpty else { throw MCPToolError("Target must not be empty.") }
        let url = try resolveFileReadingPath(raw, in: s)
        let original: String
        do {
            original = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MCPToolError("Failed to read file at \(raw): \(error.localizedDescription)")
        }
        let count = original.components(separatedBy: target).count - 1
        guard count > 0 else {
            return .structured(["path": .string(raw), "replacementCount": .int(0)],
                               summary: "Successfully replaced text in \(raw)")
        }
        let modified = original.replacingOccurrences(of: target, with: replacement)
        let rel = fileReadingRelativePath(of: url, in: s)
        try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: original, proposed: modified,
                                   summary: "Replace text in \(rel)"), call: call, session: s)
        return .structured(["path": .string(raw), "replacementCount": .int(count)],
                           summary: "Successfully replaced text in \(raw)")
    }

    func agenticFilesGrep(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let pattern = try fileReadingRequiredString(call, "pattern")
        let directory = try fileReadingRequiredString(call, "directory")
        let root = try agenticFilesDirectory(call, "directory", in: s)
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            throw MCPToolError("Regex search failed: \(error.localizedDescription)")
        }
        var matches: [String] = []
        let fm = FileManager.default
        let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                       options: [.skipsHiddenFiles])
        var urls: [URL] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            if let size = values?.fileSize, size > 1_000_000 { continue }
            if SearchWorkspace.binaryExtensions.contains(fileURL.pathExtension.lowercased()) { continue }
            urls.append(fileURL)
        }
        for fileURL in urls.sorted(by: { $0.path < $1.path }) {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let rel = fileReadingRelativePath(of: fileURL, in: s)
            for (index, line) in content.components(separatedBy: .newlines).enumerated() {
                let range = NSRange(location: 0, length: line.utf16.count)
                if regex.firstMatch(in: line, options: [], range: range) != nil {
                    matches.append("\(rel):\(index + 1): \(line)")
                }
            }
        }
        return .structured(["results": .string(matches.joined(separator: "\n"))],
                           summary: "Grep search completed for '\(pattern)'")
    }

    func agenticFilesGlobSearch(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let pattern = try fileReadingRequiredString(call, "pattern")
        let root = Self.folder(of: s.model)
        let matches = SearchWorkspace.files(under: root)
            .filter { Self.agenticFilesMatchesGlob(pattern, $0.lastPathComponent) }
            .map { SearchWorkspace.relative($0, root: root) }
            .sorted()
        let summary = matches.isEmpty
            ? "No files matching '\(pattern)' found."
            : "Found \(matches.count) file(s) matching '\(pattern)'."
        return .structured(["files": .strings(matches), "count": .int(matches.count)], summary: summary)
    }
}
