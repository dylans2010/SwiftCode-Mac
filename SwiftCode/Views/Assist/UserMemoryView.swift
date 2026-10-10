import SwiftUI
import AppKit

public struct UserMemoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = AssistMemoryStore.shared

    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"
    @State private var isShowingAddSheet = false
    @State private var editingEntry: UserMemoryEntry? = nil

    // Editing form state
    @State private var formCategory: String = "Learned Patterns & Directives"
    @State private var formContent: String = ""

    // Raw markdown view mode
    @State private var isRawMarkdownMode = false
    @State private var rawTextDraft: String = ""
    @State private var showResetConfirmation = false
    @State private var saveStatusMessage: String? = nil

    private let availableCategories = [
        "All",
        "User Preferences & Profile",
        "Project Context",
        "Learned Patterns & Directives"
    ]

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerView
                Divider()

                if !store.isMemoryEnabled {
                    disabledStateView
                } else {
                    if isRawMarkdownMode {
                        rawMarkdownEditor
                    } else {
                        structuredEntriesView
                    }
                }
            }
            .navigationTitle("User Memory")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([store.memoryFileURL])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .help("Show UserMemory.md in Finder")
                }

                ToolbarItem(placement: .automatic) {
                    Button {
                        if isRawMarkdownMode {
                            store.saveRawContent(rawTextDraft)
                            saveStatusMessage = "Saved UserMemory.md"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                saveStatusMessage = nil
                            }
                        } else {
                            rawTextDraft = store.rawContent
                        }
                        isRawMarkdownMode.toggle()
                    } label: {
                        Label(isRawMarkdownMode ? "Structured View" : "Edit Raw Markdown",
                              systemImage: isRawMarkdownMode ? "list.bullet" : "doc.text")
                    }
                    .disabled(!store.isMemoryEnabled)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingAddSheet) {
                addEntrySheet
            }
            .sheet(item: $editingEntry) { entry in
                editEntrySheet(for: entry)
            }
            .confirmationDialog("Reset Memory to Template?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
                Button("Reset to Default Template", role: .destructive) {
                    store.resetToTemplate()
                    rawTextDraft = store.rawContent
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will replace your existing UserMemory.md with the default template. This action cannot be undone.")
            }
            .onAppear {
                store.reload()
                rawTextDraft = store.rawContent
            }
        }
        .frame(minWidth: 620, minHeight: 520)
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        Text("Assist Memory")
                            .font(.title2.weight(.bold))
                    }
                    Text("Persistent developer preferences, learned patterns, and project directives saved in UserMemory.md.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle(isOn: Bindable(store).isMemoryEnabled) {
                    Text(store.isMemoryEnabled ? "Memory Active" : "Memory Off")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(store.isMemoryEnabled ? .primary : .secondary)
                }
                .toggleStyle(.switch)
            }

            if let saveStatusMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(saveStatusMessage)
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Disabled State View

    private var disabledStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "brain.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Memory Module is Disabled")
                .font(.title3.weight(.semibold))

            Text("Assist will not remember preferences or capture details while Memory is switched off.\nAny tool requests to retrieve or manage memory will return \"User has Memory module OFF.\".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            Button {
                store.isMemoryEnabled = true
            } label: {
                Text("Enable Assist Memory")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)

            Spacer()
        }
        .padding(24)
    }

    // MARK: - Structured View

    private var structuredEntriesView: some View {
        VStack(spacing: 0) {
            // Controls bar: Search & Category filter & Add button
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search memory entries...", text: $searchText)
                        .textFieldStyle(.plain)
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
                .padding(6)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                Picker("Category", selection: $selectedCategory) {
                    ForEach(availableCategories, id: \.self) { cat in
                        Text(cat).tag(cat)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 160)

                Button {
                    formCategory = "Learned Patterns & Directives"
                    formContent = ""
                    isShowingAddSheet = true
                } label: {
                    Label("Add Entry", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.03))

            Divider()

            if filteredEntries.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty ? "No memory entries found in UserMemory.md" : "No entries matching \"\(searchText)\"")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Button {
                        isShowingAddSheet = true
                    } label: {
                        Text("Add New Memory Entry")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groupedCategories, id: \.self) { category in
                        Section(header: Text(category).font(.caption.weight(.semibold)).foregroundStyle(.secondary)) {
                            ForEach(entries(for: category)) { entry in
                                entryRow(entry)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // Footer Bar
            HStack {
                Text("\(store.entries.count) total entries recorded")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Reset to Default Template", role: .destructive) {
                    showResetConfirmation = true
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.red)

                Button {
                    store.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Reload from disk")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.thinMaterial)
        }
    }

    private func entryRow(_ entry: UserMemoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconForCategory(entry.category))
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.content)
                    .font(.body)
                    .textSelection(.enabled)
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    editingEntry = entry
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Edit entry")

                Button {
                    store.deleteEntry(id: entry.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Delete entry")
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Raw Markdown Editor

    private var rawMarkdownEditor: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Direct Markdown Editor: UserMemory.md")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save Changes") {
                    store.saveRawContent(rawTextDraft)
                    saveStatusMessage = "Successfully updated UserMemory.md"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        saveStatusMessage = nil
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.thinMaterial)

            Divider()

            TextEditor(text: $rawTextDraft)
                .font(.system(.body, design: .monospaced))
                .padding(12)
        }
    }

    // MARK: - Add Entry Sheet

    private var addEntrySheet: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Category", selection: $formCategory) {
                        Text("User Preferences & Profile").tag("User Preferences & Profile")
                        Text("Project Context").tag("Project Context")
                        Text("Learned Patterns & Directives").tag("Learned Patterns & Directives")
                        Text("General").tag("General")
                    }
                    .pickerStyle(.menu)
                }

                Section("Memory Content") {
                    TextEditor(text: $formContent)
                        .frame(minHeight: 100)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Memory Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingAddSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let clean = formContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clean.isEmpty {
                            store.addEntry(category: formCategory, content: clean)
                        }
                        isShowingAddSheet = false
                    }
                    .disabled(formContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(minWidth: 420, minHeight: 280)
        }
    }

    // MARK: - Edit Entry Sheet

    private func editEntrySheet(for entry: UserMemoryEntry) -> some View {
        EditEntryModal(entry: entry) { newContent in
            store.updateEntry(id: entry.id, newContent: newContent)
        }
    }

    // MARK: - Helpers

    private var filteredEntries: [UserMemoryEntry] {
        var items = store.entries
        if selectedCategory != "All" {
            items = items.filter { $0.category.caseInsensitiveCompare(selectedCategory) == .orderedSame }
        }
        if !searchText.isEmpty {
            let lower = searchText.lowercased()
            items = items.filter { $0.content.lowercased().contains(lower) || $0.category.lowercased().contains(lower) }
        }
        return items
    }

    private var groupedCategories: [String] {
        let cats = Set(filteredEntries.map { $0.category })
        return Array(cats).sorted()
    }

    private func entries(for category: String) -> [UserMemoryEntry] {
        filteredEntries.filter { $0.category == category }
    }

    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "User Preferences & Profile":
            return "person.crop.circle"
        case "Project Context":
            return "folder.badge.gearshape"
        case "Learned Patterns & Directives":
            return "lightbulb"
        default:
            return "bubble.left.and.text.bubble.right"
        }
    }
}

// MARK: - Edit Entry Modal

private struct EditEntryModal: View {
    let entry: UserMemoryEntry
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var content: String = ""

    init(entry: UserMemoryEntry, onSave: @escaping (String) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _content = State(initialValue: entry.content)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Text(entry.category)
                        .foregroundStyle(.secondary)
                }

                Section("Edit Memory Entry") {
                    TextEditor(text: $content)
                        .frame(minHeight: 120)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clean.isEmpty {
                            onSave(clean)
                        }
                        dismiss()
                    }
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(minWidth: 420, minHeight: 280)
        }
    }
}
