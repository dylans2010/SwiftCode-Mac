import Foundation
import SwiftUI
import Observation
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "ProjectNotesWorkspaceState")

@Observable
@MainActor
public final class ProjectNotesWorkspaceState {
    public static let shared = ProjectNotesWorkspaceState()

    // MARK: - Core State
    public var notebooks: [ProjectNotebook] = []
    public var notes: [ProjectNote] = []
    public var selectedNotebookId: UUID? = nil
    public var selectedNoteId: UUID? = nil
    public var noteEditorText: String = ""
    public var isEditingNote: Bool = false
    public var searchQuery: String = ""
    public var searchHistory: [String] = []
    public var savedSearches: [SavedSearch] = []
    public var noteFilter: String = "All" // "All", "Pinned", "Favorites", "Archived", "Recent", "Todo", "Daily Notes", "Scratch Pad"
    public var recentNoteIds: [UUID] = []
    public var frequentlyAccessedNoteIds: [UUID: Int] = [:]

    // AI Workspace States
    public var activeAIConversation: [LocalChatMsg] = []
    public var isAIProcessing: Bool = false
    public var activeAIPrompt: String = ""

    // Version History
    public var noteVersions: [NoteVersion] = []

    // Productivity views
    public var isFocusMode: Bool = false
    public var isReadingMode: Bool = false
    public var isPresentationMode: Bool = false
    public var selectedTemplateKey: String = "None"
    public var activeInspectorTab: String = "AI Copilot" // "AI Copilot", "Links", "Attachments", "History"

    private init() {
        loadData()
    }

    // MARK: - Path Resolution
    var baseDirectoryURL: URL {
        let fileManager = FileManager.default
        let projectURL = ProjectSessionStore.shared.activeProject?.directoryURL
        let resolvedURL = projectURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let notesDir = resolvedURL.appendingPathComponent(".swiftcode/notes", isDirectory: true)

        try? fileManager.createDirectory(at: notesDir, withIntermediateDirectories: true)
        return notesDir
    }

    private var metadataURL: URL {
        baseDirectoryURL.appendingPathComponent("notes_metadata.json")
    }

    private var attachmentsDirectoryURL: URL {
        let url = baseDirectoryURL.appendingPathComponent("attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Persistence DTOs
    private struct MetadataDTO: Codable {
        let notebooks: [ProjectNotebook]
        let notes: [ProjectNote]
        let savedSearches: [SavedSearch]
        let searchHistory: [String]
        let noteVersions: [NoteVersion]
        let recentNoteIds: [UUID]
        let frequentlyAccessedNoteIds: [UUID: Int]
    }

    // MARK: - Persistence Logic
    public func loadData() {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            seedInitialData()
            return
        }

        do {
            let data = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            let dto = try decoder.decode(MetadataDTO.self, from: data)

            self.notebooks = dto.notebooks
            self.notes = dto.notes
            self.savedSearches = dto.savedSearches
            self.searchHistory = dto.searchHistory
            self.noteVersions = dto.noteVersions
            self.recentNoteIds = dto.recentNoteIds
            self.frequentlyAccessedNoteIds = dto.frequentlyAccessedNoteIds

            // Ensure notes content is loaded from disk files if possible
            for i in 0..<notes.count {
                let noteFile = baseDirectoryURL.appendingPathComponent("\(notes[i].id).md")
                if fileManager.fileExists(atPath: noteFile.path),
                   let content = try? String(contentsOf: noteFile, encoding: .utf8) {
                    notes[i].content = content
                }
            }

            if selectedNotebookId == nil {
                selectedNotebookId = notebooks.first?.id
            }
            if selectedNoteId == nil {
                selectedNoteId = notes.first { $0.notebookId == selectedNotebookId }?.id
            }
            if let note = activeNote {
                noteEditorText = note.content
            }
        } catch {
            logger.error("Failed to load project notes metadata: \(error.localizedDescription)")
            seedInitialData()
        }
    }

    public func saveData() {
        do {
            let fileManager = FileManager.default

            // 1. Write note contents to individual .md files
            for note in notes {
                let noteFile = baseDirectoryURL.appendingPathComponent("\(note.id).md")
                try note.content.write(to: noteFile, atomically: true, encoding: .utf8)
            }

            // 2. Write metadata
            let dto = MetadataDTO(
                notebooks: notebooks,
                notes: notes,
                savedSearches: savedSearches,
                searchHistory: searchHistory,
                noteVersions: noteVersions,
                recentNoteIds: recentNoteIds,
                frequentlyAccessedNoteIds: frequentlyAccessedNoteIds
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(dto)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            logger.error("Failed to save project notes metadata: \(error.localizedDescription)")
        }
    }

    private func seedInitialData() {
        let generalNotebook = ProjectNotebook(name: "My Notebook")
        let dailyNotebook = ProjectNotebook(name: "Daily Journals")

        self.notebooks = [generalNotebook, dailyNotebook]
        self.selectedNotebookId = generalNotebook.id

        let welcomeNote = ProjectNote(
            title: "Welcome to Project Notes",
            content: """
# Welcome to Project Notes Workspace!

This is your secure, multi-featured, local-first developer knowledge base.

## Features
- **Rich Markdown Live Preview**: Type on the left, watch responsive preview on the right.
- **Deep Code Linking**: Reference files like `LLMService.swift`, struct definitions, or Git commits.
- **AI Assistant**: Streaming rewrites, action items generation, and documentation reviews.
- **Version Snapshots**: Track revisions and easily rollback changes.
- **Attachments**: Drag-and-drop or import PDFs, YAML, Swift files, or ZIP attachments.

Feel free to customize, create notebooks, and start organizing your engineering workflows!
""",
            notebookId: generalNotebook.id,
            category: "General",
            tags: ["Guide", "Onboarding"],
            isPinned: true,
            isFavorite: true
        )

        let scratchPadNote = ProjectNote(
            title: "Scratch Pad",
            content: "## Scratch Pad\n\nUse this space for quick developer notes, temporary code blocks, or draft specs.",
            notebookId: generalNotebook.id,
            category: "General",
            tags: ["Scratch"],
            isPinned: false,
            isFavorite: false
        )

        self.notes = [welcomeNote, scratchPadNote]
        self.selectedNoteId = welcomeNote.id
        self.noteEditorText = welcomeNote.content

        saveData()
    }

    // MARK: - Computed Properties
    public var activeNote: ProjectNote? {
        notes.first { $0.id == selectedNoteId }
    }

    public var activeNotebook: ProjectNotebook? {
        notebooks.first { $0.id == selectedNotebookId }
    }

    // MARK: - Note Operations
    public func selectNote(_ id: UUID) {
        selectedNoteId = id
        if let note = notes.first(where: { $0.id == id }) {
            noteEditorText = note.content
            selectedNotebookId = note.notebookId

            // Update recents
            recentNoteIds.removeAll { $0 == id }
            recentNoteIds.insert(id, at: 0)
            recentNoteIds = Array(recentNoteIds.prefix(10))

            // Update frequently accessed
            frequentlyAccessedNoteIds[id, default: 0] += 1
            saveData()
        }
    }

    public func createNote(title: String = "Untitled Note", content: String = "", category: String = "General", notebookId: UUID? = nil) {
        let resolvedNotebookId = notebookId ?? selectedNotebookId ?? notebooks.first?.id ?? UUID()
        let newNote = ProjectNote(
            title: title,
            content: content,
            notebookId: resolvedNotebookId,
            category: category,
            tags: [],
            isPinned: false,
            isFavorite: false,
            isArchived: false,
            author: NSFullUserName()
        )
        notes.append(newNote)
        selectedNoteId = newNote.id
        noteEditorText = content
        selectedNotebookId = resolvedNotebookId
        isEditingNote = true
        saveData()
    }

    public func duplicateNote(_ note: ProjectNote) {
        let newNote = ProjectNote(
            title: "\(note.title) Copy",
            content: note.content,
            notebookId: note.notebookId,
            category: note.category,
            tags: note.tags,
            isPinned: false,
            isFavorite: false,
            isArchived: note.isArchived,
            author: NSFullUserName(),
            linkedNoteIds: note.linkedNoteIds,
            linkedFiles: note.linkedFiles,
            linkedSymbols: note.linkedSymbols,
            linkedGitCommits: note.linkedGitCommits,
            linkedBuildLogs: note.linkedBuildLogs,
            linkedDeployments: note.linkedDeployments
        )
        notes.append(newNote)
        selectNote(newNote.id)
        saveData()
    }

    public func deleteNote(_ note: ProjectNote) {
        notes.removeAll { $0.id == note.id }
        noteVersions.removeAll { $0.noteId == note.id }

        // Remove from links & backlinks
        for i in 0..<notes.count {
            notes[i].linkedNoteIds.remove(note.id)
            notes[i].backlinkNoteIds.remove(note.id)
        }

        // Physically delete .md file
        let fileURL = baseDirectoryURL.appendingPathComponent("\(note.id).md")
        try? FileManager.default.removeItem(at: fileURL)

        if selectedNoteId == note.id {
            selectedNoteId = notes.first { $0.notebookId == selectedNotebookId }?.id
            if let active = activeNote {
                noteEditorText = active.content
            } else {
                noteEditorText = ""
            }
        }
        saveData()
    }

    public func updateActiveNoteContent(_ newContent: String) {
        guard let noteIdx = notes.firstIndex(where: { $0.id == selectedNoteId }) else { return }
        notes[noteIdx].content = newContent
        notes[noteIdx].characterCount = newContent.count
        notes[noteIdx].wordCount = newContent.split { $0.isWhitespace }.count
        notes[noteIdx].readingTime = max(1, notes[noteIdx].wordCount / 200)
        notes[noteIdx].updatedAt = Date()

        // Sync backlinks automatically from double bracket tags [[Note Title]]
        syncBacklinks(for: notes[noteIdx])

        saveData()
    }

    public func saveActiveNote() {
        guard let note = activeNote else { return }
        saveCurrentVersionSnapshot(for: note)
        isEditingNote = false
        saveData()
    }

    // MARK: - Notebook Operations
    public func createNotebook(name: String) {
        let newNotebook = ProjectNotebook(name: name)
        notebooks.append(newNotebook)
        selectedNotebookId = newNotebook.id
        saveData()
    }

    public func deleteNotebook(_ notebookId: UUID) {
        notebooks.removeAll { $0.id == notebookId }
        // Orphaned notes fallback to first notebook
        if let fallbackId = notebooks.first?.id {
            for i in 0..<notes.count {
                if notes[i].notebookId == notebookId {
                    notes[i].notebookId = fallbackId
                }
            }
        }
        if selectedNotebookId == notebookId {
            selectedNotebookId = notebooks.first?.id
        }
        saveData()
    }

    // MARK: - Internal Linking & Backlinks
    private func syncBacklinks(for note: ProjectNote) {
        // Find notes that are mentioned via [[Note Title]] in content
        var targets = Set<UUID>()
        let pattern = #"\s*\[\[(.*?)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let nsRange = NSRange(note.content.startIndex..<note.content.endIndex, in: note.content)
        let matches = regex.matches(in: note.content, options: [], range: nsRange)

        for match in matches {
            guard let range = Range(match.range(at: 1), in: note.content) else { continue }
            let title = String(note.content[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let matchingNote = notes.first(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }) {
                targets.insert(matchingNote.id)
            }
        }

        // Apply links & backlinks
        guard let noteIdx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let oldTargets = notes[noteIdx].linkedNoteIds
        notes[noteIdx].linkedNoteIds = targets

        // Add backlink to target notes
        for targetId in targets {
            if let targetIdx = notes.firstIndex(where: { $0.id == targetId }) {
                notes[targetIdx].backlinkNoteIds.insert(note.id)
            }
        }

        // Remove backlink from untargeted notes
        let removedTargets = oldTargets.subtracting(targets)
        for targetId in removedTargets {
            if let targetIdx = notes.firstIndex(where: { $0.id == targetId }) {
                notes[targetIdx].backlinkNoteIds.remove(note.id)
            }
        }
    }

    public func linkNote(from noteId: UUID, to targetNoteId: UUID) {
        guard let sourceIdx = notes.firstIndex(where: { $0.id == noteId }),
              let targetIdx = notes.firstIndex(where: { $0.id == targetNoteId }) else { return }

        notes[sourceIdx].linkedNoteIds.insert(targetNoteId)
        notes[targetIdx].backlinkNoteIds.insert(noteId)
        saveData()
    }

    public func unlinkNote(from noteId: UUID, to targetNoteId: UUID) {
        guard let sourceIdx = notes.firstIndex(where: { $0.id == noteId }),
              let targetIdx = notes.firstIndex(where: { $0.id == targetNoteId }) else { return }

        notes[sourceIdx].linkedNoteIds.remove(targetNoteId)
        notes[targetIdx].backlinkNoteIds.remove(noteId)
        saveData()
    }

    // MARK: - Attachments Operations
    public func attachFile(to note: ProjectNote, fileURL: URL) {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }

        let fileManager = FileManager.default
        let ext = fileURL.pathExtension.lowercased()
        let name = fileURL.lastPathComponent
        let type: String

        switch ext {
        case "png", "jpg", "jpeg", "webp", "gif": type = "image"
        case "pdf": type = "pdf"
        case "md", "markdown": type = "markdown"
        case "txt": type = "text"
        case "json": type = "json"
        case "yaml", "yml": type = "yaml"
        case "swift": type = "swift"
        case "zip", "tar", "gz": type = "zip"
        case "mp3", "wav", "m4a": type = "audio"
        case "mp4", "mov", "webm": type = "video"
        default: type = "text"
        }

        let newAttachmentId = UUID()
        let destURL = attachmentsDirectoryURL.appendingPathComponent("\(newAttachmentId).\(ext)")

        do {
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.copyItem(at: fileURL, to: destURL)

            let attachment = NoteAttachment(
                id: newAttachmentId,
                name: name,
                type: type,
                relativePath: "attachments/\(newAttachmentId).\(ext)"
            )

            notes[idx].attachments.append(attachment)
            if selectedNoteId == note.id {
                selectedNoteId = note.id // trigger view refresh
            }
            saveData()
        } catch {
            logger.error("Failed to copy attachment file: \(error.localizedDescription)")
        }
    }

    public func deleteAttachment(_ attachment: NoteAttachment, from note: ProjectNote) {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[idx].attachments.removeAll { $0.id == attachment.id }

        let fileURL = baseDirectoryURL.appendingPathComponent(attachment.relativePath)
        try? FileManager.default.removeItem(at: fileURL)

        if selectedNoteId == note.id {
            selectedNoteId = note.id // trigger view refresh
        }
        saveData()
    }

    // MARK: - Version History Operations
    public func saveCurrentVersionSnapshot(for note: ProjectNote) {
        let snapshot = NoteVersion(noteId: note.id, content: note.content)
        noteVersions.append(snapshot)
        saveData()
    }

    public func rollbackToVersion(_ version: NoteVersion) {
        guard let noteIdx = notes.firstIndex(where: { $0.id == version.noteId }) else { return }
        notes[noteIdx].content = version.content
        noteEditorText = version.content
        notes[noteIdx].updatedAt = Date()
        saveData()
    }

    // MARK: - Saved Searches
    public func saveSearch(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if !savedSearches.contains(where: { $0.query.localizedCaseInsensitiveCompare(query) == .orderedSame }) {
            savedSearches.append(SavedSearch(query: query))
            saveData()
        }
    }

    public func deleteSavedSearch(_ search: SavedSearch) {
        savedSearches.removeAll { $0.id == search.id }
        saveData()
    }

    // MARK: - AI Action Features
    public func executeAICopilotStreaming(prompt: String, onToken: @escaping @Sendable @MainActor (String) -> Void) async {
        isAIProcessing = true
        activeAIPrompt = ""

        let currentContent = noteEditorText
        let systemPrompt = """
You are a highly skilled, world-class technical documentation assistant.
Help the developer refine, generate, format, structure, review, or summarize their markdown-based documentation.
Always return beautiful, readable, fully-commented Markdown and inline code blocks where appropriate.

Context of active note:
[START ACTIVE NOTE CONTENT]
\(currentContent)
[END ACTIVE NOTE CONTENT]
"""
        let userPrompt = prompt

        let messages = [
            AIMessage(role: .user, content: userPrompt)
        ]

        activeAIConversation.append(LocalChatMsg(isUser: true, content: prompt))

        @MainActor
        final class TokenHolder {
            var value = ""
        }
        let holder = TokenHolder()

        do {
            try await LLMService.shared.streamChat(
                messages: messages,
                model: AppSettings.shared.selectedModel.isEmpty ? "meta-llama/llama-3-70b-instruct" : AppSettings.shared.selectedModel,
                systemPrompt: systemPrompt
            ) { token in
                await MainActor.run {
                    holder.value += token
                    onToken(token)
                }
            }

            let finalTokens = await MainActor.run { holder.value }
            activeAIConversation.append(LocalChatMsg(isUser: false, content: finalTokens))
        } catch {
            let errorText = "\n[AI Error: \(error.localizedDescription)]"
            await MainActor.run { onToken(errorText) }
            activeAIConversation.append(LocalChatMsg(isUser: false, content: errorText))
        }

        isAIProcessing = false
        saveData()
    }
}
