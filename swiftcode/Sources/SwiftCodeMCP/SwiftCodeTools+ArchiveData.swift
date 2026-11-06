import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore

/// The ported Legacy archive and data tool families (Wave 5,
/// slice: Archive + Data).
///
/// Behaviour source: Legacy's `AssistZipFileTool`,
/// `AssistUnzipFileTool`, `AssistTarArchiveCreateTool`,
/// `AssistTarArchiveExtractTool`, `AssistGzipCompressTool`,
/// `AssistGzipDecompressTool` (`AssistArchiveTools.swift`),
/// `AssistBinaryPlistConverterTool`
/// (`AssistBinaryPlistConverterTool.swift`),
/// `AssistJsonValidateTool` (`AssistJsonValidateTool.swift`),
/// `AssistJSONValidatorTool` (`AssistJSONValidatorTool.swift`),
/// `AssistYAMLParserTool` (`AssistYAMLParserTool.swift`) and
/// `AssistYamlValidateTool` (`AssistYamlValidateTool.swift`) —
/// Dylan's own code, ported under MIT. See
/// `specs/ide/assist-artboards-media-tools.md` (Part B).
///
/// Conventions, following Waves 1–4:
///
/// * Schemas are Legacy's `parametersSchema` verbatim, plus the
///   `workspace` parameter every SwiftCode tool carries. Legacy's
///   parameter-name aliases (`source`, `sourcePath`,
///   `destinationPath`, `dest`, `archive`, `archivePath`) are NOT
///   supported: SwiftCode's argument validation rejects unknown
///   arguments before the handler runs (same as Waves 1–2).
/// * Structured data keeps Legacy's keys, with typed JSON values
///   (integers and booleans) the way SwiftCode's other tools do —
///   Legacy's string-only map is not reproduced. Tools whose
///   Legacy result carries no data return a plain text result.
/// * Path resolution: every tool here uses the strict
///   `resolveFileWritingPath` (trim; reject empty, NUL, a leading
///   `~` and any `..`; plain relative paths resolve against the
///   workspace root, never the session directory) — the same
///   shape as Legacy's archive resolver and the private
///   resolvers of `json_validate` / `yaml_validate`. (Legacy's
///   `json_validator_tool`, `yaml_parser_tool` and
///   `binary_plist_converter` resolved against the workspace root
///   with no confinement at all — absolute paths anywhere were
///   accepted. The port confines them to the workspace; see
///   "Deliberate deviations".) No path is ever allowed to escape
///   the workspace.
/// * Approval gating: every writing handler gates BEFORE touching
///   disk. Archive subprocesses and binary writes go through
///   `approveFileWritingChange` (the Wave 2 helper); text writes
///   (`json_validate` / `json_validator_tool` /
///   `yaml_validate` format-with-write) go through `commit()`.
///   `MCPServer.run` already refuses `writes: true` tools when
///   the server is read-only; the approval call is still
///   required. There is no Autopilot bypass.
/// * Subprocesses are fixed argument vectors, never a shell.
///   `tar` and `gzip` run `/usr/bin/tar` and `/usr/bin/gzip` on
///   both platforms, with Legacy's argv verbatim. `zip` /
///   `unzip` run Legacy's `/usr/bin/ditto` on macOS and the
///   system `zip` / `unzip` tools on Linux (see below).
///   `binary_plist_converter` does NOT shell out to `plutil`
///   (macOS-only, and absent on Linux): it round-trips through
///   `PropertyListSerialization`, which reads and writes both
///   XML and binary plists on every platform.
///
/// Deliberate deviations from Legacy, recorded here:
///
/// * `zip_file` / `unzip_file` on Linux use `/usr/bin/zip -r`
///   and `/usr/bin/unzip -q -o` instead of `/usr/bin/ditto`,
///   which does not exist on Linux. The failure messages name
///   `zip` / `unzip` instead of `ditto` on Linux. When neither
///   `zip` nor `unzip` is installed, the tool fails honestly
///   naming the missing command instead of faking an archive.
///   `ditto`'s `--sequesterRsrc` resource-fork handling has no
///   Linux equivalent and is not reproduced there.
/// * `binary_plist_converter` uses `PropertyListSerialization`
///   instead of `plutil -convert`. The observable result is the
///   same for valid plists (the file is rewritten in the target
///   format); the `format` argument is validated explicitly
///   (`xml1` / `binary1` only) instead of being passed through
///   to `plutil`, and the write is approval-gated (Legacy
///   converted in place with no gate).
/// * `json_validator_tool` and `yaml_parser_tool` gain the
///   workspace confinement Legacy lacked (see above).
/// * `json_validate`, `json_validator_tool` and `yaml_validate`
///   are registered `writes: true` (Legacy risk `safeMutation`),
///   following the Wave 2 precedent for conditional writers
///   (`batch_rename_files` dry-run, `regex_replace_in_files`
///   dry-run): a read-only server refuses even a validate-only
///   call. The write itself is additionally approval-gated.
/// * `yaml_validate`'s `format` normalizes indentation to 2
///   spaces per level exactly like Legacy; it does not reflow
///   or re-quote values, because Legacy's formatter does not
///   either.
extension SwiftCodeMCPHost {
    var archiveTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        return [
            tool("gzip_compress_file", "Gzip Compress File",
                 "Compresses a file into a .gz file using system gzip.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the source file to compress."),
                                       "destination": Schema.string("Optional workspace-relative path for output .gz file. Defaults to <path>.gz.")],
                                      required: ["path"]),
                 output: Schema.output(["destination": Schema.str, "size": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.gzipCompressFile(call)
            },
            tool("gzip_decompress_file", "Gzip Decompress File",
                 "Decompresses a .gz file into a destination file using system gzip.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the .gz file to decompress."),
                                       "destination": Schema.string("Optional workspace-relative path for decompressed file. Defaults to removing .gz suffix.")],
                                      required: ["path"]),
                 output: Schema.output(["destination": Schema.str, "size": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.gzipDecompressFile(call)
            },
            tool("tar_archive_create", "Create Tar Archive",
                 "Creates a .tar or .tar.gz archive from a directory or files using system tar.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the file or directory to archive."),
                                       "destination": Schema.string("Workspace-relative path for the resulting archive file (.tar or .tar.gz)."),
                                       "gzip": Schema.boolean("Whether to apply gzip compression (defaults to true for .tar.gz or .tgz, false for .tar).")],
                                      required: ["path", "destination"]),
                 output: Schema.output(["destination": Schema.str, "size": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.tarArchiveCreate(call)
            },
            tool("tar_archive_extract", "Extract Tar Archive",
                 "Extracts a .tar or .tar.gz archive into a destination directory using system tar.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the archive file (.tar, .tar.gz, .tgz)."),
                                       "destination": Schema.string("Workspace-relative destination directory to extract into.")],
                                      required: ["path", "destination"]),
                 output: Schema.output(["destination": Schema.str, "extractedCount": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.tarArchiveExtract(call)
            },
            tool("unzip_file", "Unzip Archive",
                 "Extracts a .zip archive into a destination directory using the macOS system archive tool.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the .zip archive to extract."),
                                       "destination": Schema.string("Workspace-relative path to the target directory to extract files into.")],
                                      required: ["path", "destination"]),
                 output: Schema.output(["destination": Schema.str, "extractedCount": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.unzipFile(call)
            },
            tool("zip_file", "Zip File or Directory",
                 "Compresses a file or directory into a .zip archive using the macOS system archive tool.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the source file or directory to compress."),
                                       "destination": Schema.string("Workspace-relative path for the resulting .zip archive.")],
                                      required: ["path", "destination"]),
                 output: Schema.output(["destination": Schema.str, "size": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.zipFile(call)
            },
        ]
    }

    var dataTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        return [
            tool("binary_plist_converter", "Binary Plist Converter",
                 "Converts property list files between XML and Binary formats using plutil.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Relative path to the .plist file."),
                                       "format": Schema.string("Target format: 'xml1' (human-readable) or 'binary1'. Defaults to 'xml1'.")],
                                      required: ["path"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.convertBinaryPlist(call)
            },
            tool("json_validate", "Validate JSON",
                 "Validates a JSON file, and optionally formats it as pretty-printed sorted-keys JSON, writing the result back only when write is true.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the JSON file."),
                                       "action": Schema.string("Action: validate or format. Default: validate."),
                                       "write": Schema.string("Pass \"true\" to write the formatted JSON back to the file on format. Default: false.")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str, "valid": Schema.bool, "written": Schema.bool]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.validateJson(call)
            },
            tool("json_validator_tool", "JSON Validator & Formatter",
                 "Validates JSON syntax, highlights line errors, and beautifies JSON configuration files.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Relative path to JSON file in workspace."),
                                       "formatInPlace": Schema.boolean("If true, reformats and writes pretty-printed JSON back to disk. Defaults to false.")],
                                      required: ["path"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.validateJsonTool(call)
            },
            tool("yaml_parser_tool", "YAML Parser & Validator",
                 "Validates structure and syntax of YAML files (workflows, project.yml, fastlane) in the workspace.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Relative path to YAML file in workspace.")],
                                      required: ["path"])) { h, call in
                try h.parseYaml(call)
            },
            tool("yaml_validate", "Validate YAML",
                 "Heuristic YAML validation (no full YAML parser): rejects tab indentation, unbalanced brackets/quotes, duplicate top-level keys, and mapping lines without a colon. Format normalizes indentation to 2 spaces per level and only writes back when write is true and validation passes.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the YAML file."),
                                       "action": Schema.string("Action: validate or format. Default: validate."),
                                       "write": Schema.string("Pass \"true\" to write the formatted YAML back to the file on format, only when validation passes. Default: false.")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str, "valid": Schema.bool, "heuristic": Schema.bool, "written": Schema.bool]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.validateYaml(call)
            },
        ]
    }

    // MARK: - Archive subprocess helpers

    /// Runs a fixed-argv subprocess off the main actor (the
    /// runner blocks on its pipes), with a 120-second timeout.
    /// `nil` when the process cannot start at all.
    func archiveRunFixed(_ executable: String, _ args: [String],
                         workingDirectory: URL? = nil) async -> TerminalFixedRun? {
        await Task.detached {
            Self.terminalRunFixed(executable, args, workingDirectory: workingDirectory, timeout: 120)
        }.value
    }

    /// Like `archiveRunFixed`, but captures stdout as raw `Data`
    /// (gzip's `-c` output is a binary payload, and decoding it
    /// as UTF-8 would corrupt it). Returns the exit code, the raw
    /// stdout bytes, stderr text, and whether the run timed out.
    nonisolated static func archiveRunCapturingData(_ executable: String, _ args: [String],
                                                    timeout: TimeInterval = 120) -> (exitCode: Int32, stdout: Data, stderr: String, timedOut: Bool)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        // stderr on its own thread: reading the two pipes one after
        // the other deadlocks when the child fills the second one
        // first (the `terminalRunFixed` shape).
        final class Box: @unchecked Sendable { var data = Data() }
        let errBox = Box()
        let group = DispatchGroup()
        group.enter()
        Thread { errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }.start()
        final class Flag: @unchecked Sendable { var value = false }
        let timedOut = Flag()
        let watchdog = DispatchWorkItem {
            if p.isRunning { timedOut.value = true; p.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        watchdog.cancel()
        return (p.terminationStatus, outData, String(decoding: errBox.data, as: UTF8.self), timedOut.value)
    }

    /// The size of a file in bytes (0 when it cannot be read).
    nonisolated static func archiveFileSize(of url: URL) -> Int {
        Int((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0)
    }

    /// The top-level item count of a directory (0 when it cannot
    /// be listed) — Legacy's `extractedCount`.
    nonisolated static func archiveTopLevelCount(of url: URL) -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.count ?? 0
    }

    /// Creates a directory (with parents) after approval, or
    /// throws the Legacy-shaped failure.
    func archiveCreateDirectory(_ url: URL, what: String) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw MCPToolError("Failed to create \(what): \(error.localizedDescription)")
        }
    }
}

// MARK: - Archive handlers

extension SwiftCodeMCPHost {
    /// `zip_file`: ditto on macOS (Legacy verbatim); the system
    /// `zip` tool on Linux, where ditto does not exist.
    func zipFile(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let sourceRaw = try fileReadingRequiredString(call, "path")
        let destRaw = try fileReadingRequiredString(call, "destination")
        guard let sourceURL = resolveFileWritingPath(sourceRaw, in: s) else {
            throw MCPToolError("Source path is outside the workspace: \(sourceRaw)")
        }
        guard let destURL = resolveFileWritingPath(destRaw, in: s) else {
            throw MCPToolError("Destination path is outside the workspace: \(destRaw)")
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MCPToolError("Source item not found at: \(sourceRaw)")
        }
        let destRel = fileReadingRelativePath(of: destURL, in: s)
        try await approveFileWritingChange(tool: call.name, path: destURL, relativePath: destRel, original: nil,
                                           summary: "Compress \(fileReadingRelativePath(of: sourceURL, in: s)) into \(destRel)", call: call)
        try archiveCreateDirectory(destURL.deletingLastPathComponent(), what: "destination directory")
#if os(macOS)
        guard let run = await archiveRunFixed("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", sourceURL.path, destURL.path]) else {
            throw MCPToolError("Failed to execute ditto compression: could not start /usr/bin/ditto")
        }
        if run.timedOut {
            throw MCPToolError("ditto zip timed out after 120 seconds.")
        }
        guard run.exitCode == 0 else {
            throw MCPToolError("ditto zip failed with code \(run.exitCode): \((run.stdout + run.stderr).trimmingCharacters(in: .whitespacesAndNewlines))")
        }
#else
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/zip") else {
            throw MCPToolError("zip_file needs the `zip` command-line tool, which is not installed on this system.")
        }
        // `zip -r` runs with the source's parent as its working
        // directory so the archive holds the item's own name, the
        // way ditto's archive does.
        guard let run = await archiveRunFixed("/usr/bin/zip",
                                              ["-r", "-q", destURL.path, sourceURL.lastPathComponent],
                                              workingDirectory: sourceURL.deletingLastPathComponent()) else {
            throw MCPToolError("Failed to execute zip compression: could not start /usr/bin/zip")
        }
        if run.timedOut {
            throw MCPToolError("zip timed out after 120 seconds.")
        }
        guard run.exitCode == 0 else {
            throw MCPToolError("zip failed with code \(run.exitCode): \((run.stdout + run.stderr).trimmingCharacters(in: .whitespacesAndNewlines))")
        }
#endif
        let size = Self.archiveFileSize(of: destURL)
        noteFileWritingChanged(destURL, in: s)
        return .structured(["destination": .string(destRaw), "size": .int(size)],
                           summary: "Successfully compressed `\(sourceRaw)` into `\(destRaw)` (\(size) bytes).")
    }

    /// `unzip_file`: ditto on macOS (Legacy verbatim); the system
    /// `unzip` tool on Linux, where ditto does not exist.
    func unzipFile(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let sourceRaw = try fileReadingRequiredString(call, "path")
        let destRaw = try fileReadingRequiredString(call, "destination")
        guard let sourceURL = resolveFileWritingPath(sourceRaw, in: s) else {
            throw MCPToolError("Source archive path is outside the workspace: \(sourceRaw)")
        }
        guard let destURL = resolveFileWritingPath(destRaw, in: s) else {
            throw MCPToolError("Destination path is outside the workspace: \(destRaw)")
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MCPToolError("Archive file not found at: \(sourceRaw)")
        }
        let destRel = fileReadingRelativePath(of: destURL, in: s)
        try await approveFileWritingChange(tool: call.name, path: destURL, relativePath: destRel, original: nil,
                                           summary: "Extract \(fileReadingRelativePath(of: sourceURL, in: s)) into \(destRel)", call: call)
        try archiveCreateDirectory(destURL, what: "destination directory")
#if os(macOS)
        guard let run = await archiveRunFixed("/usr/bin/ditto", ["-x", "-k", sourceURL.path, destURL.path]) else {
            throw MCPToolError("Failed to execute ditto extraction: could not start /usr/bin/ditto")
        }
        if run.timedOut {
            throw MCPToolError("ditto unzip timed out after 120 seconds.")
        }
        guard run.exitCode == 0 else {
            throw MCPToolError("ditto unzip failed with code \(run.exitCode): \((run.stdout + run.stderr).trimmingCharacters(in: .whitespacesAndNewlines))")
        }
#else
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/unzip") else {
            throw MCPToolError("unzip_file needs the `unzip` command-line tool, which is not installed on this system.")
        }
        guard let run = await archiveRunFixed("/usr/bin/unzip", ["-q", "-o", sourceURL.path, "-d", destURL.path]) else {
            throw MCPToolError("Failed to execute unzip extraction: could not start /usr/bin/unzip")
        }
        if run.timedOut {
            throw MCPToolError("unzip timed out after 120 seconds.")
        }
        guard run.exitCode == 0 else {
            throw MCPToolError("unzip failed with code \(run.exitCode): \((run.stdout + run.stderr).trimmingCharacters(in: .whitespacesAndNewlines))")
        }
#endif
        let count = Self.archiveTopLevelCount(of: destURL)
        noteFileWritingChanged(destURL, in: s)
        return .structured(["destination": .string(destRaw), "extractedCount": .int(count)],
                           summary: "Successfully extracted `\(sourceRaw)` into `\(destRaw)` (\(count) extracted items).")
    }

    /// `tar_archive_create`: system tar, Legacy's argv verbatim
    /// (`-czf`/`-cf` + `-C` parent + item name). The gzip flag
    /// defaults to true for `.tar.gz` / `.tgz` destinations.
    func tarArchiveCreate(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let sourceRaw = try fileReadingRequiredString(call, "path")
        let destRaw = try fileReadingRequiredString(call, "destination")
        guard let sourceURL = resolveFileWritingPath(sourceRaw, in: s) else {
            throw MCPToolError("Source path is outside the workspace: \(sourceRaw)")
        }
        guard let destURL = resolveFileWritingPath(destRaw, in: s) else {
            throw MCPToolError("Destination path is outside the workspace: \(destRaw)")
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MCPToolError("Source file/folder not found at: \(sourceRaw)")
        }
        let isGzip = call.bool("gzip") ?? (destRaw.hasSuffix(".gz") || destRaw.hasSuffix(".tgz"))
        let tarFlags = isGzip ? "-czf" : "-cf"
        let destRel = fileReadingRelativePath(of: destURL, in: s)
        try await approveFileWritingChange(tool: call.name, path: destURL, relativePath: destRel, original: nil,
                                           summary: "Create tar archive \(destRel)", call: call)
        try archiveCreateDirectory(destURL.deletingLastPathComponent(), what: "destination directory")
        guard let run = await archiveRunFixed("/usr/bin/tar",
                                              [tarFlags, destURL.path, "-C",
                                               sourceURL.deletingLastPathComponent().path, sourceURL.lastPathComponent]) else {
            throw MCPToolError("Failed to execute tar: could not start /usr/bin/tar")
        }
        if run.timedOut {
            throw MCPToolError("tar timed out after 120 seconds.")
        }
        guard run.exitCode == 0 else {
            throw MCPToolError("tar failed with code \(run.exitCode): \((run.stdout + run.stderr).trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let size = Self.archiveFileSize(of: destURL)
        noteFileWritingChanged(destURL, in: s)
        return .structured(["destination": .string(destRaw), "size": .int(size)],
                           summary: "Successfully created tar archive `\(destRaw)` (\(size) bytes).")
    }

    /// `tar_archive_extract`: system tar, Legacy's argv verbatim
    /// (`-xf` archive `-C` destination).
    func tarArchiveExtract(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let sourceRaw = try fileReadingRequiredString(call, "path")
        let destRaw = try fileReadingRequiredString(call, "destination")
        guard let sourceURL = resolveFileWritingPath(sourceRaw, in: s) else {
            throw MCPToolError("Source archive path is outside the workspace: \(sourceRaw)")
        }
        guard let destURL = resolveFileWritingPath(destRaw, in: s) else {
            throw MCPToolError("Destination path is outside the workspace: \(destRaw)")
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MCPToolError("Archive not found at: \(sourceRaw)")
        }
        let destRel = fileReadingRelativePath(of: destURL, in: s)
        try await approveFileWritingChange(tool: call.name, path: destURL, relativePath: destRel, original: nil,
                                           summary: "Extract tar archive \(fileReadingRelativePath(of: sourceURL, in: s)) into \(destRel)", call: call)
        try archiveCreateDirectory(destURL, what: "destination directory")
        guard let run = await archiveRunFixed("/usr/bin/tar", ["-xf", sourceURL.path, "-C", destURL.path]) else {
            throw MCPToolError("Failed to execute tar extraction: could not start /usr/bin/tar")
        }
        if run.timedOut {
            throw MCPToolError("tar extraction timed out after 120 seconds.")
        }
        guard run.exitCode == 0 else {
            throw MCPToolError("tar extraction failed with code \(run.exitCode): \((run.stdout + run.stderr).trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let count = Self.archiveTopLevelCount(of: destURL)
        noteFileWritingChanged(destURL, in: s)
        return .structured(["destination": .string(destRaw), "extractedCount": .int(count)],
                           summary: "Successfully extracted archive `\(sourceRaw)` into `\(destRaw)` (\(count) extracted items).")
    }

    /// `gzip_compress_file`: `gzip -c -k -f`, capturing the
    /// compressed bytes from stdout and writing them to the
    /// destination (default `<path>.gz`).
    func gzipCompressFile(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let sourceRaw = try fileReadingRequiredString(call, "path")
        guard let sourceURL = resolveFileWritingPath(sourceRaw, in: s) else {
            throw MCPToolError("Source path is outside the workspace: \(sourceRaw)")
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MCPToolError("File not found at: \(sourceRaw)")
        }
        let destRaw = call.string("destination") ?? (sourceRaw + ".gz")
        guard let destURL = resolveFileWritingPath(destRaw, in: s) else {
            throw MCPToolError("Destination path is outside the workspace: \(destRaw)")
        }
        let destRel = fileReadingRelativePath(of: destURL, in: s)
        try await approveFileWritingChange(tool: call.name, path: destURL, relativePath: destRel, original: nil,
                                           summary: "Gzip-compress \(fileReadingRelativePath(of: sourceURL, in: s)) to \(destRel)", call: call)
        guard let run = await Task.detached {
            Self.archiveRunCapturingData("/usr/bin/gzip", ["-c", "-k", "-f", sourceURL.path])
        }.value else {
            throw MCPToolError("Failed to execute gzip: could not start /usr/bin/gzip")
        }
        if run.timedOut {
            throw MCPToolError("gzip compression timed out after 120 seconds.")
        }
        guard run.exitCode == 0 else {
            throw MCPToolError("gzip compression failed: \(run.stderr)")
        }
        do {
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try run.stdout.write(to: destURL, options: .atomic)
        } catch {
            throw MCPToolError("Failed to write compressed file to `\(destRaw)`: \(error.localizedDescription)")
        }
        noteFileWritingChanged(destURL, in: s)
        return .structured(["destination": .string(destRaw), "size": .int(run.stdout.count)],
                           summary: "Successfully compressed `\(sourceRaw)` to `\(destRaw)` (\(run.stdout.count) bytes).")
    }

    /// `gzip_decompress_file`: `gzip -d -c -k -f`, capturing the
    /// decompressed bytes from stdout and writing them to the
    /// destination (default: the `.gz` suffix removed, or
    /// `<path>.decompressed` when there is none).
    func gzipDecompressFile(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let sourceRaw = try fileReadingRequiredString(call, "path")
        guard let sourceURL = resolveFileWritingPath(sourceRaw, in: s) else {
            throw MCPToolError("Source path is outside the workspace: \(sourceRaw)")
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MCPToolError("Archive file not found at: \(sourceRaw)")
        }
        let defaultDestRaw: String
        if sourceRaw.hasSuffix(".gz") {
            defaultDestRaw = String(sourceRaw.dropLast(3))
        } else {
            defaultDestRaw = sourceRaw + ".decompressed"
        }
        let destRaw = call.string("destination") ?? defaultDestRaw
        guard let destURL = resolveFileWritingPath(destRaw, in: s) else {
            throw MCPToolError("Destination path is outside the workspace: \(destRaw)")
        }
        let destRel = fileReadingRelativePath(of: destURL, in: s)
        try await approveFileWritingChange(tool: call.name, path: destURL, relativePath: destRel, original: nil,
                                           summary: "Gzip-decompress \(fileReadingRelativePath(of: sourceURL, in: s)) to \(destRel)", call: call)
        guard let run = await Task.detached {
            Self.archiveRunCapturingData("/usr/bin/gzip", ["-d", "-c", "-k", "-f", sourceURL.path])
        }.value else {
            throw MCPToolError("Failed to execute gzip decompression: could not start /usr/bin/gzip")
        }
        if run.timedOut {
            throw MCPToolError("gzip decompression timed out after 120 seconds.")
        }
        guard run.exitCode == 0 else {
            throw MCPToolError("gzip decompression failed: \(run.stderr)")
        }
        do {
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try run.stdout.write(to: destURL, options: .atomic)
        } catch {
            throw MCPToolError("Failed to write decompressed file to `\(destRaw)`: \(error.localizedDescription)")
        }
        noteFileWritingChanged(destURL, in: s)
        return .structured(["destination": .string(destRaw), "size": .int(run.stdout.count)],
                           summary: "Successfully decompressed `\(sourceRaw)` to `\(destRaw)` (\(run.stdout.count) bytes).")
    }
}

// MARK: - Data handlers

extension SwiftCodeMCPHost {
    /// `binary_plist_converter`: reads the plist (XML or binary)
    /// and rewrites it in the target format with
    /// `PropertyListSerialization` — no `plutil` subprocess, so
    /// this works on Linux too. The write is approval-gated;
    /// Legacy converted in place with no gate.
    func convertBinaryPlist(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "path")
        let format = (call.string("format") ?? "xml1").lowercased()
        guard format == "xml1" || format == "binary1" else {
            throw MCPToolError("Unsupported plist format '\(format)'. Supported formats: xml1, binary1.")
        }
        guard let url = resolveFileWritingPath(raw, in: s) else {
            throw MCPToolError("Path is outside the workspace: \(raw)")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPToolError("File not found at: \(raw)")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw MCPToolError("Failed to read plist at `\(raw)`: \(error.localizedDescription)")
        }
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw MCPToolError("Failed to read plist at `\(raw)`: \(error.localizedDescription)")
        }
        let rel = fileReadingRelativePath(of: url, in: s)
        try await approveFileWritingChange(tool: call.name, path: url, relativePath: rel, original: nil,
                                           summary: "Convert \(rel) to \(format) plist format", call: call)
        let converted: Data
        do {
            converted = try PropertyListSerialization.data(fromPropertyList: plist,
                                                           format: format == "binary1" ? .binary : .xml, options: 0)
        } catch {
            throw MCPToolError("Failed to convert plist at `\(raw)`: \(error.localizedDescription)")
        }
        do {
            try converted.write(to: url, options: .atomic)
        } catch {
            throw MCPToolError("Failed to write plist at `\(raw)`: \(error.localizedDescription)")
        }
        noteFileWritingChanged(url, in: s)
        return .text("Successfully converted `\(raw)` to \(format) format.")
    }

    /// `json_validate`: validates, and on `format` returns a
    /// pretty-printed sorted-keys preview — writing it back only
    /// when `write` is true (Legacy's `write` is the string
    /// `"true"`; a JSON boolean is accepted too).
    func validateJson(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "path")
        guard let url = resolveFileWritingPath(raw, in: s) else {
            throw MCPToolError("Refusing to access path outside the workspace: \(raw)")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw MCPToolError("JSON validation requires an existing file: \(raw)")
        }
        let action = (call.string("action") ?? "validate").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard action == "validate" || action == "format" else {
            throw MCPToolError("Invalid action '\(action)'. Allowed: validate, format.")
        }
        let shouldWrite = Self.dataBoolValue(call.arguments["write"])
        let rel = fileReadingRelativePath(of: url, in: s)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw MCPToolError("Failed to read \(rel): \(error.localizedDescription)")
        }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
        } catch {
            throw MCPToolError("Invalid JSON in \(rel): \(error.localizedDescription)")
        }
        if action == "validate" {
            return .structured(["path": .string(rel), "valid": .bool(true), "written": .bool(false)],
                               summary: "Valid JSON in \(rel).")
        }
        let formattedData: Data
        do {
            formattedData = try JSONSerialization.data(withJSONObject: parsed,
                                                       options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
        } catch {
            throw MCPToolError("Could not format JSON in \(rel): \(error.localizedDescription)")
        }
        guard let formatted = String(data: formattedData, encoding: .utf8) else {
            throw MCPToolError("Could not encode formatted JSON for \(rel) as UTF-8.")
        }
        if shouldWrite {
            try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: text(of: url),
                                       proposed: formatted, summary: "Format JSON in \(rel)"), call: call, session: s)
            return .structured(["path": .string(rel), "valid": .bool(true), "written": .bool(true), "formatted": .string(formatted)],
                               summary: "Valid JSON in \(rel). Formatted JSON written back to the file.")
        }
        return .structured(["path": .string(rel), "valid": .bool(true), "written": .bool(false), "formatted": .string(formatted)],
                           summary: "Valid JSON in \(rel). Formatted preview returned without writing.")
    }

    /// `json_validator_tool`: validates (no fragments allowed,
    /// unlike `json_validate`), reports the top-level type, and
    /// on `formatInPlace` rewrites the file pretty-printed with
    /// sorted keys.
    func validateJsonTool(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "path")
        let formatInPlace = call.bool("formatInPlace") ?? false
        guard let url = resolveFileWritingPath(raw, in: s) else {
            throw MCPToolError("Refusing to access path outside the workspace: \(raw)")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPToolError("File not found at: \(raw)")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw MCPToolError("Unable to read data from: \(raw)")
        }
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            if formatInPlace {
                let pretty = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
                guard let formatted = String(data: pretty, encoding: .utf8) else {
                    throw MCPToolError("Could not encode formatted JSON for \(raw) as UTF-8.")
                }
                let rel = fileReadingRelativePath(of: url, in: s)
                try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: text(of: url),
                                           proposed: formatted, summary: "Reformat JSON in \(rel)"), call: call, session: s)
                return .text("JSON is valid! Successfully reformatted and saved `\(raw)` with standard 2-space pretty-printing.")
            }
            return .text("✅ JSON syntax valid for `\(raw)` (\(data.count) bytes). Top-level type: \(type(of: jsonObject)).")
        } catch let error as MCPToolError {
            throw error
        } catch {
            throw MCPToolError("JSON Validation Error in `\(raw)`: \(error.localizedDescription)")
        }
    }

    /// `yaml_parser_tool`: Legacy's tab check + key listing,
    /// reported as Markdown. Read-only; no data keys.
    func parseYaml(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "path")
        let url = try resolveFileReadingPath(raw, in: s)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPToolError("File not found at: \(raw)")
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw MCPToolError("Unable to read content of: \(raw)")
        }
        var errors: [String] = []
        var keysFound: [String] = []
        for (index, line) in content.components(separatedBy: .newlines).enumerated() {
            let lineNum = index + 1
            if line.hasPrefix("\t") {
                errors.append("Line \(lineNum): Hard tab indentation detected. YAML strictly requires spaces.")
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if let colon = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                if !key.hasPrefix("-") && !key.isEmpty {
                    keysFound.append("Line \(lineNum): `\(key)`")
                }
            }
        }
        var report = "### YAML Inspection for `\(raw)`:\n\n"
        if !errors.isEmpty {
            report += "#### ❌ Syntax / Indentation Errors:\n"
            for error in errors {
                report += "- \(error)\n"
            }
            report += "\n"
        } else {
            report += "✅ Indentation check passed (no invalid tabs detected).\n\n"
        }
        report += "#### Root & Key Declarations (\(keysFound.count)):\n"
        for key in keysFound.prefix(20) {
            report += "- \(key)\n"
        }
        return .text(report)
    }

    /// `yaml_validate`: Legacy's heuristic validation (tab
    /// indentation, unbalanced brackets/quotes, duplicate
    /// top-level keys, mapping lines without a colon) and its
    /// 2-spaces-per-level formatter. Writes back only when
    /// `write` is true and validation passes. There is no full
    /// YAML parser in SwiftCode — the heuristic IS Legacy's
    /// behaviour, ported verbatim.
    func validateYaml(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "path")
        guard let url = resolveFileWritingPath(raw, in: s) else {
            throw MCPToolError("Refusing to access path outside the workspace: \(raw)")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw MCPToolError("YAML validation requires an existing file: \(raw)")
        }
        let action = (call.string("action") ?? "validate").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard action == "validate" || action == "format" else {
            throw MCPToolError("Invalid action '\(action)'. Allowed: validate, format.")
        }
        let shouldWrite = Self.dataBoolValue(call.arguments["write"])
        let rel = fileReadingRelativePath(of: url, in: s)
        let text: String
        do {
            let data = try Data(contentsOf: url)
            guard let decoded = String(data: data, encoding: .utf8) else {
                throw MCPToolError("File \(rel) is not valid UTF-8 text.")
            }
            text = decoded
        } catch let error as MCPToolError {
            throw error
        } catch {
            throw MCPToolError("Failed to read \(rel): \(error.localizedDescription)")
        }
        let errors = Self.dataValidateYAML(text)
        if !errors.isEmpty {
            throw MCPToolError("YAML validation failed (heuristic — no full YAML parser) in \(rel):\n\(errors.joined(separator: "\n"))")
        }
        if action == "validate" {
            return .structured(["path": .string(rel), "valid": .bool(true), "heuristic": .bool(true), "written": .bool(false)],
                               summary: "YAML validation passed (heuristic — no full YAML parser) in \(rel).")
        }
        let formatted = Self.dataFormatYAML(text)
        if shouldWrite {
            try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: text(of: url),
                                       proposed: formatted, summary: "Format YAML in \(rel)"), call: call, session: s)
            return .structured(["path": .string(rel), "valid": .bool(true), "heuristic": .bool(true),
                                "written": .bool(true), "formatted": .string(formatted)],
                               summary: "YAML validation passed (heuristic — no full YAML parser) in \(rel). Formatted YAML written back to the file.")
        }
        return .structured(["path": .string(rel), "valid": .bool(true), "heuristic": .bool(true),
                            "written": .bool(false), "formatted": .string(formatted)],
                           summary: "YAML validation passed (heuristic — no full YAML parser) in \(rel). Formatted preview returned without writing.")
    }

    /// Legacy's `boolValue`: a JSON boolean, or the strings
    /// `"true"` / `"1"` / `"yes"` (case-insensitive).
    nonisolated static func dataBoolValue(_ value: AnyJSON?) -> Bool {
        if let b = value?.bool { return b }
        if let s = value?.string {
            let lowered = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return lowered == "true" || lowered == "1" || lowered == "yes"
        }
        return false
    }
}

// MARK: - Legacy's YAML heuristic (ported verbatim)

extension SwiftCodeMCPHost {
    /// Legacy `AssistYamlValidateTool.validateYAML`: tab
    /// indentation, unbalanced quotes/brackets (quote-aware,
    /// comment-aware, block-scalar-aware), duplicate top-level
    /// keys, and mapping lines without a colon. Document markers
    /// (`---` / `...`) reset the top-level key set.
    nonisolated static func dataValidateYAML(_ text: String) -> [String] {
        var errors: [String] = []
        let rawLines = text.components(separatedBy: "\n")
        let lines = rawLines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var inSingle = false
        var inDouble = false
        var singleStartLine = 0
        var doubleStartLine = 0
        var bracketStack: [(char: Character, line: Int)] = []
        var blockScalarIndent: Int? = nil
        var seenTopKeys = Set<String>()

        for (index, line) in lines.enumerated() {
            let lineNo = index + 1
            let indent = line.prefix(while: { $0 == " " }).count
            let leadingRun = line.prefix(while: { $0 == " " || $0 == "\t" })
            let hasTabIndent = leadingRun.contains("\t")

            if let blockIndent = blockScalarIndent {
                let strippedForBlock = line.trimmingCharacters(in: .whitespaces)
                if strippedForBlock.isEmpty {
                    continue
                }
                if indent > blockIndent {
                    continue
                }
                blockScalarIndent = nil
            }

            if hasTabIndent {
                errors.append("Line \(lineNo): tab used for indentation (YAML requires spaces).")
            }

            let quoteOpenAtStart = inSingle || inDouble
            var cursor = line.startIndex
            var inComment = false
            while cursor < line.endIndex, !inComment {
                let ch = line[cursor]
                if inSingle {
                    if ch == "'" {
                        let next = line.index(after: cursor)
                        if next < line.endIndex, line[next] == "'" {
                            cursor = line.index(after: next)
                            continue
                        } else {
                            inSingle = false
                        }
                    }
                    cursor = line.index(after: cursor)
                    continue
                }
                if inDouble {
                    if ch == "\\" {
                        let next = line.index(after: cursor)
                        cursor = next < line.endIndex ? line.index(after: next) : line.endIndex
                        continue
                    }
                    if ch == "\"" { inDouble = false }
                    cursor = line.index(after: cursor)
                    continue
                }
                if ch == "#" {
                    let atStart = cursor == line.startIndex
                    let precededBySpace = !atStart && (line[line.index(before: cursor)] == " " || line[line.index(before: cursor)] == "\t")
                    if atStart || precededBySpace {
                        inComment = true
                        break
                    }
                    cursor = line.index(after: cursor)
                    continue
                }
                if ch == "'" {
                    inSingle = true
                    singleStartLine = lineNo
                } else if ch == "\"" {
                    inDouble = true
                    doubleStartLine = lineNo
                } else if ch == "[" || ch == "{" {
                    bracketStack.append((ch, lineNo))
                } else if ch == "]" || ch == "}" {
                    let expected: Character = (ch == "]") ? "[" : "{"
                    if let last = bracketStack.last, last.char == expected {
                        bracketStack.removeLast()
                    } else {
                        errors.append("Line \(lineNo): unbalanced closing bracket '\(ch)'.")
                    }
                }
                cursor = line.index(after: cursor)
            }

            if quoteOpenAtStart {
                continue
            }

            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty { continue }
            if stripped.hasPrefix("#") { continue }
            if stripped == "---" || stripped == "..." || stripped.hasPrefix("--- ") {
                if stripped == "---" {
                    seenTopKeys.removeAll()
                }
                continue
            }
            if stripped.hasPrefix("- ") || stripped == "-" {
                if dataIsBlockScalarHeader(stripped, isListItem: true) {
                    blockScalarIndent = indent
                }
                continue
            }

            guard let colonIndex = stripped.firstIndex(of: ":") else {
                errors.append("Line \(lineNo): expected 'key: value' mapping (no colon found) — heuristic.")
                continue
            }
            if indent == 0 {
                let rawKey = String(stripped[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let key = rawKey.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                if !key.isEmpty, !key.hasPrefix("{") && !key.hasPrefix("[") && !key.hasPrefix("?") {
                    if seenTopKeys.contains(key) {
                        errors.append("Line \(lineNo): duplicate top-level key '\(key)'.")
                    } else {
                        seenTopKeys.insert(key)
                    }
                }
            }
            if dataIsBlockScalarHeader(stripped, isListItem: false) {
                blockScalarIndent = indent
            }
        }

        if inSingle {
            errors.append("Unbalanced single quote opened at line \(singleStartLine).")
        }
        if inDouble {
            errors.append("Unbalanced double quote opened at line \(doubleStartLine).")
        }
        for unclosed in bracketStack {
            errors.append("Unbalanced opening bracket '\(unclosed.char)' opened at line \(unclosed.line).")
        }
        return errors
    }

    /// Legacy `AssistYamlValidateTool.isBlockScalarHeader`: a
    /// mapping value (or list item) starting with `|` or `>`.
    nonisolated static func dataIsBlockScalarHeader(_ stripped: String, isListItem: Bool) -> Bool {
        let content: String
        if isListItem {
            guard stripped.hasPrefix("- ") else { return false }
            content = String(stripped.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if content.hasPrefix("|") || content.hasPrefix(">") { return true }
            return false
        }
        guard let colonIndex = stripped.firstIndex(of: ":") else { return false }
        let value = String(stripped[stripped.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        guard let first = value.first, first == "|" || first == ">" else { return false }
        return true
    }

    /// Legacy `AssistYamlValidateTool.formatYAML`: re-indents to
    /// 2 spaces per level (the step is the file's smallest
    /// positive indent when it is at least 2, else 2). Block
    /// scalar bodies keep their original indentation; blank
    /// lines stay blank.
    nonisolated static func dataFormatYAML(_ text: String) -> String {
        let rawLines = text.components(separatedBy: "\n")
        let lines = rawLines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var step = 2
        var minPositive = Int.max
        for line in lines {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty { continue }
            let leading = line.prefix(while: { $0 == " " }).count
            if leading > 0, leading < minPositive {
                minPositive = leading
            }
        }
        if minPositive != Int.max, minPositive >= 2 {
            step = minPositive
        }

        var output: [String] = []
        var blockScalarIndent: Int? = nil
        for line in lines {
            let strippedFull = line.trimmingCharacters(in: .whitespaces)
            if strippedFull.isEmpty {
                output.append("")
                continue
            }
            let indent = line.prefix(while: { $0 == " " }).count
            if let blockIndent = blockScalarIndent {
                if indent > blockIndent {
                    output.append(line)
                    continue
                }
                blockScalarIndent = nil
            }
            let stripped = line.trimmingCharacters(in: .whitespaces)
            let level = step > 0 ? indent / step : 0
            let newIndent = String(repeating: " ", count: level * 2)
            output.append(newIndent + stripped)
            if stripped.hasPrefix("- ") || stripped == "-" {
                if dataIsBlockScalarHeader(stripped, isListItem: true) {
                    blockScalarIndent = indent
                }
            } else if dataIsBlockScalarHeader(stripped, isListItem: false) {
                blockScalarIndent = indent
            }
        }
        return output.joined(separator: "\n")
    }
}
