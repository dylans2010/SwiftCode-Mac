import Foundation
import Observation

/// Project notes (Legacy `ProjectNotesModels` + `ProjectNotesWorkspaceState`,
/// Dylan's own code, ported under MIT). Notebooks hold notes; notes carry
/// versions, saved searches, links/backlinks and file attachments. State
/// persists as JSON in Application Support/Ycode/ProjectNotes
/// (`metadata.json`); attachments are copied into an `Attachments/`
/// directory there. Legacy persisted the same way (its own base directory);
/// the AI-conversation fields (`activeAIConversation`, `isAIProcessing`,
/// `activeAIPrompt`) are NOT ported — AI lives in the Assistant, and the
/// notes AI surface is the Documentation Browser's AI tab. Templates are
/// condensed to their section skeletons; the full prose bodies were not
/// carried over.

public struct NoteAttachment: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var type: String
    public var relativePath: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, type: String, relativePath: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.type = type
        self.relativePath = relativePath
        self.createdAt = createdAt
    }
}

public struct NoteVersion: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let noteId: UUID
    public var content: String
    public var timestamp: Date

    public init(id: UUID = UUID(), noteId: UUID, content: String, timestamp: Date = Date()) {
        self.id = id
        self.noteId = noteId
        self.content = content
        self.timestamp = timestamp
    }
}

public struct SavedSearch: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var query: String
    public var category: String
    public var createdAt: Date

    public init(id: UUID = UUID(), query: String, category: String = "General", createdAt: Date = Date()) {
        self.id = id
        self.query = query
        self.category = category
        self.createdAt = createdAt
    }
}

public struct ProjectNotebook: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

public struct ProjectNote: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var content: String
    public var notebookId: UUID
    public var category: String
    public var tags: [String]
    public var isPinned: Bool
    public var isFavorite: Bool
    public var isArchived: Bool
    public var author: String
    public var wordCount: Int
    public var readingTime: Int
    public var characterCount: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var linkedNoteIds: Set<UUID>
    public var linkedFiles: [String]
    public var linkedSymbols: [String]
    public var linkedGitCommits: [String]
    public var linkedBuildLogs: [String]
    public var linkedDeployments: [String]
    public var attachments: [NoteAttachment]
    public var backlinkNoteIds: Set<UUID>

    public init(
        id: UUID = UUID(), title: String, content: String, notebookId: UUID,
        category: String = "General", tags: [String] = [], isPinned: Bool = false,
        isFavorite: Bool = false, isArchived: Bool = false, author: String = "Developer",
        wordCount: Int = 0, readingTime: Int = 0, characterCount: Int = 0,
        createdAt: Date = Date(), updatedAt: Date = Date(),
        linkedNoteIds: Set<UUID> = [], linkedFiles: [String] = [], linkedSymbols: [String] = [],
        linkedGitCommits: [String] = [], linkedBuildLogs: [String] = [], linkedDeployments: [String] = [],
        attachments: [NoteAttachment] = [], backlinkNoteIds: Set<UUID> = []
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.notebookId = notebookId
        self.category = category
        self.tags = tags
        self.isPinned = isPinned
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.author = author
        self.wordCount = wordCount
        self.readingTime = readingTime
        self.characterCount = characterCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.linkedNoteIds = linkedNoteIds
        self.linkedFiles = linkedFiles
        self.linkedSymbols = linkedSymbols
        self.linkedGitCommits = linkedGitCommits
        self.linkedBuildLogs = linkedBuildLogs
        self.linkedDeployments = linkedDeployments
        self.attachments = attachments
        self.backlinkNoteIds = backlinkNoteIds
    }

    public mutating func refreshCounts() {
        let words = content.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        wordCount = words.count
        characterCount = content.count
        readingTime = max(1, wordCount / 200)
        updatedAt = Date()
    }
}

/// Built-in note templates (Legacy `ProjectNoteTemplates`). Bodies are the
/// section skeletons; the full prose was not carried over.
public struct ProjectNoteTemplates {
    public static let builtInTemplates: [String: String] = [
        "Architecture Notes": "# Architecture Notes\n\n## 1. Executive Summary\n## 2. Design Pattern & Structure\n## 3. Data Flow & Communication\n## 4. Technical Debt & Trade-offs\n",
        "API Documentation": "# API Documentation\n\n## 1. Overview\n## 2. Authentication & Headers\n## 3. Endpoint Specifications\n## 4. Error Codes\n",
        "Build Notes": "# Build Notes\n\n## 1. Build Metadata\n## 2. Compilation Targets\n## 3. Critical Warnings & Suppressions\n",
        "Debugging Notes": "# Debugging Notes\n\n## 1. Problem Description\n## 2. Reproduction Steps\n## 3. Root Cause Analysis\n## 4. Verification & Testing\n",
        "Deployment Notes": "# Deployment Notes\n\n## 1. Target Environment\n## 2. Pre-Deployment Checklist\n## 3. Rollback Procedure\n",
        "Feature Planning": "# Feature Planning\n\n## 1. User Story & Goal\n## 2. Scope & Boundaries\n## 3. Design & Architecture Sketch\n",
        "Sprint Planning": "# Sprint Planning\n\n## 1. Sprint Goal\n## 2. Team Capacity\n## 3. Backlog Items\n",
        "Bug Investigation": "# Bug Investigation\n\n## 1. Symptoms & Logs\n## 2. Areas of Inquiry\n## 3. Findings & Resolution Plan\n",
        "Code Reviews": "# Code Review Plan\n\n## 1. Review Objectives\n## 2. Focus Areas\n## 3. Feedback Notes\n",
        "Refactoring Plans": "# Refactoring Plan\n\n## 1. Rationale\n## 2. Target Architecture\n## 3. Safe Migration Steps\n",
        "Design Decisions": "# Architectural Design Decision (ADR)\n\n## 1. Title & Context\n## 2. Options Considered\n## 3. Decision\n## 4. Consequences\n",
        "Meeting Notes": "# Meeting Notes\n\n## 1. Agenda\n## 2. Discussion Summary\n## 3. Action Items\n",
        "Release Notes": "# Release Notes\n\n## 1. Overview\n## 2. New Features\n## 3. Bug Fixes & Refactoring\n",
        "Changelog Entries": "# Changelog\n\n## [Unreleased]\n## [1.0.0]\n",
        "Security Reviews": "# Security Review\n\n## 1. Threat Modeling\n## 2. Compliance Checklist\n## 3. Remediation Items\n",
        "Database Documentation": "# Database Schema Documentation\n\n## 1. Tables\n## 2. Migration Triggers\n",
        "AI Prompts": "# Prompt Spec\n\n## 1. System Instruction Context\n## 2. Model Configuration\n",
        "Research Notes": "# Research Notes\n\n## 1. Abstract & Scope\n## 2. Literature/API Review\n## 3. Prototype Implementation\n",
        "Performance Analysis": "# Performance Analysis\n\n## 1. Benchmarking Scope\n## 2. Observations & Metrics\n## 3. Optimization Opportunities\n",
        "Testing Plans": "# Test Plan\n\n## 1. Testing Strategy\n## 2. Test Cases\n",
        "User Stories": "# User Story\n\n## 1. Description\n## 2. Acceptance Criteria\n",
        "Feature Requests": "# Feature Request\n\n## 1. Context & Requestor\n## 2. Expected Behavior\n## 3. Impact & Priority\n",
        "Technical Debt": "# Technical Debt Log\n\n## 1. Identified Debt\n## 2. Strategic Impact\n## 3. Remediation Strategy\n",
        "Migration Plans": "# Migration Plan\n\n## 1. Target Tech Stack\n## 2. Deprecation Timeline\n## 3. Execution Plan\n",
        "Dependency Notes": "# Dependency Log\n\n## 1. Package Metadata\n## 2. Architectural Impact\n",
    ]
}

/// The notes workspace state (Legacy `ProjectNotesWorkspaceState`).
@Observable
@MainActor
public final class ProjectNotesWorkspaceState {
    public var notebooks: [ProjectNotebook] = []
    public var notes: [ProjectNote] = []
    public var selectedNotebookId: UUID?
    public var selectedNoteId: UUID?
    public var noteEditorText: String = ""
    public var isEditingNote: Bool = false
    public var searchQuery: String = ""
    public var searchHistory: [String] = []
    public var savedSearches: [SavedSearch] = []
    public var noteFilter: String = "All"
    public var recentNoteIds: [UUID] = []
    public var frequentlyAccessedNoteIds: [UUID: Int] = [:]
    public var noteVersions: [NoteVersion] = []
    public var isFocusMode: Bool = false
    public var isReadingMode: Bool = false
    public var isPresentationMode: Bool = false
    public var selectedTemplateKey: String = "None"
    public var activeInspectorTab: String = "Links"

    public init() {
        loadData()
    }

    public var baseDirectoryURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Ycode", isDirectory: true).appendingPathComponent("ProjectNotes", isDirectory: true)
    }

    private var metadataURL: URL { baseDirectoryURL.appendingPathComponent("metadata.json") }
    private var attachmentsDirectoryURL: URL { baseDirectoryURL.appendingPathComponent("Attachments", isDirectory: true) }

    private struct MetadataDTO: Codable {
        var notebooks: [ProjectNotebook]
        var notes: [ProjectNote]
        var noteVersions: [NoteVersion]
        var savedSearches: [SavedSearch]
        var searchHistory: [String]
    }

    public func loadData() {
        if let data = try? Data(contentsOf: metadataURL),
           let dto = try? JSONDecoder().decode(MetadataDTO.self, from: data) {
            notebooks = dto.notebooks
            notes = dto.notes
            noteVersions = dto.noteVersions
            savedSearches = dto.savedSearches
            searchHistory = dto.searchHistory
            return
        }
        seedInitialData()
    }

    public func saveData() {
        let dto = MetadataDTO(notebooks: notebooks, notes: notes, noteVersions: noteVersions, savedSearches: savedSearches, searchHistory: searchHistory)
        guard let data = try? JSONEncoder().encode(dto) else { return }
        try? FileManager.default.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        try? data.write(to: metadataURL, options: .atomic)
    }

    private func seedInitialData() {
        let notebook = ProjectNotebook(name: "General")
        notebooks = [notebook]
        var welcome = ProjectNote(title: "Welcome to Project Notes", content: "# Welcome to Project Notes\n\nUse notebooks to organise architecture, API, build, debugging and planning notes for this project. Link notes to files, symbols, commits and build logs from the inspector.", notebookId: notebook.id, category: "General")
        welcome.refreshCounts()
        notes = [welcome]
        selectedNotebookId = notebook.id
        selectedNoteId = welcome.id
        noteEditorText = welcome.content
        saveData()
    }

    public var activeNote: ProjectNote? {
        guard let id = selectedNoteId else { return nil }
        return notes.first(where: { $0.id == id })
    }

    public var activeNotebook: ProjectNotebook? {
        guard let id = selectedNotebookId else { return nil }
        return notebooks.first(where: { $0.id == id })
    }

    public var filteredNotes: [ProjectNote] {
        var result = notes
        if let notebookId = selectedNotebookId {
            result = result.filter { $0.notebookId == notebookId }
        }
        switch noteFilter {
        case "Pinned": result = result.filter(\.isPinned)
        case "Favorites": result = result.filter(\.isFavorite)
        case "Archived": result = result.filter(\.isArchived)
        case "Recent": result = result.sorted { $0.updatedAt > $1.updatedAt }
        default: break
        }
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) || $0.content.lowercased().contains(query)
                    || $0.tags.contains(where: { $0.lowercased().contains(query) })
            }
        }
        return result.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    public func selectNote(_ id: UUID) {
        if let note = notes.first(where: { $0.id == id }) {
            if selectedNoteId != id {
                saveActiveNote(content: noteEditorText)
            }
            selectedNoteId = id
            selectedNotebookId = note.notebookId
            noteEditorText = note.content
            isEditingNote = false
            recentNoteIds.removeAll { $0 == id }
            recentNoteIds.insert(id, at: 0)
            frequentlyAccessedNoteIds[id, default: 0] += 1
        }
    }

    public func createNote(title: String = "Untitled Note", content: String = "", category: String = "General", notebookId: UUID? = nil) {
        let targetNotebook = notebookId ?? selectedNotebookId ?? notebooks.first?.id ?? {
            let notebook = ProjectNotebook(name: "General")
            notebooks.append(notebook)
            return notebook.id
        }()
        var note = ProjectNote(title: title, content: content.isEmpty ? (ProjectNoteTemplates.builtInTemplates[selectedTemplateKey] ?? "") : content, notebookId: targetNotebook, category: category)
        note.refreshCounts()
        notes.append(note)
        selectedNoteId = note.id
        selectedNotebookId = targetNotebook
        noteEditorText = note.content
        saveData()
    }

    public func duplicateNote(_ note: ProjectNote) {
        var copy = note
        copy.id = UUID()
        copy.title = note.title + " Copy"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.linkedNoteIds = []
        copy.backlinkNoteIds = []
        notes.append(copy)
        saveData()
    }

    public func deleteNote(_ note: ProjectNote) {
        notes.removeAll { $0.id == note.id }
        noteVersions.removeAll { $0.noteId == note.id }
        if selectedNoteId == note.id { selectedNoteId = nil }
        syncBacklinks(for: note)
        saveData()
    }

    public func updateActiveNoteContent(_ newContent: String) {
        noteEditorText = newContent
        isEditingNote = true
    }

    public func saveActiveNote(content: String) {
        guard let id = selectedNoteId, let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if notes[index].content == content { return }
        saveCurrentVersionSnapshot(for: notes[index])
        notes[index].content = content
        notes[index].refreshCounts()
        isEditingNote = false
        saveData()
    }

    public func createNotebook(name: String) {
        let notebook = ProjectNotebook(name: name)
        notebooks.append(notebook)
        selectedNotebookId = notebook.id
        saveData()
    }

    public func deleteNotebook(_ notebookId: UUID) {
        notes.removeAll { $0.notebookId == notebookId }
        notebooks.removeAll { $0.id == notebookId }
        if selectedNotebookId == notebookId { selectedNotebookId = notebooks.first?.id }
        saveData()
    }

    private func syncBacklinks(for note: ProjectNote) {
        for index in notes.indices {
            notes[index].linkedNoteIds.remove(note.id)
            notes[index].backlinkNoteIds.remove(note.id)
        }
        for index in notes.indices where notes[index].linkedNoteIds.contains(note.id) {
            notes[index].backlinkNoteIds.insert(note.id)
        }
    }

    public func linkNote(from noteId: UUID, to targetNoteId: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == noteId }),
              notes.contains(where: { $0.id == targetNoteId }), noteId != targetNoteId else { return }
        notes[index].linkedNoteIds.insert(targetNoteId)
        if let targetIndex = notes.firstIndex(where: { $0.id == targetNoteId }) {
            notes[targetIndex].backlinkNoteIds.insert(noteId)
        }
        saveData()
    }

    public func unlinkNote(from noteId: UUID, to targetNoteId: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == noteId }) else { return }
        notes[index].linkedNoteIds.remove(targetNoteId)
        if let targetIndex = notes.firstIndex(where: { $0.id == targetNoteId }) {
            notes[targetIndex].backlinkNoteIds.remove(noteId)
        }
        saveData()
    }

    public func attachFile(to note: ProjectNote, fileURL: URL) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        try? FileManager.default.createDirectory(at: attachmentsDirectoryURL, withIntermediateDirectories: true)
        let destination = attachmentsDirectoryURL.appendingPathComponent(fileURL.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: fileURL, to: destination)
        } catch {
            return
        }
        let attachment = NoteAttachment(
            name: fileURL.lastPathComponent,
            type: fileURL.pathExtension.lowercased(),
            relativePath: "Attachments/\(fileURL.lastPathComponent)"
        )
        notes[index].attachments.append(attachment)
        saveData()
    }

    public func deleteAttachment(_ attachment: NoteAttachment, from note: ProjectNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].attachments.removeAll { $0.id == attachment.id }
        try? FileManager.default.removeItem(at: baseDirectoryURL.appendingPathComponent(attachment.relativePath))
        saveData()
    }

    public func saveCurrentVersionSnapshot(for note: ProjectNote) {
        noteVersions.append(NoteVersion(noteId: note.id, content: note.content))
        saveData()
    }

    public func rollbackToVersion(_ version: NoteVersion) {
        guard let index = notes.firstIndex(where: { $0.id == version.noteId }) else { return }
        saveCurrentVersionSnapshot(for: notes[index])
        notes[index].content = version.content
        notes[index].refreshCounts()
        noteEditorText = version.content
        saveData()
    }

    public func saveSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchHistory.removeAll { $0 == trimmed }
        searchHistory.insert(trimmed, at: 0)
        if searchHistory.count > 20 { searchHistory = Array(searchHistory.prefix(20)) }
        saveData()
    }

    public func deleteSavedSearch(_ search: SavedSearch) {
        savedSearches.removeAll { $0.id == search.id }
        saveData()
    }
}
