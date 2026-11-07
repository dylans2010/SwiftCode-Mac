#if os(macOS)
import AppKit
#endif
import Foundation
import YcodeAssistant
import YcodeIDECore

extension SwiftCodeMCPHost {
    var artifactTools: [MCPTool] {
        let write = MCPToolAnnotations(readOnly: false, idempotent: false)
        let finder = MCPToolAnnotations(readOnly: true, idempotent: true, openWorld: true)
        return [
            tool("list_artifacts", "List Artifacts",
                 "Lists all Markdown artifacts in the native artifact store, including agent_notes.md, newest first.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["artifacts": Schema.anyArray, "count": Schema.int])) { h, call in
                try h.listArtifacts(call)
            },
            tool("read_artifact", "Read Artifact",
                 "Reads a Markdown artifact's full content from the native artifact store (truncated at 60k characters).",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "name": Schema.string("Artifact name (snake_case, .md optional). Example: repository_analysis")],
                                      required: ["name"]),
                 output: Schema.output(["filename": Schema.str, "title": Schema.str, "kind": Schema.str, "truncated": Schema.bool,
                                        "contentLength": Schema.int, "content": Schema.str])) { h, call in
                try h.readArtifact(call)
            },
            tool("create_artifact", "Create Artifact",
                 "Creates (or updates/appends) a Markdown artifact in the native artifact store at .assist_temp/artifacts/<name>.md. The single way to produce durable deliverables. Optional kind parameter: \"artifact\" (default) or \"execution_plan\" for multi-phase plans/handoffs; when omitted, the store infers the kind from the filename. Keep content to a recommended ~25,000-character ceiling.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "name": Schema.string("Artifact name, snake_case (.md added automatically). Example: repository_analysis"),
                                       "content": Schema.string("Full Markdown document content."),
                                       "description": Schema.string("One-line description shown in the artifact list. Default: first meaningful line."),
                                       "mode": Schema.string("create (default) | update | append."),
                                       "kind": Schema.string("artifact (default) | execution_plan. Use execution_plan for multi-phase work plans and handoff documents; use artifact for everything else. When omitted, the store infers the kind from the filename (contains _plan, or starts/ends with plan_).")],
                                      required: ["name", "content"]),
                 output: Schema.output(["filename": Schema.str, "title": Schema.str, "relativePath": Schema.str, "mode": Schema.str,
                                        "kind": Schema.str, "contentLength": Schema.int]),
                 annotations: write, writes: true) { h, call in
                try await h.createArtifact(call)
            },
            tool("delete_artifact", "Delete Artifact",
                 "Permanently deletes a Markdown artifact from the native artifact store. agent_notes.md is protected and cannot be deleted.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "name": Schema.string("Artifact name (snake_case, .md optional)."),
                                       "confirm": Schema.boolean("Must be true to delete. Safety interlock.")],
                                      required: ["name", "confirm"]),
                 output: Schema.output(["filename": Schema.str]),
                 annotations: MCPToolAnnotations(readOnly: false, destructive: true), writes: true) { h, call in
                try await h.deleteArtifact(call)
            },
            tool("file_backup", "File Backup",
                 "Backs up a workspace file to .assist_temp/backups/<name>.<timestamp>.bak before a risky edit.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative file to back up.")],
                                      required: ["path"]),
                 output: Schema.output(["source": Schema.str, "backup": Schema.str, "bytes": Schema.int]),
                 annotations: write, writes: true) { h, call in
                try await h.backupFile(call)
            },
            tool("open_in_finder", "Open in Finder",
                 "Opens a file or directory in Finder or its default application.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative or absolute path to the file or directory.")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str]),
                 annotations: finder) { h, call in
                try h.openInFinder(call)
            },
            tool("reveal_in_finder", "Reveal in Finder",
                 "Reveals and selects a file or directory in macOS Finder.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative or absolute path to the item to reveal.")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str]),
                 annotations: finder) { h, call in
                try h.revealInFinder(call)
            },
        ]
    }

    func listArtifacts(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let records = listFileReadingArtifacts(in: s)
        if records.isEmpty {
            return .structured(["artifacts": .array([]), "count": .int(0)],
                               summary: "No artifacts yet. Use create_artifact to produce the first one.")
        }
        var lines = ["Artifacts (\(records.count)):"]
        let json: [AnyJSON] = records.map { r in
            let desc = r.description.isEmpty ? "" : " — \(r.description.prefix(100))"
            lines.append("- \(r.title) [\(Self.kindDisplayName(r.kind))] — \(r.relativePath)\(desc)")
            return ["filename": .string(r.filename), "title": .string(r.title), "description": .string(r.description),
                    "kind": .string(r.kind), "relativePath": .string(r.relativePath)]
        }
        return .structured(["artifacts": .array(json), "count": .int(records.count)], summary: lines.joined(separator: "\n"))
    }

    func readArtifact(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let name = try call.require("name").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MCPToolError("Missing required parameter: name") }
        let (record, content, truncated) = try readFileReadingArtifact(named: name, in: s)
        return .structured(["filename": .string(record.filename), "title": .string(record.title), "kind": .string(record.kind),
                            "truncated": .bool(truncated), "contentLength": .int(content.count), "content": .string(content)],
                           summary: "# \(record.title)")
    }

    func createArtifact(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let name = try call.require("name").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MCPToolError("Missing required parameter: name") }
        let content = try call.require("content")
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MCPToolError("Artifact content is empty. Provide a non-empty Markdown document.") }
        let description = (call.string("description") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let modeRaw = (call.string("mode") ?? "create").lowercased()
        let mode: ArtifactMode
        switch modeRaw {
        case "create": mode = .create
        case "update": mode = .update
        case "append": mode = .append
        default: throw MCPToolError("Invalid mode '\(modeRaw)'. Use create, update, or append.")
        }
        let kindRaw = (call.string("kind") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitKind: String?
        switch kindRaw.lowercased() {
        case "": explicitKind = nil
        case "artifact": explicitKind = "artifact"
        case "execution_plan": explicitKind = "execution_plan"
        default: throw MCPToolError("Invalid kind '\(kindRaw)'. Use artifact or execution_plan.")
        }
        guard let filename = FileReadingArtifactNaming.normalize(name) else {
            throw MCPToolError("Invalid artifact name '\(name)'. Use snake_case with a .md extension (e.g. repository_analysis.md).")
        }
        let rel = ".assist_temp/artifacts/\(filename)"
        let url = artifactDirectory(in: s).appendingPathComponent(filename)
        let exists = FileManager.default.fileExists(atPath: url.path)
        let finalContent: String
        switch mode {
        case .create:
            guard !exists else {
                throw MCPToolError("Artifact '\(filename)' already exists. Use mode 'update' to replace it or 'append' to add to it.")
            }
            finalContent = trimmed + "\n"
        case .update:
            guard exists else { throw MCPToolError("No artifact named '\(filename)' exists in the artifact store.") }
            finalContent = trimmed + "\n"
        case .append:
            if exists, let current = try? String(contentsOf: url, encoding: .utf8) {
                finalContent = current.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + trimmed + "\n"
            } else {
                finalContent = trimmed + "\n"
            }
        }
        let original = text(of: url)
        let summary: String = switch mode {
        case .create: "Create \(rel)"
        case .update: "Update \(rel)"
        case .append: "Append to \(rel)"
        }
        try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: original, proposed: finalContent,
                                   summary: summary), call: call, session: s)
        guard let verify = try? String(contentsOf: url, encoding: .utf8), verify == finalContent else {
            throw MCPToolError("Failed to write artifact: verification read-back mismatch for \(filename)")
        }
        var index = loadFileReadingArtifactIndex(in: s)
        var entry = index[filename] ?? FileReadingArtifactIndexEntry(id: UUID(), description: description,
                                                                      kind: FileReadingArtifactNaming.inferredKind(for: filename),
                                                                      createdAt: Date(), sourceMessageID: nil)
        if !description.isEmpty { entry.description = description }
        if let explicitKind { entry.kind = explicitKind }
        index[filename] = entry
        saveFileReadingArtifactIndex(index, in: s)
        return .structured(["filename": .string(filename), "title": .string(FileReadingArtifactNaming.displayTitle(for: filename)),
                            "relativePath": .string(rel), "mode": .string(modeRaw), "kind": .string(entry.kind),
                            "contentLength": .int(content.count)],
                           summary: "Artifact '\(FileReadingArtifactNaming.displayTitle(for: filename))' saved (\(modeRaw)) at \(rel).")
    }

    func deleteArtifact(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let name = try call.require("name").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MCPToolError("Missing required parameter: name") }
        guard call.bool("confirm") == true else {
            throw MCPToolError("Deletion requires confirm: true. The artifact was NOT deleted.")
        }
        guard let filename = FileReadingArtifactNaming.normalize(name) else {
            throw MCPToolError("Invalid artifact name '\(name)'. Use snake_case with a .md extension (e.g. repository_analysis.md).")
        }
        guard filename != FileReadingArtifactNaming.protectedFilename else {
            throw MCPToolError("Artifact '\(filename)' is managed by its own workflow and cannot be deleted through delete_artifact.")
        }
        let rel = ".assist_temp/artifacts/\(filename)"
        let url = artifactDirectory(in: s).appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPToolError("No artifact named '\(filename)' exists in the artifact store.")
        }
        let change = MCPChange(tool: call.name, path: url.path, relativePath: rel, original: text(of: url), proposed: "",
                               summary: "Delete \(rel) permanently")
        guard await call.approve(change) else { throw MCPToolError(MCPServer.rejectedMessage) }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw MCPToolError("Failed to write artifact: \(error.localizedDescription)")
        }
        var index = loadFileReadingArtifactIndex(in: s)
        index.removeValue(forKey: filename)
        saveFileReadingArtifactIndex(index, in: s)
        s.noteFileEdited(url.path)
        delegate?.mcpHostDidWrite(url.path)
        return .structured(["filename": .string(filename)], summary: "Artifact '\(filename)' deleted permanently.")
    }

    func backupFile(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = try call.require("path").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw MCPToolError("Missing required parameter: path") }
        let url = try resolveFileReadingPath(raw, in: s)
        guard FileManager.default.fileExists(atPath: url.path) else { throw MCPToolError("No file at path: \(raw)") }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupName = url.lastPathComponent + "." + stamp + ".bak"
        let backupURL = backupDirectory(in: s).appendingPathComponent(backupName)
        let rel = ".assist_temp/backups/\(backupName)"
        let change = MCPChange(tool: call.name, path: backupURL.path, relativePath: rel, original: nil, proposed: "",
                               summary: "Back up \(relative(url.path, in: s)) to \(rel)")
        guard await call.approve(change) else { throw MCPToolError(MCPServer.rejectedMessage) }
        do {
            try FileManager.default.createDirectory(at: backupDirectory(in: s), withIntermediateDirectories: true)
        } catch {
            throw MCPToolError("Cannot create backup directory: \(error.localizedDescription)")
        }
        do {
            try FileManager.default.copyItem(at: url, to: backupURL)
        } catch {
            throw MCPToolError("Backup failed: \(error.localizedDescription)")
        }
        let srcSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
        let dstSize = (try? FileManager.default.attributesOfItem(atPath: backupURL.path))?[.size] as? Int
        guard let srcSize, let dstSize, srcSize == dstSize else {
            try? FileManager.default.removeItem(at: backupURL)
            throw MCPToolError("Backup verification failed (size mismatch); backup removed.")
        }
        s.noteFileEdited(backupURL.path)
        delegate?.mcpHostDidWrite(backupURL.path)
        return .structured(["source": .string(raw), "backup": .string(rel), "bytes": .int(srcSize)],
                           summary: "Backed up \(raw) to \(rel) (\(srcSize) bytes).")
    }

    func openInFinder(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let path = try call.require("path").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw MCPToolError("Missing required argument: 'path'") }
        let url = try resolveFileReadingPath(path, in: s)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPToolError("Path does not exist: '\(path)' (resolved to \(url.path))")
        }
        #if os(macOS)
        if NSWorkspace.shared.open(url) {
            return .structured(["path": .string(url.path)], summary: "Opened in Finder: \(url.lastPathComponent)")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw MCPToolError("Failed to open path in Finder: \(url.path)")
        }
        guard process.terminationStatus == 0 else { throw MCPToolError("Failed to open path in Finder: \(url.path)") }
        return .structured(["path": .string(url.path)], summary: "Opened in Finder: \(url.lastPathComponent)")
        #else
        throw MCPToolError("open_in_finder is only available on macOS")
        #endif
    }

    func revealInFinder(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let path = try call.require("path").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw MCPToolError("Missing required argument: 'path'") }
        let url = try resolveFileReadingPath(path, in: s)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPToolError("Path does not exist: '\(path)' (resolved to \(url.path))")
        }
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return .structured(["path": .string(url.path)], summary: "Revealed in Finder: \(url.lastPathComponent)")
        #else
        throw MCPToolError("reveal_in_finder is only available on macOS")
        #endif
    }

    nonisolated static func kindDisplayName(_ kind: String) -> String {
        switch kind {
        case "execution_plan": "Execution Plan"
        case "agent_notes": "Agent Notes"
        case "image": "Image Screenshot"
        case "screen_recording": "Screen Recording"
        default: "Artifact"
        }
    }
}

private enum ArtifactMode: String, Sendable {
    case create
    case update
    case append
}
