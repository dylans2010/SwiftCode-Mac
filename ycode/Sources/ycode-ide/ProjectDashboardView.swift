import SwiftUI

/// Project dashboard — Legacy's `FoldersView`, `FolderCardView`,
/// `FolderCreateView`, `HomeProjectCardView` and `GitHubRemoteSetupView`,
/// rebuilt in Ycode style on top of `ProjectFolderStore`.
///
/// The host supplies the known projects and the open/delete actions (the
/// Organizer owns those); the view owns folders, symbols and the remote
/// setup sheet. Project symbols keep Legacy's UserDefaults key.
public struct ProjectDashboardView: View {
    public var projects: [URL]
    public var onOpenProject: (URL) -> Void
    public var onDeleteProject: (URL) -> Void
    public var githubToken: String?

    @State private var folderStore = ProjectFolderStore()
    @State private var selectedFolderID: UUID?
    @State private var showingCreateFolder = false
    @State private var newFolderName = ""
    @State private var remoteSetupProject: URL?

    public init(projects: [URL], onOpenProject: @escaping (URL) -> Void, onDeleteProject: @escaping (URL) -> Void, githubToken: String? = nil) {
        self.projects = projects
        self.onOpenProject = onOpenProject
        self.onDeleteProject = onDeleteProject
        self.githubToken = githubToken
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selectedFolderID) {
                Section("Folders") {
                    ForEach(folderStore.folders) { folder in
                        Label(folder.name, systemImage: "folder")
                            .tag(folder.id as UUID?)
                            .swipeActions {
                                Button("Delete", role: .destructive) { folderStore.deleteFolder(id: folder.id) }
                            }
                    }
                }
                Section("All projects") {
                    Label("All Projects", systemImage: "square.grid.2x2")
                        .tag(nil as UUID?)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingCreateFolder = true } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                }
            }
        } detail: {
            projectGrid
        }
        .sheet(isPresented: $showingCreateFolder) {
            Form {
                TextField("Folder name", text: $newFolderName)
                HStack {
                    Button("Cancel") { showingCreateFolder = false }
                    Spacer()
                    Button("Create") {
                        _ = folderStore.createFolder(name: newFolderName.isEmpty ? "Untitled Folder" : newFolderName)
                        newFolderName = ""
                        showingCreateFolder = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(minWidth: 320)
        }
        .sheet(isPresented: Binding(
            get: { remoteSetupProject != nil },
            set: { if !$0 { remoteSetupProject = nil } }
        )) {
            if let project = remoteSetupProject {
                GitHubRemoteSetupSheet(projectURL: project, token: githubToken)
            }
        }
    }

    private var visibleProjects: [URL] {
        guard let id = selectedFolderID,
              let folder = folderStore.folders.first(where: { $0.id == id }) else { return projects }
        return folderStore.projects(in: folder, allProjects: projects)
    }

    private var projectGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 16) {
                ForEach(visibleProjects, id: \.self) { url in
                    projectCard(url)
                }
            }
            .padding()
        }
        .navigationTitle(selectedFolderID.flatMap { id in folderStore.folders.first(where: { $0.id == id })?.name } ?? "All Projects")
        .overlay {
            if visibleProjects.isEmpty {
                ContentUnavailableView("No projects", systemImage: "folder", description: Text("Open a project and it appears here; add it to a folder from the sidebar."))
            }
        }
    }

    private func projectCard(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "swift")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading) {
                    Text(url.lastPathComponent).font(.headline).lineLimit(1)
                    Text(url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack {
                Button("Open") { onOpenProject(url) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button("GitHub Remote") { remoteSetupProject = url }
                    .buttonStyle(.bordered).controlSize(.small)
                Spacer()
                Button(role: .destructive) { onDeleteProject(url) } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            if let folderID = selectedFolderID {
                Button("Remove from folder") { folderStore.removeProject(url, from: folderID) }
                    .font(.caption)
            } else {
                Menu("Add to folder") {
                    ForEach(folderStore.folders) { folder in
                        Button(folder.name) { folderStore.addProject(url, to: folder.id) }
                    }
                }
                .font(.caption)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// GitHub remote setup sheet (Legacy `GitHubRemoteSetupView`).
public struct GitHubRemoteSetupSheet: View {
    public var projectURL: URL
    public var token: String?

    @State private var model: GitHubRemoteSetupModel
    @State private var selectedRepo: GitHubRemoteSetupModel.RepositorySummary?
    @State private var newRepoName = ""
    @State private var newRepoDescription = ""
    @State private var newRepoIsPrivate = false
    @State private var isCreating = false
    @State private var error: String?
    @State private var doneMessage: String?
    @Environment(\.dismiss) private var dismiss

    public init(projectURL: URL, token: String? = nil) {
        self.projectURL = projectURL
        self.token = token
        _model = State(initialValue: GitHubRemoteSetupModel(token: token))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Link \"\(projectURL.lastPathComponent)\" to a GitHub repository. You can also skip and configure this later from inside the project.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Existing repositories") {
                    if model.isLoadingRepos {
                        ProgressView("Loading repositories…")
                    } else if let repoLoadError = model.repoLoadError {
                        Text(repoLoadError).font(.caption).foregroundStyle(.red)
                    } else {
                        Picker("Repository", selection: $selectedRepo) {
                            Text("None").tag(nil as GitHubRemoteSetupModel.RepositorySummary?)
                            ForEach(model.availableRepos) { repo in
                                Text(repo.fullName).tag(repo as GitHubRemoteSetupModel.RepositorySummary?)
                            }
                        }
                    }
                    Button("Link selected repository") {
                        guard let repo = selectedRepo else { error = "Select a repository first."; return }
                        do {
                            try model.linkRemote(projectURL: projectURL, remoteURL: "https://github.com/\(repo.fullName).git")
                            doneMessage = "Linked \(repo.fullName) as origin."
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .disabled(selectedRepo == nil)
                }
                Section("Create a repository") {
                    TextField("Name", text: $newRepoName)
                    TextField("Description", text: $newRepoDescription)
                    Toggle("Private", isOn: $newRepoIsPrivate)
                    Button(isCreating ? "Creating…" : "Create and link") {
                        isCreating = true
                        Task {
                            do {
                                let repo = try await model.createRepository(name: newRepoName, description: newRepoDescription, isPrivate: newRepoIsPrivate)
                                try model.linkRemote(projectURL: projectURL, remoteURL: "https://github.com/\(repo.fullName).git")
                                doneMessage = "Created and linked \(repo.fullName)."
                            } catch {
                                self.error = error.localizedDescription
                            }
                            isCreating = false
                        }
                    }
                    .disabled(newRepoName.isEmpty || isCreating)
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if let doneMessage {
                    Text(doneMessage).font(.caption).foregroundStyle(.green)
                }
            }
            .navigationTitle("Configure GitHub Remote")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await model.loadRepositories() }
        .frame(minWidth: 480, minHeight: 420)
    }
}
