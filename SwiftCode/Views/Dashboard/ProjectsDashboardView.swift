import SwiftUI
import UniformTypeIdentifiers

struct ProjectsDashboardView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var folderManager: FolderManager
    @State private var showCreationSheet = false
    @State private var showNewProjectSheet = false
    @State private var newProjectName = ""
    @State private var newProjectGithubRepo = ""
    @State private var showImportPicker = false
    @State private var showGitHubImportSheet = false
    @State private var githubImportURL = ""
    @State private var isFetchingGitHubRepos = false
    @State private var fetchedGitHubRepos: [GitHubRepoSummary] = []
    @State private var fetchGitHubReposError: String?
    @State private var showRenameSheet = false
    @State private var projectToRename: Project?
    @State private var renameText = ""
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var selectedProject: Project?
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var showSettings = false
    @State private var showGitHubRemoteSheet = false
    @State private var pendingProjectForRemote: Project?
    @State private var isImporting = false
    @State private var showFolderCreateView = false
    @State private var selectedFolder: ProjectFolder?
    @State private var showTransferProjects = false
    @State private var projectToAssignFolder: Project?
    @State private var showAddToFolderSheet = false
    @State private var showFolderRenameSheet = false
    @State private var folderToRename: ProjectFolder?
    @State private var folderRenameText = ""
    @State private var showCollaborationDashboard = false
    @State private var currentCollaborationManager: CollaborationManager?

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 20)]
    }

    private var sortedProjects: [Project] {
        switch settings.dashboardSortOrder {
        case .name:
            return projectManager.projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastOpened:
            return projectManager.projects.sorted { $0.lastOpened > $1.lastOpened }
        case .creationDate:
            return projectManager.projects.sorted { $0.createdAt > $1.createdAt }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.07, blue: 0.12),
                        Color(red: 0.10, green: 0.10, blue: 0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if projectManager.projects.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        foldersSection

                        if settings.dashboardLayout == .grid {
                            LazyVGrid(columns: gridColumns, spacing: 20) {
                                ForEach(sortedProjects) { project in
                                    ProjectCardView(
                                        project: project,
                                        showIcon: settings.showProjectIcons,
                                        showFileCount: settings.showFileCount,
                                        showLastOpenedTime: settings.showLastOpenedTime
                                    )
                                    .onTapGesture { projectManager.openProject(project) }
                                    .contextMenu { contextMenu(for: project) }
                                }
                            }
                            .padding()
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(sortedProjects) { project in
                                    ProjectListRowView(
                                        project: project,
                                        showIcon: settings.showProjectIcons,
                                        showPreview: settings.showFolderPreview,
                                        showFileCount: settings.showFileCount,
                                        showLastOpenedTime: settings.showLastOpenedTime
                                    )
                                    .onTapGesture { projectManager.openProject(project) }
                                    .contextMenu { contextMenu(for: project) }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showCreationSheet) { creationOptionsSheet }
            .sheet(isPresented: $showFolderCreateView) {
                FolderCreateView()
                    .environmentObject(folderManager)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showFolderRenameSheet) {
                folderRenameSheet
            }
            .sheet(isPresented: $showAddToFolderSheet) { addToFolderSheet }
            .sheet(isPresented: $showNewProjectSheet) { newProjectSheet }
            .sheet(isPresented: $showCollaborationDashboard) {
                if let manager = currentCollaborationManager {
                    NavigationStack {
                        CollaborationMainView(manager: manager)
                    }
                }
            }
            .sheet(isPresented: $showTransferProjects) { NavigationStack { TransferProjectsHomeView().environmentObject(projectManager) } }
            .sheet(isPresented: $showImportPicker) {
                FileImporterRepresentableView(
                    allowedContentTypes: [UTType.zip],
                    allowsMultipleSelection: false
                ) { urls in
                    showImportPicker = false
                    if let url = urls.first {
                        handleZipImport(.success([url]))
                    }
                }
            }
            .sheet(isPresented: $showGitHubImportSheet) { gitHubImportSheet }
            .sheet(isPresented: $showRenameSheet) { renameSheet }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .sheet(isPresented: $showSettings) {
                GeneralSettingsView()
                    .environmentObject(AppSettings.shared)
            }
            .sheet(isPresented: $showGitHubRemoteSheet) {
                if let project = pendingProjectForRemote {
                    GitHubRemoteSetupView(project: project) { configured in
                        if let configured {
                            projectManager.openProject(configured)
                            scheduleProjectTemplatesPresentation()
                        } else {
                            projectManager.openProject(project)
                            scheduleProjectTemplatesPresentation()
                        }
                        pendingProjectForRemote = nil
                    }
                    .environmentObject(projectManager)
                }
            }
            .navigationDestination(item: $selectedFolder) { folder in
                FoldersView(folder: folder)
                    .environmentObject(projectManager)
                    .environmentObject(folderManager)
            }
            .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK") {}
            } message: { msg in Text(msg) }
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "swift")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
                )
            Text("No Projects Yet")
                .font(.title2).bold()
                .foregroundStyle(.white)
            Text("Create a new project, import a zip archive,\nor clone from GitHub to get started.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button {
                    showCreationSheet = true
                } label: {
                    Label("New Project", systemImage: "plus.circle.fill")
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(.orange.opacity(0.8), in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
        .padding()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                showFolderCreateView = true
            } label: {
                Label("Create Folder", systemImage: "folder.badge.plus")
            }

            Button {
                showTransferProjects = true
            } label: {
                Label("Transfer", systemImage: "arrow.left.arrow.right.circle")
            }

            Button {
                showCreationSheet = true
            } label: {
                Label("New Project", systemImage: "plus")
            }
        }
        ToolbarItemGroup(placement: .topBarLeading) {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gear")
            }
        }
    }

    // MARK: - Creation Options Sheet

    private var creationOptionsSheet: some View {
        NavigationStack {
            List {
                Button {
                    showCreationSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showNewProjectSheet = true
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create New Project")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Generate a default SwiftUI project structure")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "plus.rectangle.fill")
                            .foregroundStyle(.orange)
                            .font(.title3)
                    }
                }

                Button {
                    showCreationSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showImportPicker = true
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import From ZIP")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Extract a ZIP file with the codebase into a new project")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "archivebox.fill")
                            .foregroundStyle(.blue)
                            .font(.title3)
                    }
                }

                Button {
                    showCreationSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showGitHubImportSheet = true
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import From GitHub")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Download a repository archive from GitHub")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .foregroundStyle(.purple)
                            .font(.title3)
                    }
                }

                Button {
                    showCreationSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showFolderCreateView = true
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create Folder")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Organize projects with custom folder groups")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "folder.badge.plus")
                            .foregroundStyle(.cyan)
                            .font(.title3)
                    }
                }

                Button {
                    showCreationSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        createCollaborativeProject()
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Collaboration Project")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Local Git-style branching, commits, and code review")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.orange)
                            .font(.title3)
                    }
                }
            }
            .navigationTitle("Create Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCreationSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var folderRenameSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New Folder Name")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    TextField("Folder Name", text: $folderRenameText)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal)
                Spacer()
            }
            .padding(.top, 32)
            .navigationTitle("Rename Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showFolderRenameSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename") {
                        if let folder = folderToRename {
                            folderManager.renameFolder(folder, to: folderRenameText)
                            showFolderRenameSheet = false
                        }
                    }
                    .disabled(folderRenameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - GitHub Import Sheet

    private var gitHubImportSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.title2)
                        .foregroundStyle(.purple)
                        .frame(width: 40, height: 40)
                        .background(.purple.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Import from GitHub")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Fetch your repositories or paste a direct URL.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Repository URL")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)

                        TextField("GitHub URL", text: $githubImportURL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)

                        Menu {
                            if fetchedGitHubRepos.isEmpty {
                                Text("No Repositories Loaded")
                            } else {
                                ForEach(fetchedGitHubRepos) { repo in
                                    Button(repo.fullName) {
                                        githubImportURL = repo.htmlUrl
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                                .foregroundStyle(.purple)
                        }
                        .disabled(fetchedGitHubRepos.isEmpty)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    )
                }

                HStack {
                    Button {
                        fetchGitHubRepositories()
                    } label: {
                        HStack(spacing: 8) {
                            if isFetchingGitHubRepos {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                            }
                            Text(isFetchingGitHubRepos ? "Fetching..." : "Fetch")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(isFetchingGitHubRepos || isImporting)

                    Button {
                        importFromGitHub()
                    } label: {
                        HStack(spacing: 8) {
                            if isImporting {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "square.and.arrow.down.fill")
                            }
                            Text("Import")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(githubImportURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting || isFetchingGitHubRepos)
                }

                if let fetchGitHubReposError {
                    Label(fetchGitHubReposError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Import From GitHub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        resetGitHubImportState()
                        showGitHubImportSheet = false
                    }
                }
            }
            .task {
                if fetchedGitHubRepos.isEmpty {
                    fetchGitHubRepositories()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func contextMenu(for project: Project) -> some View {
        Button {
            projectToRename = project
            renameText = project.name
            showRenameSheet = true
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            Task {
                do { _ = try await MainActor.run { try projectManager.duplicateProject(project) } }
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
            Task {
                do { try await MainActor.run { try projectManager.deleteProject(project) } }
                catch { showError(error) }
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var newProjectSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project App Name", text: $newProjectName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Project Name")
                } footer: {
                    Text("Choose a unique name for your project.")
                }

            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newProjectName = ""
                        newProjectGithubRepo = ""
                        showNewProjectSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createProject()
                    }
                    .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var renameSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New Name")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    TextField("Project Name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal)
                Spacer()
            }
            .padding(.top, 32)
            .navigationTitle("Rename Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showRenameSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename") { renameProject() }
                        .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    @MainActor
    private func createCollaborativeProject() {
        let name = "Collaborative Project \(projectManager.projects.count + 1)"
        do {
            let project = try projectManager.createProject(name: name)
            let creatorID = UIDevice.current.name
            let manager = CollaborationSessionStore.shared.manager(for: project, creatorID: creatorID)
            currentCollaborationManager = manager
            showCollaborationDashboard = true
        } catch {
            showError(error)
        }
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let repoInput = newProjectGithubRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            var project = try projectManager.createProject(name: name)
            // Link project-specific GitHub repo if provided (overrides global setting)
            if !repoInput.isEmpty {
                // Keep the full URL or owner/repo as provided, but trim whitespace and slashes
                let normalized = repoInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if let idx = projectManager.projects.firstIndex(where: { $0.id == project.id }) {
                    projectManager.projects[idx].githubRepo = normalized
                    project = projectManager.projects[idx]
                }
            }
            newProjectName = ""
            newProjectGithubRepo = ""
            showNewProjectSheet = false

            // Show GitHub remote setup dialog unless a repo was already specified.
            // A short delay is needed to allow the outgoing sheet to finish dismissing
            // before the new sheet is presented (SwiftUI restriction on sequential sheets).
            let sheetPresentationDelay = 0.4
            if repoInput.isEmpty {
                pendingProjectForRemote = project
                DispatchQueue.main.asyncAfter(deadline: .now() + sheetPresentationDelay) {
                    showGitHubRemoteSheet = true
                }
            } else {
                projectManager.openProject(project)
                scheduleProjectTemplatesPresentation()
            }
        } catch {
            newProjectName = ""
            newProjectGithubRepo = ""
            showNewProjectSheet = false
            showError(error)
        }
    }

    private func importFromGitHub() {
        let url = githubImportURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        isImporting = true
        Task {
            do {
                let project = try await GitHubImporter.shared.importRepository(from: url)
                await MainActor.run {
                    isImporting = false
                    resetGitHubImportState(clearFetchedRepos: false)
                    showGitHubImportSheet = false
                    // GitHub-source imports: the repo is already configured as the remote.
                    projectManager.openProject(project)
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    showGitHubImportSheet = false
                    showError(error)
                }
            }
        }
    }

    private func fetchGitHubRepositories() {
        isFetchingGitHubRepos = true
        fetchGitHubReposError = nil
        Task {
            do {
                let repos = try await GitHubService.shared.listUserRepositories()
                await MainActor.run {
                    fetchedGitHubRepos = repos
                    isFetchingGitHubRepos = false
                }
            } catch {
                await MainActor.run {
                    fetchedGitHubRepos = []
                    isFetchingGitHubRepos = false
                    fetchGitHubReposError = error.localizedDescription
                }
            }
        }
    }

    private func resetGitHubImportState(clearFetchedRepos: Bool = true) {
        githubImportURL = ""
        isImporting = false
        isFetchingGitHubRepos = false
        fetchGitHubReposError = nil
        if clearFetchedRepos {
            fetchedGitHubRepos = []
        }
    }

    private func renameProject() {
        guard let project = projectToRename else { return }
        do {
            try projectManager.renameProject(project, to: renameText)
            showRenameSheet = false
        } catch {
            showRenameSheet = false
            showError(error)
        }
    }

    private func handleZipImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    let project = try await ZipImporter.shared.importZip(at: url)
                    await MainActor.run {
                        pendingProjectForRemote = project
                        showGitHubRemoteSheet = true
                    }
                } catch {
                    await MainActor.run { showError(error) }
                }
            }
        case .failure(let error):
            showError(error)
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
                await MainActor.run { showError(error) }
            }
        }
    }

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }

    private func scheduleProjectTemplatesPresentation() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(name: .showProjectTemplatesOnOpen, object: nil)
        }
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !folderManager.folders.isEmpty {
                Text("Folders")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(folderManager.folders) { folder in
                            Button {
                                selectedFolder = folder
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let gColors = folder.gradientColors, gColors.count >= 2 {
                                        Image(systemName: folder.iconSymbol)
                                            .font(.title2)
                                            .foregroundStyle(LinearGradient(colors: [Color(hex: gColors[0]), Color(hex: gColors[1])], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    } else {
                                        Image(systemName: folder.iconSymbol)
                                            .font(.title2)
                                            .foregroundStyle(Color(hex: folder.colorHex))
                                    }

                                    Text(folder.folderName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text("\(folder.projectIdentifiers.count) project\(folder.projectIdentifiers.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .frame(width: 170, alignment: .leading)
                                .background {
                                    if let gColors = folder.gradientColors, gColors.count >= 2 {
                                        LinearGradient(colors: [Color(hex: gColors[0]).opacity(0.15), Color(hex: gColors[1]).opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                    } else {
                                        Color.white.opacity(0.05)
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    folderToRename = folder
                                    folderRenameText = folder.folderName
                                    showFolderRenameSheet = true
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    folderManager.deleteFolder(folder)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.top)
    }

    private var addToFolderSheet: some View {
        NavigationStack {
            List(folderManager.folders) { folder in
                Button {
                    if let project = projectToAssignFolder {
                        folderManager.addProject(project.id, to: folder.folderId)
                    }
                    showAddToFolderSheet = false
                } label: {
                    HStack {
                        Image(systemName: folder.iconSymbol)
                            .foregroundStyle(Color(hex: folder.colorHex))
                        Text(folder.folderName)
                        Spacer()
                        Text("\(folder.projectIdentifiers.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add To Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddToFolderSheet = false }
                }
            }
        }
    }
}

// MARK: - Project List Row (for list layout)

struct ProjectListRowView: View {
    let project: Project
    var showIcon: Bool = true
    var showPreview: Bool = false
    var showFileCount: Bool = true
    var showLastOpenedTime: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            if showIcon {
                Image(systemName: "swift")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .frame(width: 32)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if showFileCount || showLastOpenedTime {
                    HStack(spacing: 8) {
                        if showFileCount {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.fill")
                                    .font(.caption2)
                                Text("\(project.fileCount) File\(project.fileCount == 1 ? "" : "s")")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }

                        if showFileCount && showLastOpenedTime {
                            Text("·")
                                .foregroundStyle(.secondary)
                        }

                        if showLastOpenedTime {
                            Text(project.lastOpened, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if showPreview, let firstFile = project.files.first(where: { !$0.isDirectory }) {
                    Text(firstFile.name)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Share Sheet (UIActivityViewController wrapper)

import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Project Card

struct ProjectCardView: View {
    let project: Project
    var showIcon: Bool = true
    var showFileCount: Bool = true
    var showLastOpenedTime: Bool = true
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if showIcon {
                    Image(systemName: "swift")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
                Spacer()
                if showLastOpenedTime {
                    Text(project.lastOpened, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if showFileCount {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.fill")
                            .font(.caption2)
                        Text("\(project.fileCount) File\(project.fileCount == 1 ? "" : "s")")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(height: 140)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                }
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: .black.opacity(0.3), radius: isHovered ? 16 : 8, y: 4)
        .animation(.spring(response: 0.3), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
