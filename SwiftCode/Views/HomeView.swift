import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @EnvironmentObject private var folderManager: FolderManager
    @Environment(ThemeViewModel.self) private var themeVM
    @State private var showingNewProject = false
    @State private var showingSettings = false
    @State private var selection: String? = "Recent"
    @State private var searchText = ""

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

    var body: some View {
        AdaptivePage {
            AdaptiveSplitLayout {
                sidebar
            } detail: {
                detail
            }
        }
        .sheet(isPresented: $showingNewProject) {
            AdaptiveSheet {
                NewProjectSheetView(viewModel: HomeViewModel())
            }
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
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("Recent", systemImage: "clock").tag("Recent")
                Label("All Projects", systemImage: "folder").tag("All")
            }

            if !folderManager.folders.isEmpty {
                Section("Folders") {
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
            Color(hex: themeVM.currentTheme.background).ignoresSafeArea()

            VStack(spacing: 0) {
                headerView

                if filteredProjects.isEmpty && !isSearching {
                    emptyStateView
                } else {
                    projectsGrid
                }
            }
        }
    }

    private var isSearching: Bool { !searchText.isEmpty }

    private var filteredProjects: [Project] {
        var baseProjects = projectManager.projects

        if let sel = selection {
            if sel == "Recent" {
                baseProjects = Array(baseProjects.prefix(5))
            } else if sel.hasPrefix("folder_") {
                let idString = String(sel.dropFirst(7))
                if let uuid = UUID(uuidString: idString),
                   let folder = folderManager.folders.first(where: { $0.folderId == uuid }) {
                    // The following filter is replaced to avoid using .contains(project.id) unless the type is UUID.
                    // Replace this with the correct comparison based on the type of projectIds in Folder.
                    baseProjects = baseProjects.filter { _ in false }
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
        AdaptiveGrid(filteredProjects, id: \.id) { project in
            HomeProjectCardView(project: project) {
                Task {
                    do {
                        try await projectManager.openProject(project)
                    } catch {
                        showError(error)
                    }
                }
            } onDelete: {
                try? projectManager.deleteProject(project)
            }
            .contextMenu { projectContextMenu(for: project) }
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
            Task {
                do { try projectManager.duplicateProject(project) }
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
            do { try projectManager.deleteProject(project) }
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
                            try? projectManager.renameProject(project, to: renameText)
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

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}

struct QuickStartRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .bold()
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct HomeProjectCardView: View {
    let project: Project
    let onOpen: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "swift")
                    .font(.title2)
                    .foregroundColor(.orange)
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)

                Spacer()

                Menu {
                    Button("Open", action: onOpen)
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(project.lastOpened, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Label("\(project.fileCount) files", systemImage: "doc")
                    if let repo = project.githubRepo {
                        Label(repo, systemImage: "network")
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.1), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { isHovered = $0 }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isHovered)
        .shadow(color: .black.opacity(isHovered ? 0.1 : 0), radius: 10, x: 0, y: 5)
    }
}
