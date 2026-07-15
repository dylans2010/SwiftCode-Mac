import SwiftUI
import WelcomeView

@MainActor
struct SwiftCodeWelcomeView: View {
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

    // WelcomeView Package Bindings
    @State private var welcomeTitle = "Welcome to SwiftCode"
    @State private var resetSelection = false

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
            NewProjectSheetView(viewModel: WelcomeViewModel())
        }
        .sheet(isPresented: $showingSettings) {
            NewSettingsView()
                .environmentObject(AppSettings.shared)
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
                    Label("Welcome Screen", systemImage: "sparkles").tag("Recent")
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
            LinearGradient(
                colors: [
                    Color(hex: themeVM.currentTheme.background).opacity(0.96),
                    Color.accentColor.opacity(0.10),
                    Color.orange.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .background(.ultraThinMaterial)

            VStack(spacing: 0) {
                if selection == "Recent" {
                    packageWelcomeView
                } else if selection == "Templates" {
                    TemplatePickerView(viewModel: WelcomeViewModel())
                        .padding(24)
                } else {
                    heroHeader

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
    }

    private var packageWelcomeView: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
                .padding(.trailing, 24)
            }

            WelcomeView(
                titleText: welcomeTitle,
                menu: WelcomeMenu {
                    WelcomeMenuButton(title: "New Project", image: Image(systemName: "plus.circle.fill")) {
                        showingNewProject = true
                    }
                    WelcomeMenuButton(title: "Import Folder", image: Image(systemName: "folder.badge.plus")) {
                        importFolder()
                    }
                    WelcomeMenuButton(title: "Xcode Project", image: Image(systemName: "hammer.circle.fill")) {
                        showingNewProject = true
                    }
                },
                emptyMessage: "No Recent Projects",
                recentFileProvider: ProjectRecentFileProvider(sessionStore: sessionStore)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            baseProjects.sort { $0.createdAt > $1.createdAt }
        }

        return baseProjects
    }

    private var heroHeader: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.orange.opacity(0.22).gradient)
                    Image(systemName: "swift")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.orange.gradient)
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 8) {
                    Text(titleForSelection)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(homeSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button(action: { showingSettings = true }) {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)

                    Button(action: { showingNewProject = true }) {
                        Label("New Project", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }

            HStack(spacing: 12) {
                HomeStatPill(icon: "folder.fill", title: "Projects", value: "\(sessionStore.projects.count)", tint: .blue)
                HomeStatPill(icon: "clock.fill", title: "Recent", value: "\(min(sessionStore.projects.count, 5))", tint: .purple)
                HomeStatPill(icon: "star.fill", title: "Favorites", value: "\(favorites.count)", tint: .orange)

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search projects", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(width: 230)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Picker("Sort", selection: $sortBy) {
                    ForEach(SortMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)

                Picker("View", selection: $viewModeRaw) {
                    Label("Grid", systemImage: "square.grid.2x2").tag("grid")
                    Label("List", systemImage: "list.bullet").tag("list")
                }
                .pickerStyle(.segmented)
                .frame(width: 96)
            }
        }
        .padding(24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var homeSubtitle: String {
        if isSearching {
            return "Showing \(filteredProjects.count) result(s) for “\(searchText)”"
        }
        return "Open a workspace, organize favorites, or start something new."
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
            Image(systemName: "sparkles")
                .font(.system(size: 74, weight: .semibold))
                .foregroundStyle(.orange.gradient)
                .padding(28)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(.orange.opacity(0.25), lineWidth: 1))

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
                        set: { newFolderColor = $0.toHex }
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

    private func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    let project = try await sessionStore.importProject(from: url)
                    await sessionStore.openProject(project)
                } catch {
                    LoggingTool.error("Failed to import folder: \(error)")
                }
            }
        }
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

@MainActor
struct HomeStatPill: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.bold())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

@MainActor
struct QuickStartRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

@MainActor
struct ProjectRecentFileProvider: RecentFileProvider {
    let sessionStore: ProjectSessionStore

    func provideRecentFiles() async -> [RecentFile] {
        sessionStore.projects.map { project in
            RecentFile(
                customTitle: project.name,
                customSubtitle: project.description.isEmpty ? nil : project.description,
                url: project.directoryURL
            )
        }
    }

    func openFile(_ file: RecentFile) {
        if let project = sessionStore.projects.first(where: { $0.directoryURL == file.url }) {
            Task {
                await sessionStore.openProject(project)
            }
        }
    }
}
