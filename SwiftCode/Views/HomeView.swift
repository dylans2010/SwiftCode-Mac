import SwiftUI

struct HomeView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @EnvironmentObject private var folderManager: FolderManager
    @Environment(ThemeViewModel.self) private var themeVM
    @State private var showingNewProject = false
    @State private var showingSettings = false
    @State private var selection: String? = "Recent"
    @State private var searchText = ""

    // View layout preference: Grid vs List
    @State private var isGridLayout = true

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

    // Favorites & Recents persistence sets
    @State private var favoriteProjectIDs: Set<UUID> = []

    var body: some View {
        AdaptivePage {
            AdaptiveSplitLayout {
                sidebar
                    .background(.ultraThinMaterial)
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
        .onAppear {
            loadFavorites()
            // Restore previous layout and selection state
            isGridLayout = UserDefaults.standard.bool(forKey: "com.swiftcode.home.isGridLayout")
            if let savedSelection = UserDefaults.standard.string(forKey: "com.swiftcode.home.sidebarSelection") {
                selection = savedSelection
            }
        }
        .onChange(of: selection) { _, newValue in
            if let val = newValue {
                UserDefaults.standard.set(val, forKey: "com.swiftcode.home.sidebarSelection")
            }
        }
        .onChange(of: isGridLayout) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "com.swiftcode.home.isGridLayout")
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("Recent", systemImage: "clock").tag("Recent")
                Label("All Projects", systemImage: "folder").tag("All")
                Label("Favorites", systemImage: "star.fill").tag("Favorites")
            }

            Section("Folders") {
                if folderManager.folders.isEmpty {
                    Text("No Folders")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                } else {
                    ForEach(folderManager.folders) { folder in
                        Label(folder.folderName, systemImage: "folder.badge.gearshape")
                            .tag("folder_\(folder.folderId)")
                            .onDrop(of: [.text], isTargeted: nil) { providers in
                                guard let provider = providers.first else { return false }
                                provider.loadObject(ofClass: NSString.self) { string, _ in
                                    guard let uuidString = string as? String,
                                          let projectUUID = UUID(uuidString: uuidString) else { return }
                                    DispatchQueue.main.async {
                                        folderManager.addProject(projectUUID, to: folder.folderId)
                                    }
                                }
                                return true
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    folderManager.deleteFolder(folder)
                                } label: {
                                    Label("Delete Folder", systemImage: "trash")
                                }
                            }
                    }
                }

                Button(action: createNewFolderPrompt) {
                    Label("Add Folder", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 4)
            }

            Section("Templates") {
                Label("Browse Templates", systemImage: "square.grid.2x2").tag("Templates")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SwiftCode")
    }

    private var detail: some View {
        ZStack {
            // Elegant native macOS background materials and vibrancy
            VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerView

                if filteredProjects.isEmpty && !isSearching {
                    emptyStateView
                } else {
                    if isGridLayout {
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

        if let sel = selection {
            if sel == "Recent" {
                baseProjects = Array(baseProjects.prefix(5))
            } else if sel == "Favorites" {
                baseProjects = baseProjects.filter { favoriteProjectIDs.contains($0.id) }
            } else if sel.hasPrefix("folder_") {
                let idString = String(sel.dropFirst(7))
                if let uuid = UUID(uuidString: idString),
                   let folder = folderManager.folders.first(where: { $0.folderId == uuid }) {
                    // Centralized, programmatically fixed virtual folder lookup
                    baseProjects = baseProjects.filter { folder.projectIdentifiers.contains($0.id) }
                }
            }
        }

        if isSearching {
            return baseProjects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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
                // Layout Switcher
                HStack(spacing: 0) {
                    Button(action: { isGridLayout = true }) {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(isGridLayout ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .background(isGridLayout ? Color.white.opacity(0.1) : Color.clear)
                    .cornerRadius(6)

                    Button(action: { isGridLayout = false }) {
                        Image(systemName: "list.bullet")
                            .foregroundStyle(!isGridLayout ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .background(!isGridLayout ? Color.white.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
                }
                .padding(4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search projects...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .frame(width: 250)

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
                .onDrag {
                    NSItemProvider(object: project.id.uuidString as NSString)
                }
                .contextMenu { projectContextMenu(for: project) }
            }

            loadingOverlay
        }
    }

    private var projectsList: some View {
        ZStack {
            List(filteredProjects) { project in
                HStack(spacing: 16) {
                    Image(systemName: "swift")
                        .font(.title2)
                        .foregroundColor(.orange)
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name)
                            .font(.headline)
                        Text("Last opened \(project.lastOpened, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        Label("\(project.fileCount) files", systemImage: "doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if favoriteProjectIDs.contains(project.id) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                        }

                        Button("Open") {
                            Task {
                                await sessionStore.openProject(project)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
                .contextMenu { projectContextMenu(for: project) }
            }
            .scrollContentBackground(.hidden)

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
            projectToRename = project
            renameText = project.name
            showRenameSheet = true
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            toggleFavorite(project)
        } label: {
            Label(favoriteProjectIDs.contains(project.id) ? "Unfavorite" : "Favorite", systemImage: "star")
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

    private func createNewFolderPrompt() {
        let panel = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        let alert = NSAlert()
        alert.messageText = "New Virtual Folder"
        alert.informativeText = "Enter a name for the virtual project folder:"
        alert.accessoryView = panel
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let name = panel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                folderManager.createFolder(name: name, symbol: "folder.fill", colorHex: "#4F86FF")
            }
        }
    }

    private func toggleFavorite(_ project: Project) {
        if favoriteProjectIDs.contains(project.id) {
            favoriteProjectIDs.remove(project.id)
        } else {
            favoriteProjectIDs.insert(project.id)
        }
        saveFavorites()
    }

    private func saveFavorites() {
        let strings = favoriteProjectIDs.map { $0.uuidString }
        UserDefaults.standard.set(strings, forKey: "com.swiftcode.home.favorites")
    }

    private func loadFavorites() {
        if let saved = UserDefaults.standard.stringArray(forKey: "com.swiftcode.home.favorites") {
            favoriteProjectIDs = Set(saved.compactMap { UUID(uuidString: $0) })
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

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}

// MARK: - Visual Effect View Wrapper

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Reusable Dashboard/Home Components

struct QuickStartRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.orange)
                .frame(width: 32, height: 32)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct HomeProjectCardView: View {
    let project: Project
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "swift")
                    .font(.title)
                    .foregroundColor(.orange)
                    .padding(10)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1.0 : 0.0)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(project.description.isEmpty ? "No description" : project.description)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Label("\(project.fileCount) files", systemImage: "doc")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Opened \(project.lastOpened, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minHeight: 140)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}
