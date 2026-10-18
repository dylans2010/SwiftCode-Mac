//
//  AssistConversationsSheet.swift
//  SwiftCode
//
//  Clean, modern interface displaying conversation history with search,
//  AFM auto-titling, name suggestion (<25 chars), archiving, deletion, and context inspection.
//

import SwiftUI
import AppKit

public struct AssistConversationsSheet: View {
    @ObservedObject private var history = AssistConversationHistory.shared
    @ObservedObject private var manager = AssistManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedTab: Tab = .active
    @State private var editingConversation: ConversationItem? = nil
    @State private var newTitleText = ""
    @State private var suggestingConversationID: UUID? = nil
    @State private var hoveredConversationID: UUID? = nil

    public enum Tab: String, CaseIterable, Identifiable {
        case active = "Active"
        case archived = "Archived"
        public var id: String { rawValue }
    }

    public init() {}

    private var filteredConversations: [ConversationItem] {
        let base = selectedTab == .active ? history.activeConversations : history.archivedConversations
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.title.lowercased().contains(q) ||
            $0.previewSnippet.lowercased().contains(q)
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Sleek Top Controls Bar
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)

                            TextField("Search conversations...", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))

                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.8)
                        )

                        Picker("Category", selection: $selectedTab) {
                            Text("Active (\(history.activeConversations.count))").tag(Tab.active)
                            Text("Archived (\(history.archivedConversations.count))").tag(Tab.archived)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)

                Divider()

                // Content Area
                if filteredConversations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: selectedTab == .active ? "bubble.left.and.bubble.right" : "archivebox")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(.secondary.opacity(0.45))

                        Text(selectedTab == .active ? "No Active Conversations" : "No Archived Conversations")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text("Chats are saved and reviewed by Apple Foundation Models for instant indexing.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 280)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredConversations) { item in
                                conversationCard(item)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let newConv = history.startNewConversation()
                        manager.clearChat()
                        history.activeConversationID = newConv.id
                        dismiss()
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                }
            }
            .frame(minWidth: 500, minHeight: 420)
            .sheet(item: $editingConversation) { item in
                renameSheet(item)
            }
        }
    }

    // MARK: - Conversation Card

    @ViewBuilder
    private func conversationCard(_ item: ConversationItem) -> some View {
        let isActive = item.id == history.activeConversationID
        let isHovered = hoveredConversationID == item.id
        let isSuggesting = suggestingConversationID == item.id

        Button {
            loadConversation(item)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                // Status / Kind Icon
                ZStack {
                    Circle()
                        .fill(isActive ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
                        .frame(width: 30, height: 30)

                    if isSuggesting {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: item.isArchived ? "archivebox.fill" : (isActive ? "sparkles" : "bubble.left.fill"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    }
                }
                .padding(.top, 2)

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if isActive {
                            Text("ACTIVE")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.accentColor.opacity(0.18), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }

                        Spacer()

                        // Relative timestamp
                        Text(item.updatedAt, style: .relative)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    if !item.previewSnippet.isEmpty {
                        Text(item.previewSnippet)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    HStack(spacing: 10) {
                        Label("\(item.messageCount) msgs", systemImage: "bubble.left")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)

                        if !item.contextFilePath.isEmpty {
                            Label("Context file", systemImage: "doc.text")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isActive ? Color.accentColor.opacity(0.08) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isActive ? Color.accentColor.opacity(0.35) : (isHovered ? Color.primary.opacity(0.10) : Color.primary.opacity(0.04)), lineWidth: 0.8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { h in
            hoveredConversationID = h ? item.id : nil
        }
        .contextMenu {
            Button {
                newTitleText = item.title
                editingConversation = item
            } label: {
                Label("Rename...", systemImage: "pencil")
            }

            Button {
                triggerSuggestName(for: item)
            } label: {
                Label("Suggest Name", systemImage: "sparkles")
            }

            Button {
                history.archiveConversation(id: item.id, archive: !item.isArchived)
            } label: {
                Label(item.isArchived ? "Unarchive" : "Archive", systemImage: item.isArchived ? "tray.and.arrow.up" : "archivebox")
            }

            Button {
                let url = URL(fileURLWithPath: item.contextFilePath)
                if FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } label: {
                Label("Show Context File", systemImage: "doc.text.magnifyingglass")
            }

            Divider()

            Button(role: .destructive) {
                history.deleteConversation(id: item.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func triggerSuggestName(for item: ConversationItem) {
        suggestingConversationID = item.id
        Task {
            _ = await history.suggestName(for: item.id)
            await MainActor.run {
                suggestingConversationID = nil
            }
        }
    }

    private func loadConversation(_ item: ConversationItem) {
        if let saved = history.loadMessages(conversationId: item.id) {
            manager.messages = saved
            history.activeConversationID = item.id
            dismiss()
        }
    }

    private func renameSheet(_ item: ConversationItem) -> some View {
        NavigationStack {
            Form {
                Section("Conversation Title (under 25 chars)") {
                    HStack {
                        TextField("Title", text: $newTitleText)
                            .font(.system(size: 13))

                        Button {
                            Task {
                                if let suggested = await history.suggestName(for: item.id) {
                                    await MainActor.run {
                                        newTitleText = suggested
                                    }
                                }
                            }
                        } label: {
                            Label("Suggest with AFM", systemImage: "sparkles")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Rename Conversation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingConversation = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = String(newTitleText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
                        history.renameConversation(id: item.id, newTitle: trimmed)
                        editingConversation = nil
                    }
                    .disabled(newTitleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(minWidth: 400, minHeight: 180)
        }
    }
}
