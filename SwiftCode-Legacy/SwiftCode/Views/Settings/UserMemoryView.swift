//
//  UserMemoryView.swift
//  SwiftCode
//
//  Settings and manual management interface for UserMemory.md.
//  Enables developers to view, search, add, edit, and delete durable context memories.
//

import SwiftUI
import AppKit

public struct UserMemoryView: View {
    @ObservedObject private var memoryManager = UserMemoryManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var editingEntry: UserMemoryEntry? = nil

    // Add entry sheet state
    @State private var newKey = ""
    @State private var newValue = ""
    @State private var newCategory = "Preferences"

    public init() {}

    private var filteredEntries: [UserMemoryEntry] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return memoryManager.entries
        } else {
            return memoryManager.search(query: searchText)
        }
    }

    private var groupedEntries: [String: [UserMemoryEntry]] {
        Dictionary(grouping: filteredEntries, by: { $0.category })
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Assist Memory (UserMemory.md)")
                        .font(.headline)
                    Text("Durable knowledge, preferences, and project decisions remembered across sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    NSWorkspace.shared.selectFile(memoryManager.memoryFileURL.path, inFileViewerRootedAtPath: memoryManager.memoryDirectoryURL.path)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    newKey = ""
                    newValue = ""
                    newCategory = "Preferences"
                    showingAddSheet = true
                } label: {
                    Label("Add Memory", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            // Search Bar & Stats
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Search memory entries...", text: $searchText)
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
                .liquidGlass(style: .subtle, cornerRadius: 8)

                Spacer()

                Text("\(filteredEntries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // List of Entries
            if memoryManager.entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "brain")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text("No Memories Stored")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Assist automatically records valuable technical requirements, preferences, and architectural guidelines, or you can add them manually above.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No matching memory items")
                        .font(.headline)
                    Text("Try adjusting your search query.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(groupedEntries.keys.sorted(), id: \.self) { category in
                        Section(header: Text(category).font(.caption.weight(.bold))) {
                            if let items = groupedEntries[category] {
                                ForEach(items) { item in
                                    memoryRow(item)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 540, minHeight: 450)
        .sheet(isPresented: $showingAddSheet) {
            addEntrySheet
        }
        .sheet(item: $editingEntry) { entry in
            editEntrySheet(entry)
        }
    }

    @ViewBuilder
    private func memoryRow(_ item: UserMemoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.key)
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(item.category)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.purple.opacity(0.12), in: Capsule())
                        .foregroundStyle(.purple)
                }

                Text(item.value)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            Button {
                editingEntry = item
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Edit Memory")

            Button {
                memoryManager.deleteMemory(key: item.key)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Memory")
        }
        .padding(.vertical, 4)
    }

    private var addEntrySheet: some View {
        NavigationStack {
            Form {
                Section("Memory Details") {
                    TextField("Key (e.g. DesignTokens, StrictConcurrency, TestTarget)", text: $newKey)
                    TextField("Value / Knowledge (e.g. Always use SwiftUI NavigationStack)", text: $newValue, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Category (e.g. Preferences, Architecture, Rules)", text: $newCategory)
                }
            }
            .navigationTitle("Add Memory")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        memoryManager.saveMemory(key: newKey, value: newValue, category: newCategory)
                        showingAddSheet = false
                    }
                    .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(minWidth: 400, minHeight: 280)
        }
    }

    private func editEntrySheet(_ entry: UserMemoryEntry) -> some View {
        EditMemorySheetView(entry: entry, onSave: { key, val, cat in
            memoryManager.saveMemory(key: key, value: val, category: cat)
            editingEntry = nil
        }, onCancel: {
            editingEntry = nil
        })
    }
}

private struct EditMemorySheetView: View {
    let entry: UserMemoryEntry
    let onSave: (String, String, String) -> Void
    let onCancel: () -> Void

    @State private var key: String
    @State private var value: String
    @State private var category: String

    init(entry: UserMemoryEntry, onSave: @escaping (String, String, String) -> Void, onCancel: @escaping () -> Void) {
        self.entry = entry
        self.onSave = onSave
        self.onCancel = onCancel
        _key = State(initialValue: entry.key)
        _value = State(initialValue: entry.value)
        _category = State(initialValue: entry.category)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Edit Memory Entry") {
                    TextField("Key", text: $key)
                        .disabled(true) // Key is identity
                    TextField("Value", text: $value, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Category", text: $category)
                }
            }
            .navigationTitle("Edit Memory")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(key, value, category)
                    }
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(minWidth: 400, minHeight: 280)
        }
    }
}
