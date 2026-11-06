import Foundation
import YcodeAssistant
import YcodeIDECore

/// The ported Legacy Agentic file & search tools (Wave 8, slice A).
///
/// Behaviour source: Legacy's `ReadMultipleFilesTool`,
/// `SearchFilesTool`, `FindTextTool`, `ReplaceTextTool`, `GrepTool` and
/// `GlobSearchTool` (`SwiftCode/Tools/Agentic/`, Dylan's own code,
/// ported under MIT), as specified in
/// `specs/ide/agentic-files-draft.md`. The other 12 tools of this
/// slice are NOT registered here: 11 are already served by a
/// registered tool or an existing `MCPServer.toolAliases` entry
/// (`read_file`, `write_file`, `edit_file`, `create_file`,
/// `delete_file`, `rename_file`, `copy_file`, `move_file`,
/// `create_directory`, `delete_directory`, `tree_view`) and
/// `list_directory` is a duplicate of `dir_read` (proposed alias, see
/// the draft spec) — registering any of them again would create a
/// second tool under a name the server already serves.
///
/// Conventions, following Wave 1 (`YcodeTools+FileReading.swift`),
/// Wave 2 (`YcodeTools+FileWriting.swift`) and Wave 3
/// (`YcodeTools+Search.swift`):
///
/// * Schemas are Legacy's Agentic `schema` verbatim (the one-line
///   descriptions, the parameter names and types, the required lists),
///   plus the `workspace` parameter Wave 1 adds to every tool.
///   Legacy's Agentic tools have no parameter-name aliases, so none
///   are supported. Ycode's argument validation rejects unknown
///   arguments before the handler runs (same as Waves 1–3).
/// * Structured data keeps Legacy's keys where Legacy had them. The
///   Agentic tools return plain strings in Legacy (no data map), so
///   the structured keys here are the port's own: `files` (an array
///   of `{path, content}` objects for `read_multiple_files`, an array
///   of relative paths for `search_files` / `glob_search`),
///   `results` (the joined match lines for `find_text` / `grep`),
///   `path` + `replacementCount` for `replace_text`. Values are typed
///   JSON (integers and booleans) the way Ycode's other tools do.
/// * Paths resolve with `resolveFileReadingPath` (the shared Wave 1
///   helper): a leading `/` is workspace-root-relative, anything else
///   is relative to the session working directory `dir_cd` sets, and
///   `..` past the workspace root is an error, never a clamp. Legacy's
///   Agentic tools took raw filesystem paths with no confinement at
///   all; the port confines every path to the workspace, as every
///   other ported file tool does. Results report workspace-relative
///   paths where Legacy reported absolute ones.
/// * The five read-only tools are `readOnly: true, idempotent: true`,
///   `writes: false`. `replace_text` is `safeMutation`
///   (`readOnly: false, idempotent: true`, `writes: true`) and gates
///   through `commit()` — the full before/after text goes to review
///   before the file is written. `MCPServer.run` already refuses
///   `writes: true` tools when the server is read-only. There is no
///   Autopilot bypass.
///
/// Deliberate deviations from Legacy, recorded here:
///
/// * `read_multiple_files` reads in request order and returns in
///   request order. Legacy stored the results in a dictionary, so its
///   `--- FILE: ---` blocks came out in nondeterministic order; no
///   caller could depend on that order, so the port is deterministic
///   instead. A file that cannot be read fails the whole call, as in
///   Legacy (its `run` throws on the first unreadable path).
/// * `search_files` / `find_text` fail when the directory does not
///   exist (`Directory not found: <directory>`) or is not a directory
///   (`Not a directory: <directory>`). Legacy's enumerator returns
///   `nil` for a missing directory, so Legacy silently returned an
///   empty result; the port fails explicitly, matching the Wave 3
///   convention for directory-scoped tools
///   (`source_graph_builder`: `Path does not exist: …`).
/// * `find_text` is a case-sensitive literal search, exactly as
///   Legacy implements it (`line.contains(text)`), unlike
///   `search_text`, which is case-insensitive. It has no file-size
///   cap, as in Legacy; files that do not decode as UTF-8 are
///   silently skipped, as in Legacy.
/// * `grep` is implemented natively with `NSRegularExpression`,
///   case-sensitive (the `/usr/bin/grep -r -n` default), not by
///   spawning grep. Its scan mirrors the Wave 3 `search_regex` scan:
///   hidden files skipped, files over 1 MB skipped, binary-extension
///   files skipped, files that do not decode as UTF-8 skipped.
///   Legacy's grep would also report binary files ("Binary file …
///   matches") and descend into hidden directories; the port does
///   neither. An invalid pattern fails with
///   `Regex search failed: <error>`, as `search_regex` does.
/// * `glob_search` is implemented natively with `fnmatch` over the
///   workspace, not by running `/usr/bin/find . -name <pattern>`
///   from the process working directory. Legacy's `find` was scoped
///   to wherever the process happened to run and matched the file
///   name only (`-name`); the port scopes to the workspace root and
///   likewise matches the file name only — a pattern containing `/`
///   (e.g. `Sources/*.swift`) matches nothing, as with `find -name`.
///   Hidden files and the top-level skipped directories (`.git`,
///   `.build`, …) are pruned, as in the other ported search tools;
///   `find` would have walked them.
/// * `replace_text` replaces every occurrence, as in Legacy
///   (`replacingOccurrences`), and succeeds when the target is absent
///   — but unlike Legacy it does not rewrite the identical file in
///   that case (no pointless write, no pointless approval). An empty
///   target is rejected (`Target must not be empty.`): Legacy would
///   have inserted the replacement between every character. This is
///   a replace-all tool, deliberately distinct from `code_replace`,
///   which fails on a missing or multi-occurring target unless
///   `allowMultiple` is set — that is why `replace_text` is ported
///   rather than aliased to `code_replace` (an alias cannot inject
///   `allowMultiple: true`).
///
/// Wiring: the coordinator adds `agenticFilesTools` to `installTools()`
/// in `YcodeTools.swift` (this file must not edit that file). The
/// proposed alias `list_directory` → `dir_read` belongs in
/// `MCPServer.toolAliases` (also coordinator-owned).
extension YcodeMCPHost {
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

    // MARK: - Shared helpers for the Agentic files tools

    /// Resolves a `directory` argument: it must exist and be a
    /// directory. Legacy's enumerator silently returned nothing for a
    /// missing directory; the port fails explicitly (Wave 3 convention).
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

    /// Regular files under `root`, sorted by path: hidden files skipped,
    /// no skipped-directory rule and no size cap — Legacy's
    /// `FindTextTool` / `SearchFilesTool` enumerator, as written.
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

    /// `fnmatch` of a file name against a glob pattern — Legacy's
    /// `find -name` semantics: the name only, never a path.
    nonisolated static func agenticFilesMatchesGlob(_ pattern: String, _ name: String) -> Bool {
        fnmatch(pattern, name, 0) == 0
    }

    // MARK: - Handlers

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
            // Legacy's exact per-file block shape.
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
            // Files that do not decode as UTF-8 are silently skipped,
            // as in Legacy (`try? String(contentsOf:)`).
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
        // Non-overlapping literal occurrence count, matching what
        // `replacingOccurrences` will replace.
        let count = original.components(separatedBy: target).count - 1
        guard count > 0 else {
            // Legacy rewrites the identical file and reports success;
            // the port reports the same success without a pointless
            // write or approval round-trip.
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
            // Case-sensitive, as `/usr/bin/grep` is by default.
            regex = try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            throw MCPToolError("Regex search failed: \(error.localizedDescription)")
        }
        // The Wave 3 `search_regex` scan: hidden files skipped, files
        // over 1 MB skipped, binary-extension files skipped, files that
        // do not decode as UTF-8 skipped.
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
        // The ported search scan (hidden files skipped, top-level
        // skipped directories pruned); the pattern itself is matched
        // against the file name only, as `find -name` does.
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
