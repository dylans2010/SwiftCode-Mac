import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @State var viewModel = HomeViewModel()
    @Environment(ThemeViewModel.self) private var themeVM
    @EnvironmentObject private var projectManager: ProjectManager
    @EnvironmentObject private var folderManager: FolderManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var suggestionsManager: CodeSuggestionsML

    @State private var showingNewProject = false
    @State private var showingSettings = false
    @State private var selectedProject: Project?

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
        NavigationStack {
            ZStack {
                Color(hex: themeVM.currentTheme.background).ignoresSafeArea()

                VStack {
                    if projectManager.projects.isEmpty && folderManager.folders.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView {
                            foldersSection

                            projectsSection
                        }
                    }
                }
            }
            .frame(minWidth: 800, minHeight: 600)
            .navigationTitle("SwiftCode")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingNewProject = true }) {
                        Label("New Project", systemImage: "plus")
                    }
                    .help("New Project (⌘⇧N)")
                }
                ToolbarItem(placement: .navigation) {
                    Button(action: { showingSettings = true }) {
                        Label("Settings", systemImage: "gear")
                    }
                    .help("Settings")
                }
            }
            .sheet(isPresented: $showingNewProject) {
                NewProjectSheetView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .frame(width: 600, height: 500)
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
            .navigationDestination(isPresented: .init(get: { projectManager.activeProject != nil }, set: { if !$0 { projectManager.closeProject() } })) {
                if let project = projectManager.activeProject {
                    WorkspaceView(viewModel: WorkspaceViewModel(projectURL: project.directoryURL))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowNewProjectSheet"))) { _ in
                showingNewProject = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowImportPicker"))) { _ in
                showingNewProject = true
            }
            .onChange(of: projectManager.activeProject?.id) {
                guard settings.codeSuggestionsEnabled, let project = projectManager.activeProject else { return }
                suggestionsManager.analyze(project: project)
            }
            .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK") {}
            } message: { msg in Text(msg) }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("SwiftCode", systemImage: "swift")
                .font(.system(size: 80))
                .foregroundStyle(.orange)
        } description: {
            Text("The Next Generation IDE for Swift.\nCreate a new project or import an existing one to get started.")
        } actions: {
            Button("New Project...") { showingNewProject = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var foldersSection: some View {
        Group {
            if !folderManager.folders.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Folders")
                        .font(.headline)
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(folderManager.folders) { folder in
                                FolderCardView(folder: folder)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            folderManager.deleteFolder(folder)
                                        } label: {
                                            Label("Delete Folder", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top)
            }
        }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Projects")
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250))], spacing: 20) {
                ForEach(projectManager.projects) { project in
                    HomeProjectCardView(project: project) {
                        projectManager.openProject(project)
                    } onDelete: {
                        try? projectManager.deleteProject(project)
                    }
                    .contextMenu { projectContextMenu(for: project) }
                }
            }
            .padding(24)
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

struct HomeProjectCardView: View {
    let project: Project
    let onOpen: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "swift")
                    .font(.title)
                    .foregroundColor(.orange)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
            }
            .padding(.bottom, 8)

            Text(project.name)
                .font(.headline)
                .lineLimit(1)

            Text(project.lastOpened, style: .relative)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(isHovered ? 0.4 : 0.1), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { isHovered = $0 }
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.3), value: isHovered)
    }
}
