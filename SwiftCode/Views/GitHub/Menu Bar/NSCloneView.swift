import SwiftUI

public struct NSCloneView: View {
    @State private var cloneURL = ""
    @State private var repositories: [GitHubRepoSummary] = []
    @State private var selectedRepositoryID: Int?
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false
    @State private var showReplaceAlert = false
    @State private var pendingRemoteURL: URL?

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Git Clone (⇧⌘I)", systemImage: "plus.square.on.square")
                .font(.headline)
                .foregroundStyle(.green)

            Text("Clone a repository into your workspace. Cloning into an active project replaces its local code after confirmation.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Repository URL...", text: $cloneURL)
                .textFieldStyle(.roundedBorder)
                .disabled(isLoading)

            Picker("My Repositories", selection: $selectedRepositoryID) {
                Text("Use URL").tag(nil as Int?)
                ForEach(repositories) { repository in
                    Text(repository.fullName).tag(repository.id as Int?)
                }
            }
            .pickerStyle(.menu)
            .disabled(isLoading || repositories.isEmpty)
            .onChange(of: selectedRepositoryID) { _, newValue in
                guard let newValue, let repository = repositories.first(where: { $0.id == newValue }) else { return }
                cloneURL = repository.htmlUrl
            }

            Button("Fetch My Repositories") {
                Task { await fetchRepositories() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isLoading)

            if isLoading {
                ProgressView()
                    .progressViewStyle(.linear)
                    .padding(.vertical, 4)
            }

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if !errorMsg.isEmpty {
                Text(errorMsg)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Clone Repository") {
                prepareClone()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(cloneURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
        }
        .padding()
        .frame(width: 280)
        .alert("Replace Local Code?", isPresented: $showReplaceAlert) {
            Button("Replace and Clone", role: .destructive) {
                if let pendingRemoteURL {
                    Task { await clone(remoteURL: pendingRemoteURL, replaceActiveProject: true) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the active project's local files and replace them with the selected repository contents. Make sure any unsaved work is backed up before continuing.")
        }
    }

    private func fetchRepositories() async {
        isLoading = true
        successMsg = ""
        errorMsg = ""
        defer { isLoading = false }

        do {
            repositories = try await GitHubService.shared.listUserRepositories()
            if repositories.isEmpty {
                errorMsg = "No repositories were returned for this GitHub account."
            }
        } catch {
            errorMsg = "Failed to fetch repositories: \(error.localizedDescription)"
        }
    }

    private func prepareClone() {
        let urlStr = cloneURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let remoteURL = URL(string: urlStr) else {
            errorMsg = "Invalid repository URL."
            return
        }

        if ProjectSessionStore.shared.activeProject != nil {
            pendingRemoteURL = remoteURL
            showReplaceAlert = true
        } else {
            Task { await clone(remoteURL: remoteURL, replaceActiveProject: false) }
        }
    }

    private func clone(remoteURL: URL, replaceActiveProject: Bool) async {
        isLoading = true
        successMsg = ""
        errorMsg = ""
        defer { isLoading = false }

        do {
            let token = APIKeyManager.shared.retrieveKey(service: .gitHub) ?? KeychainService.shared.get(forKey: KeychainService.githubToken)
            let destinationURL: URL
            if replaceActiveProject, let project = ProjectSessionStore.shared.activeProject {
                destinationURL = project.directoryURL
                let temporaryURL = CodingManager.shared.projectsRoot.appendingPathComponent(".swiftcode-clone-\(UUID().uuidString)")
                try await GitService.shared.clone(remoteURL: remoteURL, destinationURL: temporaryURL, token: token)
                try replaceContents(of: destinationURL, with: temporaryURL)
                try? FileManager.default.removeItem(at: temporaryURL)
                ProjectSessionStore.shared.updateProjectSettings(description: project.description, githubRepo: repositoryFullName(from: remoteURL), for: project)
            } else {
                var repoName = remoteURL.deletingPathExtension().lastPathComponent
                if repoName.isEmpty { repoName = "ClonedRepository" }
                destinationURL = CodingManager.shared.projectsRoot.appendingPathComponent(repoName)
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    throw GitMenuBarError.gitError("Folder '\(repoName)' already exists.")
                }
                try await GitService.shared.clone(remoteURL: remoteURL, destinationURL: destinationURL, token: token)
            }

            let project = try await ProjectSessionStore.shared.importProject(from: destinationURL)
            await ProjectSessionStore.shared.openProject(project)
            successMsg = "Successfully cloned and opened '\(destinationURL.lastPathComponent)'!"
            cloneURL = ""
        } catch {
            errorMsg = "Failed: \(error.localizedDescription)"
        }
    }

    private func replaceContents(of destinationURL: URL, with sourceURL: URL) throws {
        let fileManager = FileManager.default
        let existingItems = try fileManager.contentsOfDirectory(at: destinationURL, includingPropertiesForKeys: nil, options: [])
        for item in existingItems where item.lastPathComponent != "project.json" {
            try fileManager.removeItem(at: item)
        }
        let clonedItems = try fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil, options: [])
        for item in clonedItems {
            try fileManager.moveItem(at: item, to: destinationURL.appendingPathComponent(item.lastPathComponent))
        }
    }

    private func repositoryFullName(from url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 2 else { return nil }
        let owner = components[components.count - 2]
        let repo = components[components.count - 1].replacingOccurrences(of: ".git", with: "")
        return "\(owner)/\(repo)"
    }
}
