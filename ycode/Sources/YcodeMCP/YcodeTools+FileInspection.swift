import Foundation
import YcodeAssistant
import YcodeIDECore

/// Wave 1 slice C: file inspection, diff and hashes.
///
/// Behaviour ported from Legacy's `AssistDataInspectionTools` (diff),
/// `AssistFileChecksumVerifierTool`, `AssistFileHashVerifyTool`,
/// `AssistFileTypeBreakdownTool`, `AssistFindDuplicateFilesTool`,
/// `AssistEmptyDirsFindTool`, `AssistExecutableFilesScanTool` and
/// `AssistSymlinkAuditTool` (Dylan's own code, ported under MIT): same tool
/// ids, titles, descriptions, input properties and defaults. Paths resolve
/// with the shared `resolveFileReadingPath(_:in:)` (a leading `/` is
/// workspace-root-relative, anything outside the workspace is refused) and
/// hashes use the shared swift-crypto `FileHashAlgorithm` — never
/// Legacy's CryptoKit calls or its `shasum` / `md5` subprocesses.
///
/// NOTE: this array is not wired into `installTools()` yet — that lives in
/// `YcodeTools.swift`, which this slice must not modify. The coordinator
/// adds `+ fileInspectionTools` there.
extension YcodeMCPHost {
    var fileInspectionTools: [MCPTool] {
        [
            tool("file_compare_diff", "Compare Two Files and Generate Diff",
                 "Compares two files line-by-line and produces a formatted unified diff with added/removed stats.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "pathA": Schema.string("Workspace-relative path to the first/original file."),
                                       "pathB": Schema.string("Workspace-relative path to the second/modified file.")],
                                      required: ["pathA", "pathB"]),
                 output: Schema.output(["pathA": Schema.str, "pathB": Schema.str, "identical": Schema.bool, "lineCount": Schema.int,
                                        "addedLines": Schema.int, "removedLines": Schema.int, "diff": Schema.str])) { h, call in
                guard let rawA = call.string("pathA"), let rawB = call.string("pathB") else {
                    throw MCPToolError("Missing required parameters: pathA and pathB")
                }
                let s = try h.session(for: call)
                let urlA = try h.resolveFileReadingPath(rawA, in: s)
                let urlB = try h.resolveFileReadingPath(rawB, in: s)
                guard FileManager.default.fileExists(atPath: urlA.path) else { throw MCPToolError("File A not found: \(rawA)") }
                guard FileManager.default.fileExists(atPath: urlB.path) else { throw MCPToolError("File B not found: \(rawB)") }
                let relA = h.relative(urlA.path, in: s)
                let relB = h.relative(urlB.path, in: s)
                let contentA: String
                let contentB: String
                do {
                    contentA = try String(contentsOf: urlA, encoding: .utf8)
                    contentB = try String(contentsOf: urlB, encoding: .utf8)
                } catch {
                    throw MCPToolError("Failed to read files for comparison: \(error.localizedDescription)")
                }
                // Legacy splits on `.newlines`, so a trailing newline leaves
                // a final empty element that counts as a line.
                let linesA = contentA.components(separatedBy: .newlines)
                let linesB = contentB.components(separatedBy: .newlines)
                if contentA == contentB {
                    let text = "Files `\(relA)` and `\(relB)` are identical (\(linesA.count) lines)."
                    return .structured(["pathA": .string(relA), "pathB": .string(relB), "identical": .bool(true),
                                        "lineCount": .int(linesA.count), "addedLines": .int(0), "removedLines": .int(0),
                                        "diff": .string("")],
                                       summary: text)
                }
                // Legacy's diff is positional, not a minimal (Myers/LCS)
                // diff: lines at the same index are compared, a changed
                // line counts as one removal plus one addition, and extra
                // lines at the end count on their own side.
                var diffLines: [String] = [
                    "--- a/\(relA)",
                    "+++ b/\(relB)",
                    "@@ -1,\(linesA.count) +1,\(linesB.count) @@",
                ]
                var added = 0
                var removed = 0
                for i in 0..<max(linesA.count, linesB.count) {
                    let a = i < linesA.count ? linesA[i] : nil
                    let b = i < linesB.count ? linesB[i] : nil
                    if let a, let b {
                        if a == b {
                            diffLines.append("  \(a)")
                        } else {
                            diffLines.append("- \(a)")
                            diffLines.append("+ \(b)")
                            removed += 1
                            added += 1
                        }
                    } else if let a {
                        diffLines.append("- \(a)")
                        removed += 1
                    } else if let b {
                        diffLines.append("+ \(b)")
                        added += 1
                    }
                }
                let diffText = diffLines.joined(separator: "\n")
                let text = "Unified diff for `\(relA)` vs `\(relB)` (+\(added), -\(removed) lines):\n\n\(diffText)"
                return .structured(["pathA": .string(relA), "pathB": .string(relB), "identical": .bool(false),
                                    "lineCount": .int(linesA.count), "addedLines": .int(added), "removedLines": .int(removed),
                                    "diff": .string(diffText)],
                                   summary: text)
            },
            tool("file_checksum_verifier", "File Checksum Verifier",
                 // NOTE: Legacy's description said "computes and verifies",
                 // but the tool takes no expected hash and verifies
                 // nothing — it only computes the digest. Description
                 // corrected; see specs/ide/assist-tool-catalogue.md.
                 "Computes a SHA-256, SHA-1, or MD5 cryptographic hash for a workspace file.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Relative path to file in workspace."),
                                       "algorithm": Schema.string("Hash algorithm: 'sha256', 'sha1', 'md5'. Defaults to 'sha256'.")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str, "algorithm": Schema.str, "hash": Schema.str, "size": Schema.int])) { h, call in
                guard let raw = call.string("path") else { throw MCPToolError("Missing required parameter: path") }
                let s = try h.session(for: call)
                let url = try h.resolveFileReadingPath(raw, in: s)
                guard FileManager.default.fileExists(atPath: url.path) else { throw MCPToolError("File not found at: \(raw)") }
                // Legacy's switch fell through to SHA-256 for an unknown
                // algorithm name (and still printed that name). The digest
                // behaviour is kept; the reported algorithm is the one
                // actually used.
                let requested = (call.string("algorithm") ?? "sha256").lowercased()
                let algorithm = FileHashAlgorithm(rawValue: requested) ?? .sha256
                let hash: String
                do {
                    hash = try algorithm.hashFile(at: url)
                } catch {
                    throw MCPToolError("Unable to read data from file at: \(raw)")
                }
                let size = Int(h.inspectionFileSize(of: url))
                let rel = h.relative(url.path, in: s)
                let text = "Checksum for `\(rel)`:\n- Algorithm: \(algorithm.rawValue.uppercased())\n- Digest: `\(hash)`\n- Byte Size: \(size) bytes"
                return .structured(["path": .string(rel), "algorithm": .string(algorithm.rawValue),
                                    "hash": .string(hash), "size": .int(size)],
                                   summary: text)
            },
            tool("file_hash_verify", "Verify File Hash",
                 // NOTE: Legacy hashed via the `shasum` / `md5` CLIs; the
                 // port hashes in-process with swift-crypto. Description
                 // corrected to match the implementation.
                 "Computes a file hash (SHA-256, SHA-1, or MD5) and compares it to an expected hash. A mismatch is reported as a successful comparison with match false, not as a tool error.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the file to hash."),
                                       "expectedHash": Schema.string("Expected hash in hexadecimal."),
                                       "algorithm": Schema.string("Hash algorithm: sha256, sha1, or md5. Default: sha256.")],
                                      required: ["path", "expectedHash"]),
                 output: Schema.output(["path": Schema.str, "algorithm": Schema.str, "computedHash": Schema.str,
                                        "expectedHash": Schema.str, "match": Schema.bool])) { h, call in
                guard let raw = call.string("path") else { throw MCPToolError("Missing required parameter: path") }
                guard let expectedRaw = call.string("expectedHash") else { throw MCPToolError("Missing required parameter: expectedHash") }
                let s = try h.session(for: call)
                let url = try h.resolveFileReadingPath(raw, in: s)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
                    throw MCPToolError("Hash verification requires an existing file: \(raw)")
                }
                let algorithmName = (call.arguments["algorithm"]?.string ?? "sha256")
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard let algorithm = FileHashAlgorithm(rawValue: algorithmName) else {
                    throw MCPToolError("Invalid algorithm '\(algorithmName)'. Allowed: sha256, sha1, md5.")
                }
                let expected = expectedRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard expected.count == algorithm.hexLength, expected.allSatisfy({ $0.isHexDigit }) else {
                    throw MCPToolError("Invalid expectedHash for \(algorithmName). Expected \(algorithm.hexLength) hexadecimal characters.")
                }
                let computed: String
                do {
                    computed = try algorithm.hashFile(at: url)
                } catch {
                    throw MCPToolError("Failed to compute \(algorithmName) for \(raw).")
                }
                // A mismatch is a successful comparison, not an error.
                let match = computed == expected
                let rel = h.relative(url.path, in: s)
                let text = match
                    ? "Hash match: true. \(algorithmName) of \(rel) matches the expected hash."
                    : "Hash match: false. \(algorithmName) of \(rel) is \(computed), expected \(expected)."
                return .structured(["path": .string(rel), "algorithm": .string(algorithmName), "computedHash": .string(computed),
                                    "expectedHash": .string(expected), "match": .bool(match)],
                                   summary: text)
            },
            tool("file_type_breakdown", "File Type Breakdown",
                 "Breaks down a directory by file extension: file counts and total bytes per type.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative directory. Default: workspace root (.).")]),
                 output: Schema.output(["path": Schema.str, "types": Schema.anyArray, "typeCount": Schema.int])) { h, call in
                let raw = call.string("path") ?? "."
                let s = try h.session(for: call)
                let url = try h.inspectionDirectory(raw, in: s)
                var counts: [String: Int] = [:]
                var bytes: [String: Int64] = [:]
                guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                                                                      options: [.skipsHiddenFiles]) else {
                    throw MCPToolError("Cannot enumerate directory: \(raw)")
                }
                while let child = enumerator.nextObject() as? URL {
                    let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if isDir { continue }
                    let ext = child.pathExtension.lowercased()
                    let key = ext.isEmpty ? "(no extension)" : ".\(ext)"
                    counts[key, default: 0] += 1
                    bytes[key, default: 0] += h.inspectionFileSize(of: child)
                }
                let sorted = counts.sorted { $0.value > $1.value }
                let table = fileInspectionMarkdownTable(
                    headers: ["Extension", "Files", "Bytes"],
                    rows: sorted.map { [$0.key, "\($0.value)", "\(bytes[$0.key] ?? 0)"] })
                let text = "File type breakdown for \(raw):\n\(table)"
                let types: [AnyJSON] = sorted.map { ["extension": .string($0.key), "files": .int($0.value),
                                                     "bytes": .int(Int(bytes[$0.key] ?? 0))] }
                return .structured(["path": .string(raw), "types": .array(types), "typeCount": .int(counts.count)], summary: text)
            },
            tool("find_duplicate_files", "Find Duplicate Files",
                 "Finds byte-identical duplicate files under a directory using SHA-256 content hashing.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative directory. Default: workspace root (.)."),
                                       "minSize": Schema.integer("Ignore files smaller than this many bytes. Default 1.")]),
                 output: Schema.output(["path": Schema.str, "groups": Schema.anyArray, "groupCount": Schema.int])) { h, call in
                let raw = call.string("path") ?? "."
                let minSize = max(0, call.int("minSize") ?? 1)
                let s = try h.session(for: call)
                let url = try h.inspectionDirectory(raw, in: s)
                // Group by size first so only same-size files are hashed.
                var bySize: [Int64: [URL]] = [:]
                guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                                                                      options: [.skipsHiddenFiles]) else {
                    throw MCPToolError("Cannot enumerate directory: \(raw)")
                }
                while let child = enumerator.nextObject() as? URL {
                    let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if isDir { continue }
                    let size = h.inspectionFileSize(of: child)
                    if size >= Int64(minSize) { bySize[size, default: []].append(child) }
                }
                var groups: [[String]] = []
                for (_, urls) in bySize where urls.count > 1 {
                    var byHash: [String: [URL]] = [:]
                    for u in urls {
                        if let hash = try? FileHashAlgorithm.sha256.hashFile(at: u) { byHash[hash, default: []].append(u) }
                    }
                    for (_, dupes) in byHash where dupes.count > 1 {
                        groups.append(dupes.map { h.relative($0.path, in: s) }.sorted())
                    }
                }
                groups.sort { $0.first ?? "" < $1.first ?? "" }
                if groups.isEmpty {
                    return .structured(["path": .string(raw), "groups": .array([]), "groupCount": .int(0)],
                                       summary: "No duplicate files found under \(raw).")
                }
                // Legacy shows at most 50 groups in the text; the
                // structured list carries them all.
                var lines = ["Duplicate file groups (\(groups.count)):"]
                for group in groups.prefix(50) { lines.append("- " + group.joined(separator: ", ")) }
                return .structured(["path": .string(raw), "groups": .array(groups.map { .strings($0) }),
                                    "groupCount": .int(groups.count)],
                                   summary: lines.joined(separator: "\n"))
            },
            tool("empty_dirs_find", "Find Empty Directories",
                 "Finds empty directories under a path — candidates for cleanup.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative directory. Default: workspace root (.).")]),
                 output: Schema.output(["path": Schema.str, "directories": Schema.anyArray, "count": Schema.int])) { h, call in
                let raw = call.string("path") ?? "."
                let s = try h.session(for: call)
                let url = try h.inspectionDirectory(raw, in: s)
                var empties: [String] = []
                guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                                      options: [.skipsHiddenFiles]) else {
                    throw MCPToolError("Cannot enumerate directory: \(raw)")
                }
                while let child = enumerator.nextObject() as? URL {
                    let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if !isDir { continue }
                    // Like Legacy, hidden entries count as contents here:
                    // `contentsOfDirectory` does not skip them.
                    let contents = (try? FileManager.default.contentsOfDirectory(atPath: child.path)) ?? []
                    if contents.isEmpty { empties.append(h.relative(child.path, in: s)) }
                }
                empties.sort()
                if empties.isEmpty {
                    return .structured(["path": .string(raw), "directories": .array([]), "count": .int(0)],
                                       summary: "No empty directories under \(raw).")
                }
                return .structured(["path": .string(raw), "directories": .strings(empties), "count": .int(empties.count)],
                                   summary: "Empty directories (\(empties.count)):\n" + empties.map { "- \($0)/" }.joined(separator: "\n"))
            },
            tool("executable_files_scan", "Executable Files Scan",
                 "Lists files with the executable bit set under a directory — a hygiene check for accidental +x bits in repos.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative directory. Default: workspace root (.)."),
                                       "limit": Schema.integer("Maximum results. Default 100, max 1000.")]),
                 output: Schema.output(["path": Schema.str, "files": Schema.anyArray, "count": Schema.int])) { h, call in
                let raw = call.string("path") ?? "."
                let limit = max(1, min(1000, call.int("limit") ?? 100))
                let s = try h.session(for: call)
                let url = try h.inspectionDirectory(raw, in: s)
                var hits: [String] = []
                guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                                      options: [.skipsHiddenFiles]) else {
                    throw MCPToolError("Cannot enumerate directory: \(raw)")
                }
                while let child = enumerator.nextObject() as? URL, hits.count < limit {
                    let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if isDir { continue }
                    if FileManager.default.isExecutableFile(atPath: child.path) {
                        hits.append(h.relative(child.path, in: s))
                    }
                }
                hits.sort()
                if hits.isEmpty {
                    return .structured(["path": .string(raw), "files": .array([]), "count": .int(0)],
                                       summary: "No executable files under \(raw).")
                }
                return .structured(["path": .string(raw), "files": .strings(hits), "count": .int(hits.count)],
                                   summary: "Executable files under \(raw) (\(hits.count)):\n" + hits.map { "- \($0)" }.joined(separator: "\n"))
            },
            tool("symlink_audit", "Symlink Audit",
                 "Finds symbolic links under a directory, reporting each target and flagging broken links.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative directory. Default: workspace root (.).")]),
                 output: Schema.output(["path": Schema.str, "links": Schema.anyArray, "count": Schema.int,
                                        "brokenCount": Schema.int, "escapingCount": Schema.int])) { h, call in
                let raw = call.string("path") ?? "."
                let s = try h.session(for: call)
                let url = try h.inspectionDirectory(raw, in: s)
                let root = Self.folder(of: s.model)
                var rows: [(path: String, target: String, broken: Bool, escapes: Bool)] = []
                // Legacy enumerates with no options, so hidden links are
                // included too.
                guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey],
                                                                      options: []) else {
                    throw MCPToolError("Cannot enumerate directory: \(raw)")
                }
                while let child = enumerator.nextObject() as? URL {
                    let isLink = (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
                    if !isLink { continue }
                    // Never follow a symlink during traversal (a link to a
                    // directory is a leaf, never a subtree).
                    enumerator.skipDescendants()
                    let target = (try? FileManager.default.destinationOfSymbolicLink(atPath: child.path)) ?? "(unknown)"
                    let targetURL = child.deletingLastPathComponent().appendingPathComponent(target)
                    let broken = !FileManager.default.fileExists(atPath: target.hasPrefix("/") ? target : targetURL.path)
                    let resolved = (target.hasPrefix("/") ? URL(fileURLWithPath: target) : targetURL).standardizedFileURL
                    let escapes = !Self.isInside(resolved, root)
                    rows.append((h.relative(child.path, in: s), target, broken, escapes))
                }
                rows.sort { $0.path < $1.path }
                let broken = rows.filter { $0.broken }.count
                let escaping = rows.filter { $0.escapes }.count
                if rows.isEmpty {
                    return .structured(["path": .string(raw), "links": .array([]), "count": .int(0),
                                        "brokenCount": .int(0), "escapingCount": .int(0)],
                                       summary: "No symbolic links under \(raw).")
                }
                var lines = ["Symbolic links under \(raw) (\(rows.count), \(broken) broken):"]
                lines += rows.map { "- \($0.path) -> \($0.target)\($0.broken ? " [BROKEN]" : "")\($0.escapes ? " [ESCAPES WORKSPACE]" : "")" }
                let links: [AnyJSON] = rows.map { ["path": .string($0.path), "target": .string($0.target),
                                                   "broken": .bool($0.broken), "escapesWorkspace": .bool($0.escapes)] }
                return .structured(["path": .string(raw), "links": .array(links), "count": .int(rows.count),
                                    "brokenCount": .int(broken), "escapingCount": .int(escaping)],
                                   summary: lines.joined(separator: "\n"))
            },
        ]
    }

    /// Resolves a directory argument for the scan tools: the shared path
    /// rules, plus the path must be an existing directory. Legacy reported
    /// a missing or non-directory path as "Cannot enumerate directory".
    private func inspectionDirectory(_ raw: String, in s: WorkspaceSession) throws -> URL {
        let url = try resolveFileReadingPath(raw, in: s)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw MCPToolError("Cannot enumerate directory: \(raw)")
        }
        return url
    }

    /// A file's size in bytes (0 when it cannot be read), as Legacy's
    /// `AssistWorkspaceScan.fileSize` reports it.
    private func inspectionFileSize(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }
}

/// A simple Markdown table (`| Extension | Files | Bytes |` with a `---`
/// separator row), the shape Legacy's `AssistTextFormat.markdownTable`
/// renders for `file_type_breakdown`.
private func fileInspectionMarkdownTable(headers: [String], rows: [[String]]) -> String {
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
