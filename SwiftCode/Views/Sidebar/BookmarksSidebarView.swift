import SwiftUI

struct BookmarksSidebarView: View {
    @State private var store = BookmarkStore.shared
    @Environment(WorkspaceViewModel.self) private var workspaceViewModel

    @State private var searchText = ""
    @State private var selectedBookmarkIDs = Set<UUID>()
    @State private var showCreateSheet = false
    @State private var editingBookmark: Bookmark? = nil

    // Collapsed state for folders
    @State private var collapsedFolders = Set<String>()

    var filteredBookmarks: [Bookmark] {
        if searchText.isEmpty {
            return store.bookmarks
        } else {
            return store.bookmarks.filter { b in
                b.fileName.localizedCaseInsensitiveContains(searchText) ||
                (b.title ?? "").localizedCaseInsensitiveContains(searchText) ||
                (b.folder ?? "").localizedCaseInsensitiveContains(searchText) ||
                (b.notes ?? "").localizedCaseInsensitiveContains(searchText) ||
                (b.url ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    // Group bookmarks by Folder
    var folderGroups: [String: [Bookmark]] {
        Dictionary(grouping: filteredBookmarks) { b in
            let f = b.folder?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return f.isEmpty ? "General" : f
        }
    }

    var sortedFolders: [String] {
        folderGroups.keys.sorted { f1, f2 in
            if f1 == "General" { return true }
            if f2 == "General" { return false }
            return f1.localizedStandardCompare(f2) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar & Action Buttons
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Search bookmarks...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .help("Create New Bookmark")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()

            if store.bookmarks.isEmpty {
                ContentUnavailableView("No Bookmarks", systemImage: "bookmark", description: Text("Add bookmarks to quickly jump to files, URLs, or important lines of code."))
            } else {
                List(selection: $selectedBookmarkIDs) {
                    ForEach(sortedFolders, id: \.self) { folder in
                        let bookmarksInFolder = folderGroups[folder] ?? []

                        Section(header: HStack {
                            Image(systemName: "folder.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text(folder.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                if collapsedFolders.contains(folder) {
                                    collapsedFolders.remove(folder)
                                } else {
                                    collapsedFolders.insert(folder)
                                }
                            } label: {
                                Image(systemName: collapsedFolders.contains(folder) ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }) {
                            if !collapsedFolders.contains(folder) {
                                ForEach(bookmarksInFolder) { bookmark in
                                    bookmarkRow(for: bookmark)
                                        .tag(bookmark.id)
                                        .contextMenu {
                                            bookmarkContextMenu(for: bookmark)
                                        }
                                }
                                .onMove { indices, newOffset in
                                    store.reorder(fromOffsets: indices, toOffset: newOffset)
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .onDeleteCommand {
                    deleteSelectedBookmarks()
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateNewBookmark { title, url, folder, icon, notes in
                store.add(
                    fileName: title.isEmpty ? "Bookmark" : title,
                    lineNumber: 1,
                    filePath: "",
                    title: title,
                    url: url.isEmpty ? nil : url,
                    folder: folder.isEmpty ? nil : folder,
                    icon: icon.isEmpty ? nil : icon,
                    notes: notes.isEmpty ? nil : notes
                )
                showCreateSheet = false
            }
        }
        .sheet(item: $editingBookmark) { b in
            EditBookmarkSheet(bookmark: b) { updated in
                store.update(updated)
                editingBookmark = nil
            }
        }
    }

    @ViewBuilder
    private func bookmarkRow(for bookmark: Bookmark) -> some View {
        HStack(spacing: 10) {
            Image(systemName: bookmark.icon ?? "bookmark.fill")
                .foregroundColor(.blue)
                .font(.headline)

            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.title ?? bookmark.fileName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                if let urlStr = bookmark.url, !urlStr.isEmpty {
                    Text(urlStr)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                } else if !bookmark.filePath.isEmpty {
                    Text("\(bookmark.fileName) • Line \(bookmark.lineNumber)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let notes = bookmark.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            triggerBookmark(bookmark)
        }
    }

    @ViewBuilder
    private func bookmarkContextMenu(for bookmark: Bookmark) -> some View {
        Button {
            triggerBookmark(bookmark)
        } label: {
            Label("Open / Jump", systemImage: "arrow.up.right.square")
        }

        Button {
            editingBookmark = bookmark
        } label: {
            Label("Rename & Edit", systemImage: "pencil")
        }

        Button {
            store.duplicate(bookmark)
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            store.remove(id: bookmark.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func triggerBookmark(_ bookmark: Bookmark) {
        if let urlStr = bookmark.url, let urlObj = URL(string: urlStr.hasPrefix("http") ? urlStr : "https://\(urlStr)") {
            NSWorkspace.shared.open(urlObj)
        } else if !bookmark.filePath.isEmpty {
            let fileURL = workspaceViewModel.projectURL.appendingPathComponent(bookmark.filePath)
            Task {
                await workspaceViewModel.editor.openFile(url: fileURL)
            }
        }
    }

    private func deleteSelectedBookmarks() {
        for id in selectedBookmarkIDs {
            store.remove(id: id)
        }
        selectedBookmarkIDs.removeAll()
    }
}

// MARK: - CreateNewBookmark Sheet

struct CreateNewBookmark: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var url = ""
    @State private var folder = ""
    @State private var icon = "bookmark.fill"
    @State private var notes = ""

    let onSave: (String, String, String, String, String) -> Void

    let availableIcons = ["bookmark.fill", "link", "doc.text.fill", "star.fill", "heart.fill", "tag.fill", "globe", "phone.fill", "envelope.fill", "house.fill"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Bookmark Info") {
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)

                    TextField("URL (Optional)", text: $url)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()

                    TextField("Folder (Optional, e.g. Design)", text: $folder)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Icon & Appearance") {
                    Picker("Icon", selection: $icon) {
                        ForEach(availableIcons, id: \.self) { iconName in
                            HStack {
                                Image(systemName: iconName)
                                Text(iconName)
                            }.tag(iconName)
                        }
                    }
                }

                Section("Developer Notes") {
                    TextEditor(text: $notes)
                        .frame(height: 60)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15)))
                }
            }
            .padding()
            .navigationTitle("New Bookmark")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title, url, folder, icon, notes)
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
        .frame(width: 450, height: 400)
    }
}

// MARK: - EditBookmarkSheet

struct EditBookmarkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var bookmark: Bookmark

    let onSave: (Bookmark) -> Void
    let availableIcons = ["bookmark.fill", "link", "doc.text.fill", "star.fill", "heart.fill", "tag.fill", "globe", "phone.fill", "envelope.fill", "house.fill"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Bookmark Details") {
                    TextField("Title", text: Binding(
                        get: { bookmark.title ?? bookmark.fileName },
                        set: { bookmark.title = $0; bookmark.fileName = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    TextField("URL", text: Binding(
                        get: { bookmark.url ?? "" },
                        set: { bookmark.url = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                    TextField("Folder", text: Binding(
                        get: { bookmark.folder ?? "" },
                        set: { bookmark.folder = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                Section("Icon") {
                    Picker("Icon", selection: Binding(
                        get: { bookmark.icon ?? "bookmark.fill" },
                        set: { bookmark.icon = $0 }
                    )) {
                        ForEach(availableIcons, id: \.self) { iconName in
                            HStack {
                                Image(systemName: iconName)
                                Text(iconName)
                            }.tag(iconName)
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: Binding(
                        get: { bookmark.notes ?? "" },
                        set: { bookmark.notes = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(height: 60)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15)))
                }
            }
            .padding()
            .navigationTitle("Edit Bookmark")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(bookmark)
                    }
                }
            }
        }
        .frame(width: 450, height: 400)
    }
}
