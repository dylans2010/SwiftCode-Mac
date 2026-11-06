import SwiftUI

/// Ported from SwiftCode-Legacy `SwiftCode/Views/GitHub/RepositoryExplorerView.swift`
/// (Dylan's own code; direct port authorised under MIT).
///
/// The missing slice of the repository explorer: custom collections,
/// favorites, pinned, and archived repositories, with a manage-collections
/// sheet.
///
/// Legacy kept these in un-persisted `@State` (`favorites` / `pinned` /
/// `archived` sets and a `customCollections` dictionary keyed by project
/// name, seeded with Personal / Work / Archived). This port persists them
/// in UserDefaults through `RepositoryCollectionStore`, keyed by the
/// project's path so renames don't lose the metadata.
///
/// The destination's project list lives in the Organizer
/// (`RecentProjects` / `ProjectRegistryStore`); this view is driven by a
/// lightweight `RepositoryCollectionProject` list the host maps from its
/// own model, so it does not depend on the Organizer's types.
///
/// Hook: host beside the Organizer / welcome window's project list, or as
/// the explorer sidebar when the repository browser is built out.
@MainActor
public final class RepositoryCollectionStore: ObservableObject {
    @Published public private(set) var favorites: Set<String> = []
    @Published public private(set) var pinned: Set<String> = []
    @Published public private(set) var archived: Set<String> = []
    @Published public private(set) var customCollections: [String: Set<String>] = [:]

    private static let favoritesKey = "swiftcode.repoCollections.favorites"
    private static let pinnedKey = "swiftcode.repoCollections.pinned"
    private static let archivedKey = "swiftcode.repoCollections.archived"
    private static let collectionsKey = "swiftcode.repoCollections.custom"

    public init() {
        let defaults = UserDefaults.standard
        favorites = Set(defaults.stringArray(forKey: Self.favoritesKey) ?? [])
        pinned = Set(defaults.stringArray(forKey: Self.pinnedKey) ?? [])
        archived = Set(defaults.stringArray(forKey: Self.archivedKey) ?? [])
        if let data = defaults.data(forKey: Self.collectionsKey),
           let decoded = try? JSONDecoder().decode([String: Set<String>].self, from: data) {
            customCollections = decoded
        } else {
            customCollections = ["Personal": [], "Work": [], "Archived": []]
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(Array(favorites), forKey: Self.favoritesKey)
        defaults.set(Array(pinned), forKey: Self.pinnedKey)
        defaults.set(Array(archived), forKey: Self.archivedKey)
        if let data = try? JSONEncoder().encode(customCollections) {
            defaults.set(data, forKey: Self.collectionsKey)
        }
    }

    public func toggleFavorite(_ path: String) {
        if favorites.contains(path) { favorites.remove(path) } else { favorites.insert(path) }
        persist()
    }

    public func togglePin(_ path: String) {
        if pinned.contains(path) { pinned.remove(path) } else { pinned.insert(path) }
        persist()
    }

    public func toggleArchive(_ path: String) {
        if archived.contains(path) { archived.remove(path) } else { archived.insert(path) }
        persist()
    }

    public func createCollection(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, customCollections[trimmed] == nil else { return }
        customCollections[trimmed] = []
        persist()
    }

    public func deleteCollection(_ name: String) {
        customCollections.removeValue(forKey: name)
        persist()
    }

    public func renameCollection(_ oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let members = customCollections.removeValue(forKey: oldName) else { return }
        customCollections[trimmed] = members
        persist()
    }

    public func addToCollection(_ name: String, path: String) {
        customCollections[name, default: []].insert(path)
        persist()
    }

    public func removeFromCollection(_ name: String, path: String) {
        customCollections[name]?.remove(path)
        persist()
    }
}

/// One project row for the collections view; the host maps its own project
/// model (Organizer / `ProjectRegistryEntry`) into this shape.
public struct RepositoryCollectionProject: Identifiable, Hashable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var remote: String?

    public init(name: String, path: String, remote: String? = nil) {
        self.name = name
        self.path = path
        self.remote = remote
    }
}

@MainActor
public struct RepositoryCollectionsView: View {
    @ObservedObject public var store: RepositoryCollectionStore
    public var projects: [RepositoryCollectionProject]
    @Binding public var selectedPath: String?
    public var onOpenProject: (RepositoryCollectionProject) -> Void

    @State private var searchText = ""
    @State private var filter: FilterOption = .all
    @State private var sortBy: SortOption = .recent
    @State private var showCollectionSheet = false

    public enum FilterOption: String, CaseIterable, Identifiable {
        case all = "All Repositories"
        case favorites = "Favorites Only"
        case pinned = "Pinned Only"
        case archived = "Archived Only"

        public var id: String { rawValue }
    }

    public enum SortOption: String, CaseIterable, Identifiable {
        case recent = "Most Recent"
        case name = "Name Alphabetical"

        public var id: String { rawValue }
    }

    public init(store: RepositoryCollectionStore, projects: [RepositoryCollectionProject], selectedPath: Binding<String?>, onOpenProject: @escaping (RepositoryCollectionProject) -> Void) {
        self.store = store
        self.projects = projects
        self._selectedPath = selectedPath
        self.onOpenProject = onOpenProject
    }

    private var processedProjects: [RepositoryCollectionProject] {
        var list = projects
        if !searchText.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        switch filter {
        case .all: break
        case .favorites: list = list.filter { store.favorites.contains($0.path) }
        case .pinned: list = list.filter { store.pinned.contains($0.path) }
        case .archived: list = list.filter { store.archived.contains($0.path) }
        }
        switch sortBy {
        case .recent: break // input order is the Organizer's recency order
        case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return list
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Repository Browser")
                        .font(.headline)
                    Spacer()
                    Button("Manage Collections…") { showCollectionSheet = true }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search Projects", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)

                HStack {
                    Picker("Filter", selection: $filter) {
                        ForEach(FilterOption.allCases) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .controlSize(.small)
                    Spacer()
                    Picker("Sort", selection: $sortBy) {
                        ForEach(SortOption.allCases) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .controlSize(.small)
                }
            }
            .padding(12)

            Divider()

            List(selection: $selectedPath) {
                Section("Active Workspace Collections") {
                    ForEach(processedProjects) { project in
                        HStack(spacing: 8) {
                            Image(systemName: project.remote != nil ? "cloud.fill" : "laptopcomputer")
                                .foregroundStyle(project.remote != nil ? Color.blue : Color.secondary)
                                .font(.system(size: 11))
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    Text(project.name)
                                        .font(.subheadline.bold())
                                        .lineLimit(1)
                                    if store.pinned.contains(project.path) {
                                        Image(systemName: "pin.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.orange)
                                    }
                                    if store.favorites.contains(project.path) {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.yellow)
                                    }
                                }
                                if let remote = project.remote {
                                    Text(remote)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Text("Local Project")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            if store.archived.contains(project.path) {
                                Text("Archived")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.15))
                                    .foregroundStyle(.secondary)
                                    .cornerRadius(3)
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(project.path)
                        .contentShape(Rectangle())
                        .onTapGesture { onOpenProject(project) }
                        .contextMenu {
                            Button(store.pinned.contains(project.path) ? "Unpin Repository" : "Pin Repository") {
                                store.togglePin(project.path)
                            }
                            Button(store.favorites.contains(project.path) ? "Remove from Favorites" : "Mark as Favorite") {
                                store.toggleFavorite(project.path)
                            }
                            Button(store.archived.contains(project.path) ? "Unarchive Repository" : "Archive Repository") {
                                store.toggleArchive(project.path)
                            }
                            Divider()
                            Menu("Add to Collection") {
                                ForEach(store.customCollections.keys.sorted(), id: \.self) { name in
                                    Button(name) { store.addToCollection(name, path: project.path) }
                                }
                            }
                        }
                    }
                }

                Section("Collections") {
                    ForEach(store.customCollections.keys.sorted(), id: \.self) { name in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(name)
                            Spacer()
                            Text("\(store.customCollections[name]?.count ?? 0)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .sheet(isPresented: $showCollectionSheet) {
            ManageCollectionsSheet(store: store)
        }
    }
}

/// Create / rename / delete custom collections.
@MainActor
public struct ManageCollectionsSheet: View {
    @ObservedObject public var store: RepositoryCollectionStore
    @Environment(\.dismiss) private var dismiss

    @State private var newCollectionName = ""
    @State private var renameTarget: String?
    @State private var renameText = ""

    public init(store: RepositoryCollectionStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Manage Collections")
                .font(.headline)
            HStack {
                TextField("New collection name", text: $newCollectionName)
                    .textFieldStyle(.roundedBorder)
                Button("Create") {
                    store.createCollection(newCollectionName)
                    newCollectionName = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            List {
                ForEach(store.customCollections.keys.sorted(), id: \.self) { name in
                    HStack {
                        if renameTarget == name {
                            TextField("Collection name", text: $renameText)
                                .textFieldStyle(.roundedBorder)
                            Button("Save") {
                                store.renameCollection(name, to: renameText)
                                renameTarget = nil
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Text(name)
                            Spacer()
                            Text("\(store.customCollections[name]?.count ?? 0) projects")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Rename") {
                                renameTarget = name
                                renameText = name
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            Button("Delete", role: .destructive) {
                                store.deleteCollection(name)
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440, height: 380)
    }
}
