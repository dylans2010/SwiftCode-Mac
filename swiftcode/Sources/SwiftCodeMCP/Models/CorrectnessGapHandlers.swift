import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore

extension SwiftCodeMCPHost {

    func correctnessSafeUndo(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard let entry = SafeUndoJournal.shared.entries(workspaceRoot: root).last else {
            throw MCPToolError("safe_undo is unavailable: no agent modification has been recorded yet in this workspace. safe_undo reverts the last modification recorded by a write tool (file_write, file_create, code_replace, …). Nothing was changed.")
        }
        guard !entry.unrecorded else {
            throw MCPToolError("safe_undo cannot undo the last modification: the previous content of \(entry.relativePath) was not recorded (the file was too large or not UTF-8). Nothing was changed.")
        }
        let url = root.appendingPathComponent(entry.relativePath)
        try await approveFileWritingChange(tool: call.name, path: url, relativePath: entry.relativePath, original: text(of: url),
                                           summary: "Undo \(entry.tool) on \(entry.relativePath) — restore its previous content", call: call)
        guard let restored = SafeUndoJournal.shared.popLast(workspaceRoot: root), restored == entry else {
            throw MCPToolError("safe_undo failed: the recorded modification changed while the undo was being approved. Nothing was changed.")
        }
        do {
            if let original = restored.original {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try original.write(to: url, atomically: true, encoding: .utf8)
            } else if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            throw MCPToolError("safe_undo failed to restore \(restored.relativePath): \(error.localizedDescription)")
        }
        noteFileWritingChanged(url, in: s)
        if restored.original == nil {
            return .text("Undid \(restored.tool) on \(restored.relativePath): the file did not exist before the change, so it was removed.")
        }
        return .text("Undid \(restored.tool) on \(restored.relativePath): restored its previous content.")
    }

    func correctnessSessionProgress(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let notesURL = root.appendingPathComponent("agent_notes.md")
        let notesLine: String
        if let mtime = Self.reviewDocsModificationDate(of: notesURL) {
            notesLine = "Agent notes last saved: \(Self.reviewDocsIso8601(mtime))"
        } else {
            notesLine = "Agent notes: never saved this session."
        }
        let plans = AgenticPlanningPlanStore.shared.plans(workspace: memoryWorkspaceKey(in: s))
        let tasks = plans.flatMap(\.tasks)
        if tasks.isEmpty {
            return .structured(["phaseCount": .int(0), "completed": .int(0), "inProgress": .int(0), "failed": .int(0), "pending": .int(0)],
                               summary: "No engineering phases are registered for this session.\n\(notesLine)")
        }
        let completed = tasks.filter { $0.status == "completed" }
        let inProgress = tasks.filter { $0.status == "in_progress" }
        let failed = tasks.filter { $0.status == "failed" }
        let skipped = tasks.filter { $0.status == "skipped" }
        let pending = tasks.filter { !["completed", "in_progress", "failed", "skipped"].contains($0.status) }
        let progress = tasks.map(\.progressWeight).reduce(0.0, +) / Double(tasks.count)
        var lines = ["Session progress: \(completed.count) of \(tasks.count) phases completed (\(plans.count) plan(s), \(Int(progress * 100))% by task weight)."]
        switch s.activity {
        case .idle: break
        case .building(let what): lines.append("Session: building \(what).")
        case .running(let what): lines.append("Session: running \(what).")
        case .paused(let what): lines.append("Session: paused \(what).")
        case .finished(let what): lines.append("Session: \(what).")
        }
        if s.failedTestCount > 0 { lines.append("Failed tests in last run: \(s.failedTestCount).") }
        if !inProgress.isEmpty {
            lines.append("In progress (\(inProgress.count)):")
            lines += inProgress.map { "- \($0.title)" }
        }
        if !failed.isEmpty {
            lines.append("Failed (\(failed.count)):")
            for task in failed {
                let detail = task.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append(detail.isEmpty ? "- \(task.title)" : "- \(task.title): \(String(detail.prefix(200)))")
            }
        }
        if !pending.isEmpty { lines.append("Pending: \(pending.map(\.title).joined(separator: ", ").prefix(200))") }
        if !skipped.isEmpty { lines.append("Skipped: \(skipped.count)") }
        lines.append(notesLine)
        return .structured(["phaseCount": .int(tasks.count), "completed": .int(completed.count), "inProgress": .int(inProgress.count),
                            "failed": .int(failed.count), "pending": .int(pending.count)],
                           summary: lines.joined(separator: "\n"))
    }

    func correctnessSwiftASTInspector(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let path = try fileReadingRequiredString(call, "path")
        let symbolFilter = call.arguments["symbol"]?.string
        guard let resolvedURL = resolveFileWritingPath(path, in: s) else {
            throw MCPToolError("File not found at path: \(path)")
        }
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            throw MCPToolError("File not found at path: \(path)")
        }
        guard let content = try? String(contentsOf: resolvedURL, encoding: .utf8) else {
            throw MCPToolError("Unable to read source file at \(path)")
        }
        let inspection = SwiftASTInspection.inspect(source: content, file: path, symbolFilter: symbolFilter)
        if inspection.declarations.isEmpty {
            return .text("No major type declarations found in \(path).")
        }
        var lines = ["Swift AST declarations in \(path) (parsed with swift-syntax):"]
        func render(_ decls: [SwiftASTInspection.Declaration], indent: String) {
            for decl in decls {
                var head = "\(indent)- [\(decl.kind)] \(decl.name) (line \(decl.line))"
                if !decl.inheritance.isEmpty { head += " : " + decl.inheritance.joined(separator: ", ") }
                if !decl.detail.isEmpty { head += " \(decl.detail)" }
                lines.append(head)
                render(decl.members, indent: indent + "  ")
            }
        }
        render(inspection.declarations, indent: "")
        if !inspection.imports.isEmpty {
            lines.append("Imports: " + inspection.imports.joined(separator: ", ") + ".")
        }
        if inspection.hasError {
            lines.append("Note: the file has parse errors; results may be incomplete.")
        }
        return .text(lines.joined(separator: "\n"))
    }

    func correctnessRenameSymbolProject(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard let oldName = call.arguments["oldName"]?.string, !oldName.isEmpty else {
            throw MCPToolError("Missing required parameter: oldName")
        }
        guard let newName = call.arguments["newName"]?.string, !newName.isEmpty else {
            throw MCPToolError("Missing required parameter: newName")
        }
        guard Self.isValidSearchIdentifier(oldName) else {
            throw MCPToolError("Invalid oldName '\(oldName)': identifiers may contain only letters, digits, and underscores, and must not start with a digit.")
        }
        guard Self.isValidSearchIdentifier(newName) else {
            throw MCPToolError("Invalid newName '\(newName)': identifiers may contain only letters, digits, and underscores, and must not start with a digit.")
        }
        guard oldName != newName else {
            throw MCPToolError("Refusing rename: oldName and newName are identical ('\(oldName)').")
        }
        let scope: URL
        if let raw = call.arguments["path"]?.string, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let resolved = resolveFileWritingPath(raw, in: s) else {
                throw MCPToolError("Invalid path: path must stay inside the workspace and must not contain '..'.")
            }
            scope = resolved
        } else {
            scope = root
        }
        let files = Self.renameScopeFiles(at: scope)
        if files.isEmpty {
            return .structured(["filesChanged": .string(""), "replacementCount": .int(0), "changedFileCount": .int(0)],
                               summary: "Rename Symbol: no Swift files found.")
        }
        var changed: [String] = []
        var totalReplacements = 0
        var totalSkipped = 0
        for url in files {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let renamed = SymbolRenameEngine.rename(source: content, oldName: oldName, newName: newName)
            totalSkipped += renamed.skipped
            guard renamed.replacements > 0 else { continue }
            let rel = relative(url.path, in: s)
            try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel,
                                       original: content, proposed: renamed.updated,
                                       summary: "Rename \(oldName) to \(newName) in \(rel)"),
                             call: call, session: s)
            changed.append(rel)
            totalReplacements += renamed.replacements
        }
        if changed.isEmpty {
            var summary = "Rename Symbol: no identifier occurrences of '\(oldName)' found in \(files.count) Swift file(s). Nothing changed."
            if totalSkipped > 0 {
                summary += " (\(totalSkipped) whole-word occurrence(s) exist only inside strings, comments, or import paths and were left alone.)"
            }
            return .structured(["filesChanged": .string(""), "replacementCount": .int(0), "changedFileCount": .int(0)],
                               summary: summary)
        }
        var summary = "Rename Symbol: replaced \(totalReplacements) identifier occurrence(s) of '\(oldName)' with '\(newName)' across \(changed.count) file(s)"
        if totalSkipped > 0 {
            summary += " (\(totalSkipped) occurrence(s) inside strings, comments, or import paths left alone)"
        }
        summary += ":\n" + changed.map { "- \($0)" }.joined(separator: "\n")
        return .structured(["filesChanged": .string(changed.joined(separator: "\n")),
                            "replacementCount": .int(totalReplacements),
                            "changedFileCount": .int(changed.count)],
                           summary: summary)
    }
}
