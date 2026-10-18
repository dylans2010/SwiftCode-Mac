import Foundation
import Observation
import os

// MARK: - Assist Artifact Store
//
// Central, observable registry for Assist Markdown artifacts.
//
// Storage convention (established by AgentNotesManager's gitignore rules):
//   <workspaceRoot>/.assist_temp/artifacts/<snake_case_name>.md
// `.assist_temp/` is git-ignored, so artifacts never pollute the repo.
// `agent_notes.md` keeps its historical location at the workspace root and
// is surfaced as a first-class artifact without being moved.
//
// A small JSON sidecar (`.artifacts_index.json`) persists per-artifact
// metadata (stable id, description, creation date, kind) that cannot be
// derived from the file alone.

public enum AssistArtifactKind: String, Codable, Sendable, CaseIterable {
    case artifact
    case agentNotes = "agent_notes"
    case executionPlan = "execution_plan"

    public var displayName: String {
        switch self {
        case .artifact: return "Artifact"
        case .agentNotes: return "Agent Notes"
        case .executionPlan: return "Execution Plan"
        }
    }
}

public struct AssistArtifactRecord: Codable, Sendable, Identifiable {
    public var id: UUID
    public var filename: String
    public var title: String
    public var description: String
    public var kind: AssistArtifactKind
    /// Workspace-relative path (e.g. `.assist_temp/artifacts/foo.md` or `agent_notes.md`).
    public var relativePath: String
    public var createdAt: Date
    public var modifiedAt: Date
    /// Chat message that produced this artifact, if known. Used to link
    /// artifacts back to the conversation that requested them.
    public var sourceMessageID: UUID? = nil

    public init(
        id: UUID = UUID(),
        filename: String,
        title: String,
        description: String,
        kind: AssistArtifactKind,
        relativePath: String,
        createdAt: Date,
        modifiedAt: Date,
        sourceMessageID: UUID? = nil
    ) {
        self.id = id
        self.filename = filename
        self.title = title
        self.description = description
        self.kind = kind
        self.relativePath = relativePath
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.sourceMessageID = sourceMessageID
    }
}

public enum AssistArtifactMode: String, Sendable {
    case create
    case update
    case append
}

public enum AssistArtifactError: Error, LocalizedError {
    case invalidName(String)
    case emptyContent
    case alreadyExists(String)
    case notFound(String)
    case notDeletable(String)
    case writeFailed(String)
    case readFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName(let n): return "Invalid artifact name '\(n)'. Use snake_case with a .md extension (e.g. repository_analysis.md)."
        case .emptyContent: return "Artifact content is empty. Provide a non-empty Markdown document."
        case .alreadyExists(let n): return "Artifact '\(n)' already exists. Use mode 'update' to replace it or 'append' to add to it."
        case .notFound(let n): return "No artifact named '\(n)' exists in the artifact store."
        case .notDeletable(let n): return "Artifact '\(n)' is managed by its own workflow and cannot be deleted through delete_artifact."
        case .writeFailed(let d): return "Failed to write artifact: \(d)"
        case .readFailed(let d): return "Failed to read artifact: \(d)"
        }
    }
}

@Observable
@MainActor
public final class AssistArtifactStore: Sendable {
    public static let shared = AssistArtifactStore()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistArtifactStore")
    private let fileManager = FileManager.default

    /// Records for the current workspace, newest first. Drives AssistArtifactsView.
    public private(set) var records: [AssistArtifactRecord] = []
    public private(set) var currentWorkspaceRoot: URL?
    public private(set) var lastRefresh: Date?

    private struct IndexEntry: Codable {
        var id: UUID
        var description: String
        var kind: AssistArtifactKind
        var createdAt: Date
        /// Chat message that produced this artifact, if known.
        var sourceMessageID: UUID? = nil
    }

    private init() {}

    // MARK: - Kind inference

    /// Strict kind inference from a normalized filename. A filename is an
    /// execution plan only when it contains `_plan`, starts with `plan_`,
    /// or ends with `_plan` — a bare `plan` substring (e.g.
    /// `airplane_notes.md`) no longer classifies as a plan. An explicit
    /// `kind` argument to `createArtifact` always wins over this inference.
    private static func inferredKind(for filename: String) -> AssistArtifactKind {
        var stem = filename.lowercased()
        if stem.hasSuffix(".md") { stem = String(stem.dropLast(3)) }
        if stem.contains("_plan") || stem.hasPrefix("plan_") || stem.hasSuffix("_plan") {
            return .executionPlan
        }
        return .artifact
    }

    // MARK: - Locations

    public func artifactsDirectory(workspaceRoot: URL) -> URL {
        workspaceRoot.appendingPathComponent(".assist_temp/artifacts", isDirectory: true)
    }

    private func indexURL(workspaceRoot: URL) -> URL {
        artifactsDirectory(workspaceRoot: workspaceRoot).appendingPathComponent(".artifacts_index.json")
    }

    private func loadIndex(workspaceRoot: URL) -> [String: IndexEntry] {
        let url = indexURL(workspaceRoot: workspaceRoot)
        guard let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode([String: IndexEntry].self, from: data) else {
            return [:]
        }
        return index
    }

    private func saveIndex(_ index: [String: IndexEntry], workspaceRoot: URL) {
        let dir = artifactsDirectory(workspaceRoot: workspaceRoot)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: indexURL(workspaceRoot: workspaceRoot), options: .atomic)
    }

    // MARK: - Refresh / discovery

    /// Rebuild `records` from disk: the artifacts directory plus the
    /// well-known `agent_notes.md` at the workspace root.
    @discardableResult
    public func refresh(workspaceRoot: URL) -> [AssistArtifactRecord] {
        currentWorkspaceRoot = workspaceRoot
        var found: [AssistArtifactRecord] = []
        let index = loadIndex(workspaceRoot: workspaceRoot)
        let dir = artifactsDirectory(workspaceRoot: workspaceRoot)

        if let entries = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey], options: [.skipsHiddenFiles]) {
            for url in entries where url.pathExtension.lowercased() == "md" {
                let filename = url.lastPathComponent
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
                let modified = values?.contentModificationDate ?? Date()
                let fileCreated = values?.creationDate ?? modified
                let entry = index[filename]
                let description = entry?.description ?? Self.firstMeaningfulLine(of: url) ?? ""
                let kind: AssistArtifactKind = entry?.kind ?? Self.inferredKind(for: filename)
                found.append(AssistArtifactRecord(
                    id: entry?.id ?? UUID(),
                    filename: filename,
                    title: AssistArtifactNaming.displayTitle(for: filename),
                    description: description,
                    kind: kind,
                    relativePath: ".assist_temp/artifacts/\(filename)",
                    createdAt: entry?.createdAt ?? fileCreated,
                    modifiedAt: modified,
                    sourceMessageID: entry?.sourceMessageID
                ))
            }
        }

        // agent_notes.md keeps its workspace-root location; surface it too.
        let notesURL = workspaceRoot.appendingPathComponent("agent_notes.md")
        if fileManager.fileExists(atPath: notesURL.path) {
            let values = try? notesURL.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let modified = values?.contentModificationDate ?? Date()
            found.append(AssistArtifactRecord(
                filename: "agent_notes.md",
                title: "Agent Notes",
                description: "Live agent notes and execution plan for the active task.",
                kind: .agentNotes,
                relativePath: "agent_notes.md",
                createdAt: values?.creationDate ?? modified,
                modifiedAt: modified
            ))
        }

        found.sort { $0.modifiedAt > $1.modifiedAt }
        records = found
        lastRefresh = Date()
        return found
    }

    private static func firstMeaningfulLine(of url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in content.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if !t.isEmpty {
                return String(t.prefix(140))
            }
        }
        return nil
    }

    // MARK: - CRUD

    /// Create, update, or append a Markdown artifact. Returns the record.
    ///
    /// - Parameter kind: Explicit artifact kind. When nil, the kind is
    ///   inferred from the filename (strict `_plan` rules). An explicit
    ///   kind always wins over filename inference.
    /// - Parameter sourceMessageID: Optional chat message that produced
    ///   this artifact; persisted in the sidecar index.
    @discardableResult
    public func createArtifact(
        name: String,
        content: String,
        description: String,
        mode: AssistArtifactMode,
        kind: AssistArtifactKind? = nil,
        sourceMessageID: UUID? = nil,
        workspaceRoot: URL
    ) throws -> AssistArtifactRecord {
        guard let filename = AssistArtifactNaming.normalize(name) else {
            throw AssistArtifactError.invalidName(name)
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AssistArtifactError.emptyContent }

        let dir = artifactsDirectory(workspaceRoot: workspaceRoot)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)
        let exists = fileManager.fileExists(atPath: url.path)

        let finalContent: String
        switch mode {
        case .create:
            if exists { throw AssistArtifactError.alreadyExists(filename) }
            finalContent = trimmed + "\n"
        case .update:
            if !exists { throw AssistArtifactError.notFound(filename) }
            finalContent = trimmed + "\n"
        case .append:
            if exists, let current = try? String(contentsOf: url, encoding: .utf8) {
                finalContent = current.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + trimmed + "\n"
            } else {
                finalContent = trimmed + "\n"
            }
        }

        do {
            try finalContent.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw AssistArtifactError.writeFailed(error.localizedDescription)
        }
        // Verify the write by reading it back.
        guard let verify = try? String(contentsOf: url, encoding: .utf8), verify == finalContent else {
            throw AssistArtifactError.writeFailed("verification read-back mismatch for \(filename)")
        }

        var index = loadIndex(workspaceRoot: workspaceRoot)
        let entry = index[filename] ?? IndexEntry(
            id: UUID(),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: Self.inferredKind(for: filename),
            createdAt: Date()
        )
        var updatedEntry = entry
        if !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updatedEntry.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // An explicit kind always wins, even over a previously stored kind.
        if let kind {
            updatedEntry.kind = kind
        }
        // Persist the producing message when the caller knows it.
        if let sourceMessageID {
            updatedEntry.sourceMessageID = sourceMessageID
        }
        index[filename] = updatedEntry
        saveIndex(index, workspaceRoot: workspaceRoot)

        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let record = AssistArtifactRecord(
            id: updatedEntry.id,
            filename: filename,
            title: AssistArtifactNaming.displayTitle(for: filename),
            description: updatedEntry.description,
            kind: updatedEntry.kind,
            relativePath: ".assist_temp/artifacts/\(filename)",
            createdAt: updatedEntry.createdAt,
            modifiedAt: values?.contentModificationDate ?? Date(),
            sourceMessageID: updatedEntry.sourceMessageID
        )
        refresh(workspaceRoot: workspaceRoot)
        logger.info("Artifact \(mode) -> \(filename)")
        return record
    }

    public func readArtifact(name: String, workspaceRoot: URL, maxCharacters: Int = 60_000) throws -> (record: AssistArtifactRecord, content: String, wasTruncated: Bool) {
        guard let filename = AssistArtifactNaming.normalize(name) else {
            throw AssistArtifactError.invalidName(name)
        }
        let matches = refresh(workspaceRoot: workspaceRoot).filter { $0.filename.lowercased() == filename.lowercased() }
        guard let record = matches.first else { throw AssistArtifactError.notFound(filename) }
        let url = workspaceRoot.appendingPathComponent(record.relativePath)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw AssistArtifactError.readFailed("could not decode \(filename) as UTF-8")
        }
        if content.count > maxCharacters {
            return (record, String(content.prefix(maxCharacters)) + "\n… [truncated: showing first \(maxCharacters) of \(content.count) characters. The recommended write ceiling for new artifacts is ~25,000 characters — link workspace files instead of pasting them whole.]", true)
        }
        return (record, content, false)
    }

    public func deleteArtifact(name: String, workspaceRoot: URL) throws -> String {
        guard let filename = AssistArtifactNaming.normalize(name) else {
            throw AssistArtifactError.invalidName(name)
        }
        if filename == "agent_notes.md" {
            throw AssistArtifactError.notDeletable(filename)
        }
        let url = artifactsDirectory(workspaceRoot: workspaceRoot).appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: url.path) else {
            throw AssistArtifactError.notFound(filename)
        }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw AssistArtifactError.writeFailed(error.localizedDescription)
        }
        var index = loadIndex(workspaceRoot: workspaceRoot)
        index.removeValue(forKey: filename)
        saveIndex(index, workspaceRoot: workspaceRoot)
        refresh(workspaceRoot: workspaceRoot)
        logger.info("Artifact deleted: \(filename)")
        return filename
    }

    public func listArtifacts(workspaceRoot: URL) -> [AssistArtifactRecord] {
        refresh(workspaceRoot: workspaceRoot)
    }
}
