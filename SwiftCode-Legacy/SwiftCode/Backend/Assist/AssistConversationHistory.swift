//
//  AssistConversationHistory.swift
//  SwiftCode
//
//  Persistent history manager for Assist conversations.
//  Maintains multi-session conversation index, context files (<id>.context.md),
//  and reviews conversations with Apple Foundation Models for intelligent auto-titling.
//

import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistConversationHistory")

public struct ConversationItem: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var updatedAt: Date
    public var isArchived: Bool
    public var messageCount: Int
    public var previewSnippet: String
    public var contextFilePath: String
    public var contextFileURL: URL? {
        contextFilePath.isEmpty ? nil : URL(fileURLWithPath: contextFilePath)
    }

    public init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false,
        messageCount: Int = 0,
        previewSnippet: String = "",
        contextFilePath: String = ""
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.messageCount = messageCount
        self.previewSnippet = previewSnippet
        self.contextFilePath = contextFilePath
    }
}

@MainActor
public final class AssistConversationHistory: ObservableObject {
    public static let shared = AssistConversationHistory()

    @Published public private(set) var conversations: [ConversationItem] = []
    @Published public var activeConversationID: UUID? = nil

    private let fileManager = FileManager.default

    public var baseDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SwiftCode/Conversations", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var indexFileURL: URL {
        baseDirectoryURL.appendingPathComponent("index.json")
    }

    private init() {
        loadIndex()
    }

    public var activeConversations: [ConversationItem] {
        conversations.filter { !$0.isArchived }.sorted { $0.updatedAt > $1.updatedAt }
    }

    public var archivedConversations: [ConversationItem] {
        conversations.filter { $0.isArchived }.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func listConversations() -> [ConversationItem] {
        activeConversations
    }

    // MARK: - Conversation Lifecycle

    public func startNewConversation() -> ConversationItem {
        let id = UUID()
        let contextFile = baseDirectoryURL.appendingPathComponent("\(id.uuidString).context.md")

        let initialContext = """
        # Conversation Context: New Conversation
        - **ID**: \(id.uuidString)
        - **Created**: \(ISO8601DateFormatter().string(from: Date()))
        - **Status**: Active
        - **Summary**: Fresh conversation session.
        """
        try? initialContext.write(to: contextFile, atomically: true, encoding: .utf8)

        let item = ConversationItem(
            id: id,
            title: "New Conversation",
            createdAt: Date(),
            updatedAt: Date(),
            isArchived: false,
            messageCount: 0,
            previewSnippet: "",
            contextFilePath: contextFile.path
        )

        conversations.insert(item, at: 0)
        activeConversationID = id
        saveIndex()
        return item
    }

    public func saveMessages(conversationId: UUID, messages: [AssistMessage]) async {
        guard !messages.isEmpty else { return }

        let folder = baseDirectoryURL.appendingPathComponent(conversationId.uuidString, isDirectory: true)
        if !fileManager.fileExists(atPath: folder.path) {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        let messagesFile = folder.appendingPathComponent("messages.json")
        if let data = try? JSONEncoder().encode(messages) {
            try? data.write(to: messagesFile)
        }

        let firstUserMsg = messages.first(where: { $0.role == .user })?.content ?? ""
        let preview = String(firstUserMsg.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)

        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].updatedAt = Date()
            conversations[idx].messageCount = messages.count
            conversations[idx].previewSnippet = preview

            // If the conversation title is still default, review with Apple Foundation Models!
            if (conversations[idx].title == "New Conversation" || conversations[idx].title.isEmpty) && !firstUserMsg.isEmpty {
                let currentId = conversationId
                Task {
                    await reviewAndTitleConversation(id: currentId, firstMessage: firstUserMsg)
                }
            }
        } else {
            let contextFile = baseDirectoryURL.appendingPathComponent("\(conversationId.uuidString).context.md")
            let item = ConversationItem(
                id: conversationId,
                title: "New Conversation",
                createdAt: Date(),
                updatedAt: Date(),
                isArchived: false,
                messageCount: messages.count,
                previewSnippet: preview,
                contextFilePath: contextFile.path
            )
            conversations.insert(item, at: 0)
            let currentId = conversationId
            Task {
                await reviewAndTitleConversation(id: currentId, firstMessage: firstUserMsg)
            }
        }

        updateContextFile(conversationId: conversationId, messages: messages)
        saveIndex()
    }

    public func loadMessages(conversationId: UUID) -> [AssistMessage]? {
        let folder = baseDirectoryURL.appendingPathComponent(conversationId.uuidString, isDirectory: true)
        let messagesFile = folder.appendingPathComponent("messages.json")
        guard let data = try? Data(contentsOf: messagesFile) else { return nil }
        return try? JSONDecoder().decode([AssistMessage].self, from: data)
    }

    public func renameConversation(id: UUID, newTitle: String) {
        let clean = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].title = clean
        conversations[idx].updatedAt = Date()
        saveIndex()
        objectWillChange.send()
    }

    public func archiveConversation(id: UUID, archive: Bool = true) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].isArchived = archive
        conversations[idx].updatedAt = Date()
        saveIndex()
        objectWillChange.send()
    }

    public func deleteConversation(id: UUID) {
        conversations.removeAll(where: { $0.id == id })
        let folder = baseDirectoryURL.appendingPathComponent(id.uuidString, isDirectory: true)
        try? fileManager.removeItem(at: folder)
        let contextFile = baseDirectoryURL.appendingPathComponent("\(id.uuidString).context.md")
        try? fileManager.removeItem(at: contextFile)
        if activeConversationID == id {
            activeConversationID = activeConversations.first?.id
        }
        saveIndex()
        objectWillChange.send()
    }

    // MARK: - Apple Foundation Models Review

    public func reviewAndTitleConversation(id: UUID, firstMessage: String) async {
        let prompt = """
        Review this user request to an AI coding assistant and generate a very short, concise title (under 25 characters, 2 to 4 words).
        Do not use quotation marks, do not include any preamble, output ONLY the title:

        User Request:
        \(firstMessage)
        """

        var generatedTitle: String? = nil
        do {
            let response = try await FoundationModels.shared.generatePrivateResponse(prompt: prompt)
            let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "\n", with: " ")
            if !cleaned.isEmpty {
                if cleaned.count < 25 {
                    generatedTitle = cleaned
                } else {
                    generatedTitle = FoundationModels.generateConciseTitle(from: cleaned)
                }
            }
        } catch {
            logger.info("Apple Foundation Models review fallback: \(error.localizedDescription)")
        }

        if generatedTitle == nil || generatedTitle?.isEmpty == true {
            generatedTitle = FoundationModels.generateConciseTitle(from: firstMessage)
        }

        if let finalTitle = generatedTitle, !finalTitle.isEmpty {
            let sanitized = String(finalTitle.prefix(24)).trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                if let idx = self.conversations.firstIndex(where: { $0.id == id }) {
                    self.conversations[idx].title = sanitized
                    self.saveIndex()
                    self.objectWillChange.send()
                }
            }
        }
    }

    /// Generates and assigns an AI-suggested title under 25 characters for a conversation using AFM.
    @discardableResult
    public func suggestName(for id: UUID) async -> String? {
        guard let item = conversations.first(where: { $0.id == id }) else { return nil }
        var sampleText = item.previewSnippet
        if let msgs = loadMessages(conversationId: id) {
            if let userMsg = msgs.first(where: { $0.role == .user && !$0.content.isEmpty }) {
                sampleText = userMsg.content
            }
        }
        if sampleText.isEmpty {
            sampleText = item.title
        }

        let prompt = """
        Review this user request to an AI coding assistant and generate a very short, concise title (under 25 characters, 2 to 4 words).
        Do not use quotation marks, do not include preamble, output ONLY the title:

        User Request:
        \(sampleText)
        """

        var suggested: String? = nil
        do {
            let response = try await FoundationModels.shared.generatePrivateResponse(prompt: prompt)
            let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "\n", with: " ")
            if !cleaned.isEmpty {
                if cleaned.count < 25 {
                    suggested = cleaned
                } else {
                    suggested = FoundationModels.generateConciseTitle(from: cleaned)
                }
            }
        } catch {
            logger.info("AFM suggest name fallback: \(error.localizedDescription)")
        }

        if suggested == nil || suggested?.isEmpty == true {
            suggested = FoundationModels.generateConciseTitle(from: sampleText)
        }

        if let final = suggested, !final.isEmpty {
            let sanitized = String(final.prefix(24)).trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                self.renameConversation(id: id, newTitle: sanitized)
            }
            return sanitized
        }
        return nil
    }

    private func updateContextFile(conversationId: UUID, messages: [AssistMessage]) {
        let contextFile = baseDirectoryURL.appendingPathComponent("\(conversationId.uuidString).context.md")
        let title = conversations.first(where: { $0.id == conversationId })?.title ?? "Conversation"

        var summary = "# Conversation Context: \(title)\n\n"
        summary += "- **Conversation ID**: \(conversationId.uuidString)\n"
        summary += "- **Last Updated**: \(ISO8601DateFormatter().string(from: Date()))\n"
        summary += "- **Message Count**: \(messages.count)\n\n"
        summary += "## Discussion Outline\n\n"

        for (i, m) in messages.prefix(10).enumerated() {
            let role = m.role == .user ? "User" : "Assist"
            let snippet = String(m.content.prefix(150)).replacingOccurrences(of: "\n", with: " ")
            if !snippet.isEmpty {
                summary += "\(i + 1). **\(role)**: \(snippet)\n"
            }
        }

        try? summary.write(to: contextFile, atomically: true, encoding: .utf8)
    }

    // MARK: - Index Persistence

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(conversations) {
            try? data.write(to: indexFileURL)
        }
    }

    private func loadIndex() {
        guard fileManager.fileExists(atPath: indexFileURL.path),
              let data = try? Data(contentsOf: indexFileURL),
              let items = try? JSONDecoder().decode([ConversationItem].self, from: data) else {
            return
        }
        self.conversations = items
        if activeConversationID == nil {
            activeConversationID = activeConversations.first?.id
        }
    }
}
