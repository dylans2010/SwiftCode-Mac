import SwiftUI

struct HomeView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @EnvironmentObject private var folderManager: FolderManager
    @Environment(ThemeViewModel.self) private var themeVM

    @State private var showingNewProject = false
    @State private var showingSettings = false
    @State private var selection: String? = "Recent"
    @State private var searchText = ""

    // Sorting and view mode
    @AppStorage("com.swiftcode.home.viewMode") private var viewModeRaw = "grid" // "grid" or "list"
    @State private var sortBy: SortMode = .lastOpened
    @AppStorage("com.swiftcode.home.favoriteProjects") private var favoriteProjectIDs: String = ""

    // Folder Creation Sheet
    @State private var showCreateFolderSheet = false
    @State private var newFolderName = ""
    @State private var newFolderColor = "#FF5733"

    // Project management states
    @State private var showRenameSheet = false
    @State private var projectToRename: Project?
    @State private var renameText = ""
    @State private var showAddToFolderSheet = false
    @State private var projectToAssignFolder: Project?
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var errorMessage: String?
    @State private var showError = false

    enum ViewMode: String {
        case grid, list
    }

    enum SortMode: String, CaseIterable, Identifiable {
        case lastOpened = "Last Opened"
        case name = "Name"
        case dateCreated = "Date Created"

        var id: String { rawValue }
    }

    private var favorites: Set<String> {
        Set(favoriteProjectIDs.split(separator: ",").map(String.init))
    }

    var body: some View {
        AdaptivePage {
            AdaptiveSplitLayout {
                sidebar
            } detail: {
                detail
            }
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheetView(viewModel: HomeViewModel())
        }
        .sheet(isPresented: $showingSettings) {
            AdaptiveSheet {
                SettingsView()
            }
        }
        .sheet(isPresented: $showCreateFolderSheet) {
            createFolderSheet
        }
        .sheet(isPresented: $showRenameSheet) {
            renameSheet
        }
        .sheet(isPresented: $showAddToFolderSheet) {
            addToFolderSheet
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
            }
        }
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") {}
        } message: { msg in Text(msg) }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowImportPicker"))) { _ in
            showingNewProject = true
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Library") {
                    Label("Recent Projects", systemImage: "clock").tag("Recent")
                    Label("All Projects", systemImage: "folder").tag("All")
                    Label("Favorites", systemImage: "star.fill").tag("Favorites")
                }

                Section(header: HStack {
                    Text("Folders")
                    Spacer()
                    Button {
                        newFolderName = ""
                        showCreateFolderSheet = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Create Organization Folder")
                }) {
                    ForEach(folderManager.folders) { folder in
                        Label(folder.folderName, systemImage: "folder.badge.gearshape")
                            .tag("folder_\(folder.folderId)")
                            .contextMenu {
                                Button(role: .destructive) {
                                    folderManager.deleteFolder(folder)
                                } label: {
                                    Label("Delete Folder", systemImage: "trash")
                                }
                            }
                    }
                }

                Section("Templates") {
                    Label("Browse Templates", systemImage: "square.grid.2x2").tag("Templates")
                }
            }
            .listStyle(.sidebar)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("SwiftCode")
    }

    private var detail: some View {
        ZStack {
            // Vibant translucent layout
            Color(hex: themeVM.currentTheme.background)
                .opacity(0.85)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)

            VStack(spacing: 0) {
                headerView

                if filteredProjects.isEmpty && !isSearching {
                    emptyStateView
                } else {
                    if viewModeRaw == "grid" {
                        projectsGrid
                    } else {
                        projectsList
                    }
                }
            }
        }
    }

    private var isSearching: Bool { !searchText.isEmpty }

    private var filteredProjects: [Project] {
        var baseProjects = sessionStore.projects

        // Filter based on library/sidebar selection
        if let sel = selection {
            if sel == "Recent" {
                baseProjects = Array(baseProjects.prefix(5))
            } else if sel == "Favorites" {
                baseProjects = baseProjects.filter { favorites.contains($0.id.uuidString) }
            } else if sel.hasPrefix("folder_") {
                let idString = String(sel.dropFirst(7))
                if let uuid = UUID(uuidString: idString),
                   let folder = folderManager.folders.first(where: { $0.folderId == uuid }) {
                    baseProjects = folderManager.projects(in: folder, allProjects: baseProjects)
                }
            }
        }

        // Apply text search
        if isSearching {
            baseProjects = baseProjects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        // Apply sort mode
        switch sortBy {
        case .lastOpened:
            baseProjects.sort { $0.lastOpened > $1.lastOpened }
        case .name:
            baseProjects.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .dateCreated:
            baseProjects.sort { $0.createdAt > $1.lastOpened }
        }

        return baseProjects
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(titleForSelection)
                    .font(.largeTitle)
                    .bold()
                Text("\(filteredProjects.count) projects")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                // View Mode Toggle
                Picker("View", selection: $viewModeRaw) {
                    Image(systemName: "square.grid.2x2").tag("grid")
                    Image(systemName: "list.bullet").tag("list")
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
                .help("Toggle Grid/List layout")

                // Sort selection
                Picker("Sort", selection: $sortBy) {
                    ForEach(SortMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search projects...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(8)
                .frame(width: 200)

                Button(action: { showingNewProject = true }) {
                    Label("New Project", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Button(action: { showingSettings = true }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(32)
    }

    private var titleForSelection: String {
        guard let sel = selection else { return "Projects" }
        if sel == "Recent" { return "Recent Projects" }
        if sel == "All" { return "All Projects" }
        if sel == "Favorites" { return "Favorites" }
        if sel.hasPrefix("folder_") {
            let idString = String(sel.dropFirst(7))
            if let uuid = UUID(uuidString: idString) {
                return folderManager.folders.first(where: { $0.folderId == uuid })?.folderName ?? "Folder"
            }
            return "Folder"
        }
        return "Projects"
    }

    private var projectsGrid: some View {
        ZStack {
            AdaptiveGrid(filteredProjects, id: \.id) { project in
                HomeProjectCardView(project: project) {
                    Task {
                        await sessionStore.openProject(project)
                    }
                } onDelete: {
                    try? sessionStore.deleteProject(project)
                }
                .contextMenu { projectContextMenu(for: project) }
            }

            loadingOverlay
        }
    }

    private var projectsList: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredProjects) { project in
                        HStack {
                            Image(systemName: "swift")
                                .font(.title3)
                                .foregroundColor(.orange)
                                .padding(8)
                                .background(Color.orange.opacity(0.12))
                                .cornerRadius(6)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.name)
                                    .font(.headline)
                                Text(project.description.isEmpty ? "No description" : project.description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            HStack(spacing: 16) {
                                if favorites.contains(project.id.uuidString) {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.orange)
                                }
                                Text(project.lastOpened, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .cornerRadius(10)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                await sessionStore.openProject(project)
                            }
                        }
                        .contextMenu { projectContextMenu(for: project) }
                    }
                }
                .padding(.horizontal, 32)
            }

            loadingOverlay
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if sessionStore.state != .idle && sessionStore.state != .cancelled {
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    switch sessionStore.state {
                    case .resolving, .loading:
                        ProgressView()
                            .controlSize(.large)

                        Text("Opening project...")
                            .font(.headline)

                        Button("Cancel") {
                            sessionStore.cancelLoad()
                        }
                        .buttonStyle(.bordered)
                    case .failed(let error):
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.red)

                        Text("Failed to open project")
                            .font(.headline)

                        Text(error.localizedDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 300)

                        HStack {
                            Button("Cancel") {
                                sessionStore.closeProject()
                            }
                            .buttonStyle(.bordered)

                            Button("Retry") {
                                sessionStore.state = .idle
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    default:
                        EmptyView()
                    }
                }
                .padding(32)
                .background(RoundedRectangle(cornerRadius: 16).fill(.thinMaterial))
            }
        }
    }

    @ViewBuilder
    private func projectContextMenu(for project: Project) -> some View {
        Button {
            Task {
                await sessionStore.openProject(project)
            }
        } label: {
            Label("Open Project", systemImage: "play.fill")
        }

        Button {
            toggleFavorite(project)
        } label: {
            Label(favorites.contains(project.id.uuidString) ? "Remove Favorite" : "Add to Favorites", systemImage: "star")
        }

        Button {
            projectToRename = project
            renameText = project.name
            showRenameSheet = true
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            Task {
                do { try sessionStore.duplicateProject(project) }
                catch { showError(error) }
            }
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Button {
            exportProject(project)
        } label: {
            Label("Export As ZIP", systemImage: "square.and.arrow.up")
        }

        Button {
            projectToAssignFolder = project
            showAddToFolderSheet = true
        } label: {
            Label("Add To Folder", systemImage: "folder.badge.plus")
        }

        Divider()

        Button(role: .destructive) {
            do { try sessionStore.deleteProject(project) }
            catch { showError(error) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "swift")
                .font(.system(size: 80))
                .foregroundStyle(.orange.gradient)
                .padding()
                .background(Circle().fill(.orange.opacity(0.1)))

            VStack(spacing: 8) {
                Text("Welcome to SwiftCode")
                    .font(.title)
                    .bold()
                Text("Start your next great idea by creating a new project or importing an existing one.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            HStack(spacing: 16) {
                Button(action: { showingNewProject = true }) {
                    Label("Create New Project", systemImage: "plus")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: { showingNewProject = true }) {
                    Label("Import Project", systemImage: "folder.badge.plus")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("Quick Start")
                    .font(.headline)
                    .padding(.top)

                QuickStartRow(icon: "book.pages", title: "Learn SwiftCode", description: "Read the introduction guide to get started.")
                QuickStartRow(icon: "shippingbox", title: "Swift Packages", description: "Create and manage Swift packages with ease.")
                QuickStartRow(icon: "macwindow", title: "App Templates", description: "Choose from a variety of pre-configured templates.")
            }
            .frame(maxWidth: 400)
            .padding(.top, 40)
        }
        .frame(maxHeight: .infinity)
    }

    private var createFolderSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Folder Name", text: $newFolderName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Folder Theme Color")
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: newFolderColor) },
                        set: { newFolderColor = $0.toHex() ?? "#FF5733" }
                    ))
                }
            }
            .padding()
            .navigationTitle("Create Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCreateFolderSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        folderManager.createFolder(name: newFolderName, symbol: "folder.badge.gearshape", colorHex: newFolderColor)
                        showCreateFolderSheet = false
                    }
                    .disabled(newFolderName.isEmpty)
                }
            }
        }
        .frame(width: 320, height: 180)
    }

    private var renameSheet: some View {
        NavigationStack {
            VStack {
                TextField("Project Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding()
            .navigationTitle("Rename Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showRenameSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename") {
                        if let project = projectToRename {
                            try? sessionStore.renameProject(project, to: renameText)
                            showRenameSheet = false
                        }
                    }
                    .disabled(renameText.isEmpty)
                }
            }
        }
        .frame(width: 300, height: 150)
    }

    private var addToFolderSheet: some View {
        NavigationStack {
            List(folderManager.folders) { folder in
                Button(folder.folderName) {
                    if let project = projectToAssignFolder {
                        folderManager.addProject(project.id, to: folder.folderId)
                    }
                    showAddToFolderSheet = false
                }
            }
            .navigationTitle("Add to Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddToFolderSheet = false }
                }
            }
        }
        .frame(width: 300, height: 400)
    }

    private func exportProject(_ project: Project) {
        Task {
            do {
                let url = try await ZipImporter.shared.exportZip(for: project)
                await MainActor.run {
                    exportURL = url
                    showShareSheet = true
                }
            } catch {
                showError(error)
            }
        }
    }

    private func toggleFavorite(_ project: Project) {
        var favs = favorites
        let uuidStr = project.id.uuidString
        if favs.contains(uuidStr) {
            favs.remove(uuidStr)
        } else {
            favs.insert(uuidStr)
        }
        favoriteProjectIDs = favs.joined(separator: ",")
    }

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}

// Color conversion helpers for saving selected theme HEX string
private extension Color {
    func toHex() -> String? {
        let uic = NSColor(self)
        guard let rgb = uic.usingColorSpace(.deviceRGB) else { return nil }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
