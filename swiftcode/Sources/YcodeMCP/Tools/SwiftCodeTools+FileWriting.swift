import Crypto
import Foundation
import YcodeAssistant
import YcodeIDECore

extension SwiftCodeMCPHost {
    var fileWritingTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        let destructive = MCPToolAnnotations(readOnly: false, destructive: true)
        return [
            tool("file_create", "Create File",
                 "Creates a new file with full content and intermediate directories when needed.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the file to create. Must be non-blank."),
                                       "content": Schema.string("File body. Default: \"\"."),
                                       "overwrite": Schema.boolean("Must be true to replace an existing file. Default: false.")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str, "bytes": Schema.int, "is_new": Schema.bool, "diff": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.createFile(call)
            },
            tool("file_append", "Append to File",
                 "Appends content to the end of a file.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the existing file to append to. The file must already exist."),
                                       "content": Schema.string("Text content to append to the end of the file.")],
                                      required: ["path", "content"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.appendFile(call)
            },
            tool("file_copy", "Copy File",
                 "Copies a file from source to destination path.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "source": Schema.string("Workspace-relative path of the existing file to copy."),
                                       "destination": Schema.string("Workspace-relative destination path.")],
                                      required: ["source", "destination"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.copyFile(call)
            },
            tool("file_move", "Move File",
                 "Moves a file from source to destination path.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "source": Schema.string("Workspace-relative path of the existing file to move."),
                                       "destination": Schema.string("Workspace-relative destination path.")],
                                      required: ["source", "destination"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.moveFile(call)
            },
            tool("file_rename", "Rename File",
                 "Renames a file at the specified path.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "oldPath": Schema.string("Workspace-relative path of the existing file."),
                                       "newName": Schema.string("New file name (a single path component) within the same directory, or a workspace-relative path to move the file (Legacy 'newPath' form).")],
                                      required: ["oldPath", "newName"]),
                 output: Schema.output(["path": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.renameFile(call)
            },
            tool("file_delete", "Delete File",
                 "Deletes a file at the specified path.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the file to delete.")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str]),
                 annotations: destructive, writes: true) { h, call in
                try await h.deleteFile(call)
            },
            tool("dir_create", "Create Directory",
                 "Creates a new directory at the specified path.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the directory to create.")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.createDirectory(call)
            },
            tool("dir_delete", "Delete Directory",
                 "Deletes a directory and all its contents.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the directory to delete.")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str]),
                 annotations: destructive, writes: true) { h, call in
                try await h.deleteDirectory(call)
            },
            tool("code_replace", "Replace in File",
                 "Replaces a specific targeted code snippet within an existing file, ensuring exact match and providing unified diffs.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("The relative path to the file to modify."),
                                       "target": Schema.string("The exact existing text snippet to find and replace."),
                                       "replacement": Schema.string("The new text snippet to insert in place of the target."),
                                       "allowMultiple": Schema.boolean("Whether to replace multiple occurrences if found (default false)."),
                                       "edits": Schema.array(Schema.anyObject, "Legacy form: array of {search, replace} edits applied sequentially to the file. Either 'edits' or 'target' + 'replacement' is required.")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str, "diff": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.replaceInFile(call)
            },
            tool("code_insert", "Insert Code Block",
                 "Inserts a block of code at a specific line or before/after a symbol.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the file to modify."),
                                       "code": Schema.string("Code block to insert."),
                                       "mode": Schema.string("One of 'line', 'before', or 'after'. Default: \"line\". Unknown modes are rejected."),
                                       "line": Schema.integer("1-based line number for 'line' mode. Appends past end of file. Default: 1.", minimum: 1),
                                       "pattern": Schema.string("Anchor text for 'before'/'after' modes. Required in those modes.")],
                                      required: ["path", "code"]),
                 output: Schema.output(["path": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.insertCode(call)
            },
            tool("code_multi_edit", "Multi-file Edit",
                 "Applies edits across multiple files simultaneously.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "edits": Schema.array(Schema.anyObject, "Array of edit objects. Each object requires a non-empty 'path', plus either 'content' (full-file replacement) or 'search' + 'replace'.")],
                                      required: ["edits"]),
                 output: Schema.output(["files": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.multiEdit(call)
            },
            tool("code_refactor", "Refactor",
                 "Performs code refactoring (e.g., extract method, rename variable) intelligently.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the file to refactor."),
                                       "action": Schema.string("Natural-language description of the refactoring to perform.")],
                                      required: ["path", "action"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.refactorCode(call)
            },
            tool("code_format", "Format Code",
                 "Formats the code according to project style guidelines.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative file or directory to format. Default: \".\".")]),
                 output: Schema.output(["formatted_files": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.formatCode(call)
            },
            tool("code_generate", "Generate File",
                 "Generates a new file with boilerplate or specific logic.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative target path. Must not already exist."),
                                       "template": Schema.string("One of: swift_struct, swift_class, swiftui_view, test (case-insensitive)."),
                                       "module": Schema.string("Module name used only by the test template for @testable import. Defaults to the user's project name.")],
                                      required: ["path", "template"]),
                 output: Schema.output(["path": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.generateFile(call)
            },
            tool("format_json_file", "Format and Validate JSON File",
                 "Validates and pretty-prints a JSON file with consistent indentation and sorted keys.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the JSON file to format.")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str, "formattedBytes": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.formatJsonFile(call)
            },
            tool("csv_to_json", "Convert CSV to JSON",
                 "Parses a tabular CSV file and converts records into a structured JSON array of objects.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the input CSV file."),
                                       "destination": Schema.string("Optional workspace-relative destination path for .json file. Defaults to <path>.json."),
                                       "delimiter": Schema.string("Delimiter character: ',' (default), '\t', or ';'.")],
                                      required: ["path"]),
                 output: Schema.output(["destination": Schema.str, "recordCount": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.csvToJson(call)
            },
            tool("json_to_csv", "Convert JSON to CSV",
                 "Converts a JSON array of objects into a standard CSV tabular file.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the input JSON file."),
                                       "destination": Schema.string("Optional workspace-relative destination path for .csv file. Defaults to <path>.csv.")],
                                      required: ["path"]),
                 output: Schema.output(["destination": Schema.str, "rowCount": Schema.int, "columnCount": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.jsonToCsv(call)
            },
            tool("plist_to_json", "Convert Plist to JSON",
                 "Converts an Apple Property List (.plist) file directly into formatted JSON format.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the .plist file."),
                                       "destination": Schema.string("Optional workspace-relative destination path for .json file. Defaults to <path>.json.")],
                                      required: ["path"]),
                 output: Schema.output(["destination": Schema.str, "size": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.plistToJson(call)
            },
            tool("json_to_plist", "Convert JSON to Plist",
                 "Converts a JSON file into an Apple Property List (.plist, XML or Binary format).",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the .json file."),
                                       "destination": Schema.string("Optional workspace-relative destination path for .plist. Defaults to <path>.plist."),
                                       "binary": Schema.boolean("Whether to encode as binary plist (default false: XML plist).")],
                                      required: ["path"]),
                 output: Schema.output(["destination": Schema.str, "format": Schema.str, "size": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.jsonToPlist(call)
            },
            tool("batch_rename_files", "Batch Rename Files",
                 "Renames multiple files in a directory matching a prefix, suffix, or substring pattern.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "directory": Schema.string("Workspace-relative directory containing the files to rename."),
                                       "search": Schema.string("Target substring or pattern in filenames to replace."),
                                       "replacement": Schema.string("String to replace the search target with."),
                                       "extension": Schema.string("Optional file extension filter (e.g. 'swift', 'png')."),
                                       "dryRun": Schema.boolean("If true, simulates the rename without modifying files. Default: false.")],
                                      required: ["directory", "search", "replacement"]),
                 output: Schema.output(["renamedCount": Schema.int, "dryRun": Schema.bool, "matchCount": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.batchRenameFiles(call)
            },
            tool("generate_file_checksum", "Generate File Cryptographic Checksum",
                 "Computes SHA-256, SHA-512, SHA-1, and MD5 cryptographic checksums of a file on disk.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the file to hash.")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str, "sha256": Schema.str, "sha512": Schema.str, "sha1": Schema.str,
                                        "md5": Schema.str, "size": Schema.int])) { h, call in
                try h.generateFileChecksum(call)
            },
            tool("plist_edit", "Edit Plist",
                 "Gets, sets, or deletes a key in a plist file using PropertyListSerialization.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the plist file (required)."),
                                       "action": Schema.string("get, set, or delete. Default: get."),
                                       "key": Schema.string("Plist key (required)."),
                                       "value": Schema.string("String value for set action.")],
                                      required: ["path", "key"]),
                 output: Schema.output(["key": Schema.str, "value": Schema.str, "path": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.editPlist(call)
            },
            tool("regex_replace_in_files", "Regex Replace in Files",
                 "Performs regular expression search and replace across multiple workspace files with dry-run support.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "pattern": Schema.string("Regular expression pattern to find."),
                                       "replacement": Schema.string("Replacement string (supports $1, $2 capturing group templates)."),
                                       "fileExtension": Schema.string("File extension filter (e.g. 'swift', 'json', 'md'). Defaults to 'swift'."),
                                       "dryRun": Schema.boolean("If true, only reports changes without writing to disk. Defaults to false.")],
                                      required: ["pattern", "replacement"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.regexReplaceInFiles(call)
            },
        ]
    }

    func resolveFileWritingPath(_ raw: String, in s: WorkspaceSession) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0"), !trimmed.hasPrefix("~"), !trimmed.contains("..") else { return nil }
        let root = Self.folder(of: s.model).standardizedFileURL
        let candidate: URL
        if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed).standardizedFileURL
        } else {
            candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        }
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return nil }
        return candidate
    }

    func resolvePlistEditPath(_ raw: String, in s: WorkspaceSession) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("..") else { return nil }
        let root = Self.folder(of: s.model).standardizedFileURL
        let candidate: URL
        if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed).standardizedFileURL
        } else {
            candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        }
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return nil }
        return candidate
    }

    func resolveFileWritingClampedPath(_ raw: String, in s: WorkspaceSession) -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = Self.folder(of: s.model).standardizedFileURL
        guard !trimmed.isEmpty, trimmed != "." else { return root }
        let candidate: URL
        if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed).standardizedFileURL
        } else {
            candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        }
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return root }
        return candidate
    }

    func approveFileWritingChange(tool: String, path: URL, relativePath: String, original: String?, summary: String, call: MCPToolCall) async throws {
        let change = MCPChange(tool: tool, path: path.path, relativePath: relativePath, original: original, proposed: "", summary: summary)
        guard await call.approve(change) else { throw MCPToolError(MCPServer.rejectedMessage) }
    }

    func noteFileWritingChanged(_ url: URL, in s: WorkspaceSession) {
        s.noteFileEdited(url.path)
        delegate?.mcpHostDidWrite(url.path)
    }

    nonisolated static func fileWritingErrorText(_ error: Error) -> String {
        (error as? MCPToolError)?.message ?? error.localizedDescription
    }

    nonisolated static func fileWritingSHA512Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA512()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func fileWritingSimpleFormat(_ content: String) -> String {
        var result: [String] = []
        var previousBlank = false
        for rawLine in content.components(separatedBy: .newlines) {
            let expanded = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let line = expanded.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank {
                if !previousBlank { result.append("") }
            } else {
                result.append(line)
            }
            previousBlank = isBlank
        }
        return result.joined(separator: "\n") + "\n"
    }

    nonisolated static func fileWritingPlistValueDescription(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let number = value as? NSNumber { return "\(number)" }
        if let array = value as? [Any] { return "array(\(array.count))" }
        if let dict = value as? [String: Any] { return "dictionary(\(dict.count))" }
        return "\(value)"
    }

    nonisolated static func fileWritingLineNumber(_ value: AnyJSON) -> Int? {
        if let i = value.int, i >= 1 { return i }
        if let s = value.string, let i = Int(s.trimmingCharacters(in: .whitespaces)), i >= 1 { return i }
        return nil
    }
}

extension SwiftCodeMCPHost {

    func createFile(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "path")
        var content = call.arguments["content"]?.string ?? ""
        let overwrite = call.bool("overwrite") ?? false
        let url = try resolveFileReadingPath(raw, in: s)
        if url.pathExtension == "swift" {
            content = NewFileComment.generateHeader(filename: url.lastPathComponent, projectName: s.model.displayName, userName: NSUserName()) + content
        }
        guard !FileManager.default.fileExists(atPath: url.path) || overwrite else {
            throw MCPToolError("File already exists at \(raw). Set overwrite=true to replace it.")
        }
        let rel = fileReadingRelativePath(of: url, in: s)
        let original = text(of: url)
        try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: original, proposed: content,
                                   summary: "Create \(rel)"), call: call, session: s)
        let lines = content.components(separatedBy: .newlines).count
        let diff = FileWritingSupport.unifiedDiff(old: original, new: content, file: rel)
        return .structured(["path": .string(raw), "bytes": .int(content.utf8.count), "is_new": .bool(true), "diff": .string(diff)],
                           summary: "Created file at \(raw) (\(lines) lines)")
    }

    func appendFile(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "path")
        guard let content = call.arguments["content"]?.string else { throw MCPToolError("Missing required parameter: content") }
        let url = try resolveFileReadingPath(raw, in: s)
        let original: String
        do {
            original = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MCPToolError("Failed to append to file at \(raw): \(error.localizedDescription)")
        }
        let rel = fileReadingRelativePath(of: url, in: s)
        try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: original, proposed: original + content,
                                   summary: "Append to \(rel)"), call: call, session: s)
        return .text("Successfully appended to file: \(raw)")
    }

    func copyFile(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let source = try fileReadingRequiredString(call, "source")
        let destination = try fileReadingRequiredString(call, "destination")
        let srcURL = try resolveFileReadingPath(source, in: s)
        let dstURL = try resolveFileReadingPath(destination, in: s)
        guard !FileManager.default.fileExists(atPath: dstURL.path) else {
            throw MCPToolError("Failed to copy file: Destination already exists: \(destination). Delete it first or choose another destination.")
        }
        let dstRel = fileReadingRelativePath(of: dstURL, in: s)
        try await approveFileWritingChange(tool: call.name, path: dstURL, relativePath: dstRel, original: nil,
                                           summary: "Copy \(fileReadingRelativePath(of: srcURL, in: s)) to \(dstRel)", call: call)
        do {
            try FileManager.default.copyItem(at: srcURL, to: dstURL)
        } catch {
            throw MCPToolError("Failed to copy file: \(error.localizedDescription)")
        }
        noteFileWritingChanged(dstURL, in: s)
        return .text("Successfully copied file from \(source) to \(destination)")
    }

    func moveFile(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let source = try fileReadingRequiredString(call, "source")
        let destination = try fileReadingRequiredString(call, "destination")
        let srcURL = try resolveFileReadingPath(source, in: s)
        let dstURL = try resolveFileReadingPath(destination, in: s)
        guard !FileManager.default.fileExists(atPath: dstURL.path) else {
            throw MCPToolError("Failed to move file: Destination already exists: \(destination). Delete it first or choose another destination.")
        }
        let dstRel = fileReadingRelativePath(of: dstURL, in: s)
        try await approveFileWritingChange(tool: call.name, path: dstURL, relativePath: dstRel, original: text(of: srcURL),
                                           summary: "Move \(fileReadingRelativePath(of: srcURL, in: s)) to \(dstRel)", call: call)
        do {
            try FileManager.default.moveItem(at: srcURL, to: dstURL)
        } catch {
            throw MCPToolError("Failed to move file: \(error.localizedDescription)")
        }
        noteFileWritingChanged(srcURL, in: s)
        noteFileWritingChanged(dstURL, in: s)
        return .text("Successfully moved file from \(source) to \(destination)")
    }

    func renameFile(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let oldPath = call.arguments["oldPath"]?.string else { throw MCPToolError("Missing required parameter: oldPath") }
        guard let newName = call.arguments["newName"]?.string else { throw MCPToolError("Missing required parameter: newName") }
        if newName.isEmpty || newName.contains("..") || newName.contains("\0") || newName == "." {
            throw MCPToolError("Invalid newName '\(newName)': must be a file name or a workspace-relative path.")
        }
        let oldURL = try resolveFileReadingPath(oldPath, in: s)
        let root = Self.folder(of: s.model)
        guard oldURL.path != root.path else {
            throw MCPToolError("Failed to rename file: Cannot rename the workspace root.")
        }
        let newURL: URL
        if newName.contains("/") {
            newURL = try resolveFileReadingPath(newName, in: s)
        } else {
            newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)
        }
        guard newURL.path != oldURL.path else {
            throw MCPToolError("Rename is a no-op: newName matches the current file name.")
        }
        let newRel = fileReadingRelativePath(of: newURL, in: s)
        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            throw MCPToolError("Failed to rename file: Destination already exists: \(newRel). Delete it first or choose another destination.")
        }
        let oldRel = fileReadingRelativePath(of: oldURL, in: s)
        try await approveFileWritingChange(tool: call.name, path: newURL, relativePath: newRel, original: text(of: oldURL),
                                           summary: "Rename \(oldRel) to \(newName)", call: call)
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            throw MCPToolError("Failed to rename file: \(error.localizedDescription)")
        }
        noteFileWritingChanged(oldURL, in: s)
        noteFileWritingChanged(newURL, in: s)
        return .structured(["path": .string(newRel)], summary: "Successfully renamed file to: \(newName)")
    }

    func deleteFile(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "path")
        let url = try resolveFileReadingPath(raw, in: s)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPToolError("No file at \(raw) — nothing to delete.")
        }
        let rel = fileReadingRelativePath(of: url, in: s)
        try await approveFileWritingChange(tool: call.name, path: url, relativePath: rel, original: text(of: url),
                                           summary: "Delete \(rel) permanently", call: call)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw MCPToolError("Failed to delete file at \(raw): \(error.localizedDescription)")
        }
        noteFileWritingChanged(url, in: s)
        return .structured(["path": .string(raw)], summary: "Successfully deleted file: \(raw)")
    }

    func createDirectory(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "path")
        let url = try resolveFileReadingPath(raw, in: s)
        var isDir: ObjCBool = false
        let rel = fileReadingRelativePath(of: url, in: s)
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return .structured(["path": .string(raw)], summary: "Successfully created directory: \(raw)")
        }
        try await approveFileWritingChange(tool: call.name, path: url, relativePath: rel, original: nil,
                                           summary: "Create directory \(rel)", call: call)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw MCPToolError("Failed to create directory at \(raw): \(error.localizedDescription)")
        }
        noteFileWritingChanged(url, in: s)
        return .structured(["path": .string(raw)], summary: "Successfully created directory: \(raw)")
    }

    func deleteDirectory(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try fileReadingRequiredString(call, "path")
        let url = try resolveFileReadingPath(raw, in: s)
        let root = Self.folder(of: s.model)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw MCPToolError("No directory at \(raw) — nothing to delete.")
        }
        guard url.path != root.path else {
            throw MCPToolError("Failed to delete directory at \(raw): Security Error: Refusing to delete the workspace root itself: \(raw)")
        }
        guard isDir.boolValue else {
            throw MCPToolError("Failed to delete directory at \(raw): No directory at \(raw) — nothing to delete.")
        }
        let rel = fileReadingRelativePath(of: url, in: s)
        try await approveFileWritingChange(tool: call.name, path: url, relativePath: rel, original: nil,
                                           summary: "Delete directory \(rel) and all its contents permanently", call: call)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw MCPToolError("Failed to delete directory at \(raw): \(error.localizedDescription)")
        }
        noteFileWritingChanged(url, in: s)
        return .structured(["path": .string(raw)], summary: "Successfully deleted directory: \(raw)")
    }
}

extension SwiftCodeMCPHost {

    func replaceInFile(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let raw = call.arguments["path"]?.string else { throw MCPToolError("Missing required parameter: 'path'") }
        let edits: [(search: String, replace: String)]
        if let editsJSON = call.arguments["edits"]?.array {
            var parsed: [(search: String, replace: String)] = []
            for (index, editJSON) in editsJSON.enumerated() {
                let edit = editJSON.object ?? [:]
                guard let search = edit["search"]?.string, !search.isEmpty else {
                    throw MCPToolError("Edit #\(index + 1) is missing a non-empty 'search'.")
                }
                parsed.append((search: search, replace: edit["replace"]?.string ?? ""))
            }
            guard !parsed.isEmpty else { throw MCPToolError("Missing required parameter: 'edits' must not be empty, or pass 'target' + 'replacement'.") }
            edits = parsed
        } else {
            guard let target = call.arguments["target"]?.string else { throw MCPToolError("Missing required parameter: 'target' (or 'edits')") }
            guard let replacement = call.arguments["replacement"]?.string else { throw MCPToolError("Missing required parameter: 'replacement' (or 'edits')") }
            edits = [(search: target, replace: replacement)]
        }
        let allowMultiple = call.bool("allowMultiple") ?? false
        if raw.contains("..") {
            throw MCPToolError("Path security error: Relative path traversal ('..') is prohibited for safety. Path: '\(raw)'")
        }
        let url = try resolveFileReadingPath(raw, in: s)
        let original: String
        do {
            original = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MCPToolError("Failed to replace in file at \(raw): \(error.localizedDescription)")
        }
        var modified = original
        for edit in edits {
            let occurrences = modified.components(separatedBy: edit.search).count - 1
            guard occurrences > 0 else {
                throw MCPToolError("Target snippet not found in '\(raw)'. Please re-read the file with 'file_read' to inspect the exact existing lines before attempting replacement. Target snippet was: '\(edit.search)'")
            }
            guard occurrences == 1 || allowMultiple else {
                throw MCPToolError("Target snippet matched \(occurrences) times in '\(raw)'. Provide more surrounding lines to uniquely identify the location, or pass 'allowMultiple: true'. Snippet was: '\(edit.search)'")
            }
            modified = modified.replacingOccurrences(of: edit.search, with: edit.replace)
        }
        let rel = fileReadingRelativePath(of: url, in: s)
        try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: original, proposed: modified,
                                   summary: "Replace in \(rel)"), call: call, session: s)
        let diff = FileWritingSupport.unifiedDiff(old: original, new: modified, file: rel)
        return .structured(["path": .string(raw), "diff": .string(diff)], summary: "Successfully updated \(raw) with targeted replacement.")
    }

    func insertCode(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let raw = call.arguments["path"]?.string else { throw MCPToolError("Missing required parameter: path") }
        guard let code = call.arguments["code"]?.string else { throw MCPToolError("Missing required parameter: code") }
        let mode = (call.arguments["mode"]?.string ?? "line").lowercased()
        guard ["line", "before", "after"].contains(mode) else {
            throw MCPToolError("Unknown mode '\(mode)': expected 'line', 'before', or 'after'.")
        }
        var pattern: String?
        if mode == "before" || mode == "after" {
            guard let p = call.arguments["pattern"]?.string, !p.isEmpty else {
                throw MCPToolError("Missing required parameter for \(mode) mode: pattern")
            }
            pattern = p
        }
        var lineNumber = 1
        if mode == "line", let rawLine = call.arguments["line"] {
            guard let parsed = Self.fileWritingLineNumber(rawLine) else {
                throw MCPToolError("Invalid line: must be an integer >= 1 (got '\(rawLine.string ?? rawLine.text)').")
            }
            lineNumber = parsed
        }
        let url = try resolveFileReadingPath(raw, in: s)
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MCPToolError("Failed to insert code into \(raw): \(error.localizedDescription)")
        }
        if let pattern {
            guard content.contains(pattern) else {
                throw MCPToolError("Pattern not found in \(raw): '\(pattern)'. No changes made.")
            }
        }
        let updated: String
        switch mode {
        case "before":
            if let range = content.range(of: pattern!) {
                var next = content
                next.insert(contentsOf: code + "\n", at: range.lowerBound)
                updated = next
            } else {
                updated = content
            }
        case "after":
            if let range = content.range(of: pattern!) {
                var next = content
                next.insert(contentsOf: "\n" + code, at: range.upperBound)
                updated = next
            } else {
                updated = content
            }
        default:
            var lines = content.components(separatedBy: .newlines)
            lines.insert(contentsOf: code.components(separatedBy: .newlines), at: min(lineNumber - 1, lines.count))
            updated = lines.joined(separator: "\n")
        }
        guard updated != content else {
            throw MCPToolError("Insert made no change to \(raw). No changes made.")
        }
        let rel = fileReadingRelativePath(of: url, in: s)
        try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: content, proposed: updated,
                                   summary: "Insert code into \(rel)"), call: call, session: s)
        return .structured(["path": .string(raw)], summary: "Code block inserted into \(raw)")
    }

    func multiEdit(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let editsJSON = call.arguments["edits"]?.array else {
            throw MCPToolError("Missing required parameter: edits (array of edit objects)")
        }
        struct ValidatedEdit { let path: String; let content: String?; let search: String?; let replace: String? }
        var validated: [ValidatedEdit] = []
        for (index, editJSON) in editsJSON.enumerated() {
            let edit = editJSON.object ?? [:]
            guard let path = edit["path"]?.string, !path.isEmpty else {
                throw MCPToolError("Edit #\(index + 1) is missing a non-empty 'path'. No edits were applied.")
            }
            if let content = edit["content"]?.string {
                validated.append(ValidatedEdit(path: path, content: content, search: nil, replace: nil))
            } else {
                guard let search = edit["search"]?.string, !search.isEmpty else {
                    throw MCPToolError("Edit #\(index + 1) for \(path) is missing a non-empty 'search'. No edits were applied.")
                }
                let replace = edit["replace"]?.string ?? ""
                validated.append(ValidatedEdit(path: path, content: nil, search: search, replace: replace))
            }
        }
        var updatedPaths: [String] = []
        for edit in validated {
            let appliedSuffix = "Edits already applied: \(updatedPaths.joined(separator: ", "))."
            let url: URL
            do {
                url = try resolveFileReadingPath(edit.path, in: s)
            } catch {
                throw MCPToolError("Failed to apply edit to \(edit.path): \(Self.fileWritingErrorText(error)). \(appliedSuffix)")
            }
            let rel = fileReadingRelativePath(of: url, in: s)
            if let content = edit.content {
                do {
                    try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: text(of: url), proposed: content,
                                               summary: "Replace \(rel)"), call: call, session: s)
                } catch let error as MCPToolError where error.message == MCPServer.rejectedMessage {
                    throw error
                } catch {
                    throw MCPToolError("Failed to apply edit to \(edit.path): \(Self.fileWritingErrorText(error)). \(appliedSuffix)")
                }
            } else {
                let original: String
                do {
                    original = try String(contentsOf: url, encoding: .utf8)
                } catch {
                    throw MCPToolError("Failed to apply edit to \(edit.path): \(error.localizedDescription). \(appliedSuffix)")
                }
                guard original.contains(edit.search!) else {
                    throw MCPToolError("Search text not found in \(edit.path). \(appliedSuffix)")
                }
                let updated = original.replacingOccurrences(of: edit.search!, with: edit.replace ?? "")
                guard updated != original else {
                    throw MCPToolError("Edit for \(edit.path) made no change. \(appliedSuffix)")
                }
                do {
                    try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: original, proposed: updated,
                                               summary: "Edit \(rel)"), call: call, session: s)
                } catch let error as MCPToolError where error.message == MCPServer.rejectedMessage {
                    throw error
                } catch {
                    throw MCPToolError("Failed to apply edit to \(edit.path): \(Self.fileWritingErrorText(error)). \(appliedSuffix)")
                }
            }
            updatedPaths.append(edit.path)
        }
        return .structured(["files": .string(updatedPaths.joined(separator: ","))],
                           summary: "Multi-file edit completed for \(updatedPaths.count) files")
    }

    func refactorCode(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let raw = call.arguments["path"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            throw MCPToolError("Missing required parameter: path")
        }
        guard let action = call.arguments["action"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !action.isEmpty else {
            throw MCPToolError("Missing required parameter: action")
        }
        let url = try resolveFileReadingPath(raw, in: s)
        guard let original = text(of: url) else {
            throw MCPToolError("Failed to read \(raw)")
        }
        let systemPrompt = """
            You are a refactoring engine. Apply the following refactoring action to the code.
            Return ONLY the modified code, no preamble.
            """
        let completion = try await llmToolComplete(systemPrompt: systemPrompt,
            userText: "Action: \(action)\nFile: \(raw)\n---\n\(original)",
            toolName: "code_refactor", failureNote: "Nothing was changed.")
        let updated = Self.llmToolStripFences(completion.text)
        guard !updated.isEmpty else {
            throw MCPToolError("code_refactor is unavailable: the LLM provider returned an empty refactoring for \(raw). Nothing was changed.")
        }
        let rel = fileReadingRelativePath(of: url, in: s)
        try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: original,
                                   proposed: updated, summary: "Refactor \(rel): \(action)"),
                         call: call, session: s)
        if updated == original {
            return .text("Refactoring '\(action)' applied to \(raw): the LLM returned the file unchanged.")
        }
        return .text("Refactoring '\(action)' applied to \(raw)")
    }

    func formatCode(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = call.arguments["path"]?.string ?? "."
        let targetURL = resolveFileWritingClampedPath(raw, in: s)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir) else {
            throw MCPToolError("Path does not exist: \(raw)")
        }
        let files: [URL]
        if isDir.boolValue {
            var found: [URL] = []
            if let enumerator = FileManager.default.enumerator(at: targetURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                                options: [.skipsHiddenFiles]) {
                while let fileURL = enumerator.nextObject() as? URL {
                    guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                          values.isRegularFile == true else { continue }
                    if let size = values.fileSize, size > 300_000 { continue }
                    guard ["swift", "m", "h", "c", "cpp", "js", "ts", "py"].contains(fileURL.pathExtension.lowercased()) else { continue }
                    found.append(fileURL)
                }
            }
            files = found
        } else {
            files = [targetURL]
        }
        var formattedCount = 0
        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let formatted = Self.fileWritingSimpleFormat(content)
            guard formatted != content else { continue }
            let rel = fileReadingRelativePath(of: file, in: s)
            try await commit(MCPChange(tool: call.name, path: file.path, relativePath: rel, original: content, proposed: formatted,
                                       summary: "Format \(rel)"), call: call, session: s)
            formattedCount += 1
        }
        return .structured(["formatted_files": .int(formattedCount)], summary: "Code formatting completed at \(raw)")
    }

    func generateFile(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let raw = call.arguments["path"]?.string else { throw MCPToolError("Missing required parameter: path") }
        guard let template = call.arguments["template"]?.string else { throw MCPToolError("Missing required parameter: template") }
        let url = try resolveFileReadingPath(raw, in: s)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw MCPToolError("Target file already exists: \(raw)")
        }
        let fileName = url.deletingPathExtension().lastPathComponent
        let moduleName = call.string("module") ?? (s.model.displayName.isEmpty ? "App" : s.model.displayName)
        let rendered: String
        switch template.lowercased() {
        case "swift_struct":
            rendered = "import Foundation\n\npublic struct \(fileName) {\n    public init() {}\n}\n"
        case "swift_class":
            rendered = "import Foundation\n\npublic final class \(fileName) {\n    public init() {}\n}\n"
        case "swiftui_view":
            rendered = "import SwiftUI\n\nstruct \(fileName): View {\n    var body: some View {\n        Text(\"\(fileName)\")\n    }\n}\n\n#Preview {\n    \(fileName)()\n}\n"
        case "test":
            rendered = "import XCTest\n@testable import \(moduleName)\n\nfinal class \(fileName): XCTestCase {\n    func testExample() {\n        XCTFail(\"Not implemented: replace with a real assertion for \(fileName).\")\n    }\n}\n"
        default:
            throw MCPToolError("Unknown template '\(template)': expected swift_struct, swift_class, swiftui_view, or test.")
        }
        let rel = fileReadingRelativePath(of: url, in: s)
        try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: nil, proposed: rendered,
                                   summary: "Generate \(rel) from template '\(template)'"), call: call, session: s)
        return .structured(["path": .string(raw)], summary: "Generated file \(raw) using template '\(template)'")
    }
}

extension SwiftCodeMCPHost {

    func formatJsonFile(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let raw = call.arguments["path"]?.string else { throw MCPToolError("Missing required parameter: path") }
        guard let fileURL = resolveFileWritingPath(raw, in: s) else {
            throw MCPToolError("Path is outside the workspace: \(raw)")
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MCPToolError("JSON file not found at: \(raw)")
        }
        let formattedData: Data
        do {
            let data = try Data(contentsOf: fileURL)
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            formattedData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
        } catch {
            throw MCPToolError("JSON formatting or validation error in `\(raw)`: \(error.localizedDescription)")
        }
        let rel = fileReadingRelativePath(of: fileURL, in: s)
        try await commit(MCPChange(tool: call.name, path: fileURL.path, relativePath: rel, original: text(of: fileURL),
                                   proposed: String(decoding: formattedData, as: UTF8.self), summary: "Format JSON \(rel)"),
                         call: call, session: s)
        return .structured(["path": .string(raw), "formattedBytes": .int(formattedData.count)],
                           summary: "Successfully formatted and validated JSON file at `\(raw)` (\(formattedData.count) bytes).")
    }

    func csvToJson(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let raw = call.arguments["path"]?.string else { throw MCPToolError("Missing required parameter: path") }
        guard let fileURL = resolveFileWritingPath(raw, in: s) else {
            throw MCPToolError("Path is outside the workspace: \(raw)")
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MCPToolError("CSV file not found at: \(raw)")
        }
        let delimiter = call.arguments["delimiter"]?.string ?? ","
        let records: [[String: String]]
        do {
            let rawString = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = rawString.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !lines.isEmpty else { throw MCPToolError("CSV file is empty.") }
            let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\""))
            let headers = lines[0].components(separatedBy: delimiter).map { $0.trimmingCharacters(in: trimSet) }
            var parsed: [[String: String]] = []
            for line in lines.dropFirst() {
                let columns = line.components(separatedBy: delimiter).map { $0.trimmingCharacters(in: trimSet) }
                var record: [String: String] = [:]
                for (idx, header) in headers.enumerated() {
                    record[header] = idx < columns.count ? columns[idx] : ""
                }
                parsed.append(record)
            }
            records = parsed
        } catch let error as MCPToolError {
            throw error
        } catch {
            throw MCPToolError("Failed to convert CSV to JSON: \(error.localizedDescription)")
        }
        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
        } catch {
            throw MCPToolError("Failed to convert CSV to JSON: \(error.localizedDescription)")
        }
        let baseName = (raw as NSString).deletingPathExtension
        let destRaw = call.arguments["destination"]?.string ?? "\(baseName).json"
        guard let destURL = resolveFileWritingPath(destRaw, in: s) else {
            throw MCPToolError("Destination path is outside the workspace: \(destRaw)")
        }
        let destRel = fileReadingRelativePath(of: destURL, in: s)
        try await commit(MCPChange(tool: call.name, path: destURL.path, relativePath: destRel, original: text(of: destURL),
                                   proposed: String(decoding: jsonData, as: UTF8.self), summary: "Convert \(raw) to JSON at \(destRel)"),
                         call: call, session: s)
        return .structured(["destination": .string(destRaw), "recordCount": .int(records.count)],
                           summary: "Successfully converted CSV `\(raw)` to JSON at `\(destRaw)` (\(records.count) records parsed).")
    }

    func jsonToCsv(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let raw = call.arguments["path"]?.string else { throw MCPToolError("Missing required parameter: path") }
        guard let fileURL = resolveFileWritingPath(raw, in: s) else {
            throw MCPToolError("Path is outside the workspace: \(raw)")
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MCPToolError("JSON file not found at: \(raw)")
        }
        let array: [[String: Any]]
        let headers: [String]
        let csvString: String
        do {
            let data = try Data(contentsOf: fileURL)
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            guard let parsed = jsonObject as? [[String: Any]], !parsed.isEmpty else {
                throw MCPToolError("JSON root must be a non-empty array of objects to convert to CSV.")
            }
            array = parsed
            var keys = Set<String>()
            for item in parsed { keys.formUnion(item.keys) }
            headers = keys.sorted()
            var lines: [String] = [headers.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",")]
            for item in parsed {
                let row = headers.map { key -> String in
                    let val = item[key] != nil ? "\(item[key]!)" : ""
                    return "\"\(val.replacingOccurrences(of: "\"", with: "\"\""))\""
                }
                lines.append(row.joined(separator: ","))
            }
            csvString = lines.joined(separator: "\n") + "\n"
        } catch let error as MCPToolError {
            throw error
        } catch {
            throw MCPToolError("Failed to convert JSON to CSV: \(error.localizedDescription)")
        }
        let baseName = (raw as NSString).deletingPathExtension
        let destRaw = call.arguments["destination"]?.string ?? "\(baseName).csv"
        guard let destURL = resolveFileWritingPath(destRaw, in: s) else {
            throw MCPToolError("Destination path is outside the workspace: \(destRaw)")
        }
        let destRel = fileReadingRelativePath(of: destURL, in: s)
        try await commit(MCPChange(tool: call.name, path: destURL.path, relativePath: destRel, original: text(of: destURL),
                                   proposed: csvString, summary: "Convert \(raw) to CSV at \(destRel)"),
                         call: call, session: s)
        return .structured(["destination": .string(destRaw), "rowCount": .int(array.count), "columnCount": .int(headers.count)],
                           summary: "Successfully converted JSON `\(raw)` to CSV at `\(destRaw)` (\(array.count) rows, \(headers.count) columns).")
    }

    func plistToJson(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let raw = call.arguments["path"]?.string else { throw MCPToolError("Missing required parameter: path") }
        guard let fileURL = resolveFileWritingPath(raw, in: s) else {
            throw MCPToolError("Path is outside the workspace: \(raw)")
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MCPToolError("Plist file not found at: \(raw)")
        }
        let jsonData: Data
        do {
            let plistData = try Data(contentsOf: fileURL)
            var format = PropertyListSerialization.PropertyListFormat.xml
            let plistObject = try PropertyListSerialization.propertyList(from: plistData, options: [], format: &format)
            jsonData = try JSONSerialization.data(withJSONObject: plistObject, options: [.prettyPrinted, .sortedKeys])
        } catch {
            throw MCPToolError("Failed to convert Plist to JSON: \(error.localizedDescription)")
        }
        let baseName = (raw as NSString).deletingPathExtension
        let destRaw = call.arguments["destination"]?.string ?? "\(baseName).json"
        guard let destURL = resolveFileWritingPath(destRaw, in: s) else {
            throw MCPToolError("Destination path is outside the workspace: \(destRaw)")
        }
        let destRel = fileReadingRelativePath(of: destURL, in: s)
        try await commit(MCPChange(tool: call.name, path: destURL.path, relativePath: destRel, original: text(of: destURL),
                                   proposed: String(decoding: jsonData, as: UTF8.self), summary: "Convert \(raw) to JSON at \(destRel)"),
                         call: call, session: s)
        return .structured(["destination": .string(destRaw), "size": .int(jsonData.count)],
                           summary: "Successfully converted Plist `\(raw)` to JSON at `\(destRaw)` (\(jsonData.count) bytes).")
    }

    func jsonToPlist(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let raw = call.arguments["path"]?.string else { throw MCPToolError("Missing required parameter: path") }
        guard let fileURL = resolveFileWritingPath(raw, in: s) else {
            throw MCPToolError("Path is outside the workspace: \(raw)")
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MCPToolError("JSON file not found at: \(raw)")
        }
        let isBinary = call.bool("binary") ?? false
        let plistData: Data
        do {
            let jsonData = try Data(contentsOf: fileURL)
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
            let format: PropertyListSerialization.PropertyListFormat = isBinary ? .binary : .xml
            plistData = try PropertyListSerialization.data(fromPropertyList: jsonObject, format: format, options: 0)
        } catch {
            throw MCPToolError("Failed to convert JSON to Plist: \(error.localizedDescription)")
        }
        let baseName = (raw as NSString).deletingPathExtension
        let destRaw = call.arguments["destination"]?.string ?? "\(baseName).plist"
        guard let destURL = resolveFileWritingPath(destRaw, in: s) else {
            throw MCPToolError("Destination path is outside the workspace: \(destRaw)")
        }
        let destRel = fileReadingRelativePath(of: destURL, in: s)
        if isBinary {
            try await approveFileWritingChange(tool: call.name, path: destURL, relativePath: destRel, original: nil,
                                               summary: "Convert \(raw) to binary plist at \(destRel)", call: call)
            do {
                try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try plistData.write(to: destURL, options: .atomic)
            } catch {
                throw MCPToolError("cannot write \(destRel): \(error.localizedDescription)")
            }
            noteFileWritingChanged(destURL, in: s)
        } else {
            try await commit(MCPChange(tool: call.name, path: destURL.path, relativePath: destRel, original: text(of: destURL),
                                       proposed: String(decoding: plistData, as: UTF8.self), summary: "Convert \(raw) to XML plist at \(destRel)"),
                             call: call, session: s)
        }
        let formatName = isBinary ? "binary" : "xml"
        return .structured(["destination": .string(destRaw), "format": .string(formatName), "size": .int(plistData.count)],
                           summary: "Successfully converted JSON `\(raw)` to Plist (\(formatName)) at `\(destRaw)` (\(plistData.count) bytes).")
    }

    func batchRenameFiles(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let dirRaw = call.arguments["directory"]?.string,
              let search = call.arguments["search"]?.string,
              let replacement = call.arguments["replacement"]?.string else {
            throw MCPToolError("Missing required parameters: directory, search, replacement")
        }
        guard let dirURL = resolveFileWritingPath(dirRaw, in: s) else {
            throw MCPToolError("Directory path is outside the workspace: \(dirRaw)")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw MCPToolError("Directory not found at: \(dirRaw)")
        }
        let extFilter = call.arguments["extension"]?.string?.lowercased()
        let isDryRun = call.bool("dryRun") ?? false
        let contents: [String]
        do {
            contents = try FileManager.default.contentsOfDirectory(atPath: dirURL.path)
        } catch {
            throw MCPToolError("Failed to batch rename files in `\(dirRaw)`: \(error.localizedDescription)")
        }
        var planned: [(from: String, to: String, oldURL: URL, newURL: URL)] = []
        for filename in contents.sorted() {
            if let ext = extFilter, (filename as NSString).pathExtension.lowercased() != ext { continue }
            if filename.contains(search) {
                let newName = filename.replacingOccurrences(of: search, with: replacement)
                if newName != filename {
                    planned.append((from: filename, to: newName, oldURL: dirURL.appendingPathComponent(filename),
                                    newURL: dirURL.appendingPathComponent(newName)))
                }
            }
        }
        guard !planned.isEmpty else {
            return .structured(["renamedCount": .int(0)],
                               summary: "No files in `\(dirRaw)` matched search pattern '\(search)'.")
        }
        if isDryRun {
            let preview = planned.map { "  • \($0.from) -> \($0.to)" }.joined(separator: "\n")
            return .structured(["dryRun": .bool(true), "matchCount": .int(planned.count)],
                               summary: "Dry run: \(planned.count) file(s) would be renamed in `\(dirRaw)`:\n\(preview)")
        }
        for item in planned {
            let oldRel = fileReadingRelativePath(of: item.oldURL, in: s)
            let newRel = fileReadingRelativePath(of: item.newURL, in: s)
            try await approveFileWritingChange(tool: call.name, path: item.newURL, relativePath: newRel, original: nil,
                                               summary: "Rename \(oldRel) to \(newRel)", call: call)
            do {
                try FileManager.default.moveItem(at: item.oldURL, to: item.newURL)
            } catch {
                throw MCPToolError("Failed to batch rename files in `\(dirRaw)`: \(error.localizedDescription)")
            }
            noteFileWritingChanged(item.oldURL, in: s)
            noteFileWritingChanged(item.newURL, in: s)
        }
        let summary = planned.map { "  • \($0.from) -> \($0.to)" }.joined(separator: "\n")
        return .structured(["renamedCount": .int(planned.count)],
                           summary: "Successfully batch-renamed \(planned.count) file(s) in `\(dirRaw)`:\n\(summary)")
    }

    func generateFileChecksum(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        guard let raw = call.arguments["path"]?.string else { throw MCPToolError("Missing required parameter: path") }
        guard let fileURL = resolveFileWritingPath(raw, in: s) else {
            throw MCPToolError("Path is outside the workspace: \(raw)")
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MCPToolError("File not found at: \(raw)")
        }
        let sha256: String, sha512: String, sha1: String, md5: String, size: Int
        do {
            sha256 = try FileHashAlgorithm.sha256.hashFile(at: fileURL)
            sha512 = try Self.fileWritingSHA512Hex(ofFileAt: fileURL)
            sha1 = try FileHashAlgorithm.sha1.hashFile(at: fileURL)
            md5 = try FileHashAlgorithm.md5.hashFile(at: fileURL)
            size = Int(fileReadingFileSize(of: fileURL))
        } catch {
            throw MCPToolError("Failed to compute file checksum: \(error.localizedDescription)")
        }
        let output = """
        Checksums for \(raw) (\(size) bytes):
        - SHA-256: \(sha256)
        - SHA-512: \(sha512)
        - SHA-1:   \(sha1)
        - MD5:     \(md5)
        """
        return .structured(["path": .string(raw), "sha256": .string(sha256), "sha512": .string(sha512), "sha1": .string(sha1),
                            "md5": .string(md5), "size": .int(size)], summary: output)
    }

    func editPlist(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let rawPath = try fileReadingRequiredString(call, "path")
        let key = try fileReadingRequiredString(call, "key")
        let action = (call.arguments["action"]?.string ?? "get").lowercased()
        guard action == "get" || action == "set" || action == "delete" else {
            throw MCPToolError("Invalid action '\(action)': must be get, set, or delete.")
        }
        var value = ""
        if action == "set" {
            guard let v = call.arguments["value"]?.string else {
                throw MCPToolError("Missing required parameter: value for set action.")
            }
            value = v
        }
        guard let fileURL = resolvePlistEditPath(rawPath, in: s) else {
            throw MCPToolError("Invalid path '\(rawPath)': must be inside the workspace and must not contain '..'.")
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MCPToolError("Plist file not found at '\(rawPath)'.")
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            throw MCPToolError("Failed to read plist at '\(rawPath)'.")
        }
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format),
              var dict = plist as? [String: Any] else {
            throw MCPToolError("Plist at '\(rawPath)' is not a dictionary plist. Key-based edit requires a top-level dictionary.")
        }
        let rel = fileReadingRelativePath(of: fileURL, in: s)
        if action == "get" {
            guard let found = dict[key] else {
                throw MCPToolError("Key '\(key)' not found in '\(rawPath)'.")
            }
            let described = Self.fileWritingPlistValueDescription(found)
            return .structured(["key": .string(key), "value": .string(described), "path": .string(rawPath)],
                               summary: "Key '\(key)' = \(described) in '\(rawPath)'.")
        }
        if action == "set" {
            dict[key] = value
            let out: Data
            do {
                out = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            } catch {
                throw MCPToolError("Failed to write plist: \(error.localizedDescription)")
            }
            try await commit(MCPChange(tool: call.name, path: fileURL.path, relativePath: rel, original: text(of: fileURL),
                                       proposed: String(decoding: out, as: UTF8.self), summary: "Set '\(key)' in \(rel)"),
                             call: call, session: s)
            guard let verifyData = try? Data(contentsOf: fileURL),
                  let verifyPlist = try? PropertyListSerialization.propertyList(from: verifyData, options: [], format: &format),
                  let verifyDict = verifyPlist as? [String: Any],
                  let verifyValue = verifyDict[key] as? String, verifyValue == value else {
                throw MCPToolError("Verification failed: key not present after write.")
            }
            return .structured(["key": .string(key), "value": .string(value), "path": .string(rawPath)],
                               summary: "Set key '\(key)' in '\(rawPath)'.")
        }
        guard dict[key] != nil else {
            throw MCPToolError("Key '\(key)' not found in '\(rawPath)'.")
        }
        dict.removeValue(forKey: key)
        let out: Data
        do {
            out = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        } catch {
            throw MCPToolError("Failed to write plist: \(error.localizedDescription)")
        }
        try await commit(MCPChange(tool: call.name, path: fileURL.path, relativePath: rel, original: text(of: fileURL),
                                   proposed: String(decoding: out, as: UTF8.self), summary: "Delete '\(key)' from \(rel)"),
                         call: call, session: s)
        guard let verifyData = try? Data(contentsOf: fileURL),
              let verifyPlist = try? PropertyListSerialization.propertyList(from: verifyData, options: [], format: &format),
              let verifyDict = verifyPlist as? [String: Any],
              verifyDict[key] == nil else {
            throw MCPToolError("Verification failed: key still present after delete.")
        }
        return .structured(["key": .string(key), "path": .string(rawPath)],
                           summary: "Deleted key '\(key)' from '\(rawPath)'.")
    }

    func regexReplaceInFiles(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let pattern = call.arguments["pattern"]?.string else { throw MCPToolError("Missing required parameter: pattern") }
        guard let replacement = call.arguments["replacement"]?.string else { throw MCPToolError("Missing required parameter: replacement") }
        let ext = call.arguments["fileExtension"]?.string ?? "swift"
        let dryRun = call.bool("dryRun") ?? false
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            throw MCPToolError("Invalid regular expression pattern: \(pattern)")
        }
        let root = Self.folder(of: s.model)
        var modifiedFiles: [String] = []
        var totalReplacements = 0
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == ext else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let nsString = content as NSString
            let range = NSRange(location: 0, length: nsString.length)
            let matches = regex.matches(in: content, options: [], range: range)
            guard !matches.isEmpty else { continue }
            let replaced = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: replacement)
            let rel = fileReadingRelativePath(of: fileURL, in: s)
            modifiedFiles.append("`\(rel)` (\(matches.count) matches)")
            totalReplacements += matches.count
            if !dryRun {
                do {
                    try await commit(MCPChange(tool: call.name, path: fileURL.path, relativePath: rel, original: content, proposed: replaced,
                                               summary: "Regex replace in \(rel)"), call: call, session: s)
                } catch let error as MCPToolError where error.message == MCPServer.rejectedMessage {
                    throw error
                } catch {
                }
            }
        }
        guard !modifiedFiles.isEmpty else {
            return .text("No matches found for pattern `\(pattern)` in *.\(ext) files.")
        }
        let prefix = dryRun ? "[DRY RUN] Would modify" : "Successfully modified"
        var report = "\(prefix) \(modifiedFiles.count) file(s) with \(totalReplacements) total replacements:\n\n"
        for f in modifiedFiles.prefix(30) {
            report += "- \(f)\n"
        }
        return .text(report)
    }
}
