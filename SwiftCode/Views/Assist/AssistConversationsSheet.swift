//
//  AssistConversationsSheet.swift
//  SwiftCode
//
//  Sheet interface displaying conversation history with search, renaming,
//  archiving, deletion, and context file inspection.
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
                // Search and Filter Bar
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Search conversation history...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.subheadline)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                    Picker("Filter", selection: $selectedTab) {
                        ForEach(Tab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)

                Divider()

                // List
                if filteredConversations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text(selectedTab == .active ? "No Active Conversations" : "No Archived Conversations")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Every chat is automatically saved and reviewed by Apple Foundation Models.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List {
                        ForEach(filteredConversations) { item in
                            conversationRow(item)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Conversations History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let newConv = history.startNewConversation()
                        manager.clearChat()
                        dismiss()
                    } label: {
                        Label("New Chat", systemImage: "plus")
                    }
                }
            }
            .frame(minWidth: 540, minHeight: 450)
            .sheet(item: $editingConversation) { item in
                renameSheet(item)
            }
        }
    }

    @ViewBuilder
    private func conversationRow(_ item: ConversationItem) -> some View {
        Button {
            loadConversation(item)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.isArchived ? "archivebox" : "bubble.left.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(item.id == history.activeConversationID ? Color.accentColor : Color.secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        if item.id == history.activeConversationID {
                            Text("ACTIVE")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    if !item.previewSnippet.isEmpty {
                        Text(item.previewSnippet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        Text("\(item.messageCount) messages")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)

                        Text("·")
                            .foregroundStyle(.tertiary)

                        Text(item.updatedAt, style: .relative)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename...") {
                newTitleText = item.title
                editingConversation = item
            }

            Button(item.isArchived ? "Unarchive" : "Archive") {
                history.archiveConversation(id: item.id, archive: !item.isArchived)
            }

            Button("Show Context File") {
                let url = URL(fileURLWithPath: item.contextFilePath)
                if FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }

            Divider()

            Button("Delete", role: .destructive) {
                history.deleteConversation(id: item.id)
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
                Section("Conversation Title") {
                    TextField("Title", text: $newTitleText)
                }
            }
            .navigationTitle("Rename Conversation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingConversation = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        history.renameConversation(id: item.id, newTitle: newTitleText)
                        editingConversation = nil
                    }
                    .disabled(newTitleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(minWidth: 350, minHeight: 180)
            .padding()
        }
    }
}
