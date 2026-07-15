import SwiftUI

@MainActor
struct SwiftCodeWelcomeView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @EnvironmentObject private var folderManager: FolderManager
    @Environment(ThemeViewModel.self) private var themeVM

    @State private var showingNewProject = false
    @State private var showingSettings = false
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

    enum SortMode: String, CaseIterable, Identifiable {
        case lastOpened = "Last Opened"
        case name = "Name"
        case dateCreated = "Date Created"

        var id: String { rawValue }
    }

    private var favorites: Set<String> {
        Set(favoriteProjectIDs.split(separator: ",").map(String.init))
    }

    private var isSearching: Bool { !searchText.isEmpty }

    var body: some View {
        AdaptivePage {
            mainDashboard
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheetView(viewModel: WelcomeViewModel())
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
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

    private var mainDashboard: some View {
        ZStack {
            // Modern, rich background gradient with neon accents
            LinearGradient(
                colors: [
                    Color(hex: themeVM.currentTheme.background).opacity(0.98),
                    Color.accentColor.opacity(0.08),
                    Color.orange.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 0) {
                // Left Column: Modern Welcoming Hero & Quick Actions
                leftPanel
                    .frame(width: 360)
                    .background(.ultraThinMaterial.opacity(0.5))

                Divider()

                // Right Column: Active/Recent Workspace Manager
                rightPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var leftPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 32) {
                    // Modern Stylized Icon
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.12).gradient)
                            .frame(width: 110, height: 110)
                            .blur(radius: 6)

                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 80, height: 80)
                            .shadow(color: .orange.opacity(0.4), radius: 12, x: 0, y: 6)

                        Image(systemName: "swift")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 40)

                    // Modernised "Welcome to SwiftCode" Header Text
                    VStack(spacing: 12) {
                        Text("Welcome to SwiftCode")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.orange, .red, Color.accentColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        Text("The desktop IDE for building and organizing cutting-edge Swift applications natively.")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // Modern Quick Action Cards
                    VStack(spacing: 14) {
                        ModernActionCard(
                            title: "New Project",
                            subtitle: "Start a fresh app from templates",
                            iconName: "plus.circle.fill",
                            color: .orange
                        ) {
                            showingNewProject = true
                        }

                        ModernActionCard(
                            title: "Import Folder",
                            subtitle: "Open a project directory from disk",
                            iconName: "folder.badge.plus",
                            color: .blue
                        ) {
                            importFolder()
                        }

                        ModernActionCard(
                            title: "Settings",
                            subtitle: "Configure accounts, themes & AI",
                            iconName: "gearshape.fill",
                            color: .purple
                        ) {
                            showingSettings = true
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 20)
                }
            }
            .scrollIndicators(.never)

            // Dynamic stats bar at the bottom
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(sessionStore.projects.count)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Total Projects")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(favorites.count)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Favorites")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 16)
            .background(.ultraThinMaterial.opacity(0.8))
        }
    }

    private var rightPanel: some View {
        VStack(spacing: 0) {
            // Workspace Header Bar
            HStack(spacing: 16) {
                Text("Your Workspaces")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer()

                // Interactive Filters
                HStack(spacing: 12) {
                    // Search Bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search projects...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(width: 180)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    // Sort Picker
                    Picker("", selection: $sortBy) {
                        ForEach(SortMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)

                    // View Mode Switcher
                    Picker("", selection: $viewModeRaw) {
                        Image(systemName: "square.grid.2x2").tag("grid")
                        Image(systemName: "list.bullet").tag("list")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 60)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            // Main List/Grid Area
            ZStack {
                if filteredProjects.isEmpty {
                    emptyStateView
                } else {
                    if viewModeRaw == "grid" {
                        projectsGrid
                    } else {
                        projectsList
                    }
                }

                loadingOverlay
            }
        }
    }

    private var projectsGrid: some View {
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
        .padding(24)
    }

    private var projectsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredProjects) { project in
                    HStack(spacing: 16) {
                        Image(systemName: "swift")
                            .font(.title3)
                            .foregroundColor(.orange)
                            .padding(10)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(project.description.isEmpty ? "No description provided" : project.description)
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .cornerRadius(12)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task {
                            await sessionStore.openProject(project)
                        }
                    }
                    .contextMenu { projectContextMenu(for: project) }
                }
            }
            .padding(24)
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
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.orange.gradient)
                .padding(24)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(.orange.opacity(0.2), lineWidth: 1))

            VStack(spacing: 8) {
                Text("No Projects Found")
                    .font(.title2)
                    .bold()
                Text("Get started by creating a new project or importing an existing folder from your Mac.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            HStack(spacing: 16) {
                Button(action: { showingNewProject = true }) {
                    Label("Create New Project", systemImage: "plus")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: { importFolder() }) {
                    Label("Import Folder", systemImage: "folder.badge.plus")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
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
struct ModernActionCard: View {
    let title: String
    let subtitle: String
    let iconName: String
    let color: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(isHovering ? 0.25 : 0.12).gradient)
                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundColor(color)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: Color.black.opacity(isHovering ? 0.12 : 0.04), radius: isHovering ? 8 : 3, x: 0, y: isHovering ? 3 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isHovering ? color.opacity(0.3) : Color.primary.opacity(0.05), lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.82), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
