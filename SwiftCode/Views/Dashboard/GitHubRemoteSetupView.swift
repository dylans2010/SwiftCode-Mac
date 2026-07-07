import SwiftUI

struct GitHubRemoteSetupView: View {
    let project: Project

    let onComplete: (Project?) -> Void

    @EnvironmentObject private var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: RemoteSetupTab = .existing
    @State private var availableRepos: [GitHubRepoSummary] = []
    @State private var isLoadingRepos = false
    @State private var repoLoadError: String?
    @State private var selectedRepo: GitHubRepoSummary?

    @State private var newRepoName: String = ""
    @State private var newRepoDescription: String = ""
    @State private var newRepoIsPrivate = false
    @State private var isCreatingRepo = false
    @State private var createError: String?

    enum RemoteSetupTab: String, CaseIterable {
        case existing = "Existing Repo"
        case create   = "Create Repo"
    }

    var body: some View {
        NavigationStack {
            Form {
                // Header
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Configure GitHub Remote", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.headline)
                        Text("Link \"\(project.name)\" to a GitHub repository. You can also skip and configure this later from inside the project.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Tab picker
                Section {
                    Picker("Setup Method", selection: $selectedTab) {
                        ForEach(RemoteSetupTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Content per tab
                switch selectedTab {
                case .existing:
                    existingRepoSection
                case .create:
                    createRepoSection
                }
            }
            .navigationTitle("Link Repository")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        dismiss()
                        onComplete(nil)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    confirmButton
                }
            }
            .task {
                await loadRepositories()
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Existing Repo Section

    @ViewBuilder
    private var existingRepoSection: some View {
        Section {
            if isLoadingRepos {
                HStack {
                    ProgressView()
                        .padding(.trailing, 6)
                    Text("Loading Repositories…")
                        .foregroundStyle(.secondary)
                }
            } else if let error = repoLoadError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Button("Retry") {
                    Task { await loadRepositories() }
                }
            } else if availableRepos.isEmpty {
                Text("No repositories found. Make sure your GitHub token has the correct permissions and try again.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(availableRepos) { repo in
                    Button {
                        selectedRepo = (selectedRepo?.id == repo.id) ? nil : repo
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                                .foregroundStyle(repo.isPrivate ? Color.secondary : Color.blue)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(repo.fullName)
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                if let desc = repo.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if selectedRepo?.id == repo.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Your Repositories")
        } footer: {
            Text("Select the repository you want to use as the remote for this project.")
        }
    }

    // MARK: - Create Repo Section

    @ViewBuilder
    private var createRepoSection: some View {
        Section {
            TextField("Repository Name", text: $newRepoName)
                .autocorrectionDisabled()
            TextField("Description (Optional)", text: $newRepoDescription)
                .autocorrectionDisabled()
            Toggle("Private Repository", isOn: $newRepoIsPrivate)
        } header: {
            Text("New Repository Details")
        } footer: {
            Text("A new repository will be created on GitHub and set as the remote for this project.")
        }

        if let error = createError {
            Section {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    // MARK: - Confirm Button

    @ViewBuilder
    private var confirmButton: some View {
        switch selectedTab {
        case .existing:
            Button("Select") {
                confirmExistingRepo()
            }
            .disabled(selectedRepo == nil)
        case .create:
            Button {
                Task { await confirmCreateRepo() }
            } label: {
                if isCreatingRepo {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Create")
                }
            }
            .disabled(newRepoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreatingRepo)
        }
    }

    // MARK: - Actions

    private func loadRepositories() async {
        isLoadingRepos = true
        repoLoadError = nil
        do {
            let repos = try await GitHubService.shared.listUserRepositories()
            await MainActor.run {
                availableRepos = repos
                isLoadingRepos = false
            }
        } catch {
            await MainActor.run {
                repoLoadError = error.localizedDescription
                isLoadingRepos = false
            }
        }
    }

    private func confirmExistingRepo() {
        guard let repo = selectedRepo else { return }
        var updated = project
        updated.githubRepo = repo.fullName
        applyRemote(to: updated)
    }

    private func confirmCreateRepo() async {
        let name = newRepoName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isCreatingRepo = true
        createError = nil
        do {
            let created = try await GitHubService.shared.createRepository(
                name: name,
                description: newRepoDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                isPrivate: newRepoIsPrivate
            )
            await MainActor.run {
                isCreatingRepo = false
                var updated = project
                updated.githubRepo = created.fullName
                applyRemote(to: updated)
            }
        } catch {
            await MainActor.run {
                isCreatingRepo = false
                createError = error.localizedDescription
            }
        }
    }

    /// Persists the `githubRepo` field in ProjectManager and calls the completion handler.
    private func applyRemote(to project: Project) {
        if let idx = projectManager.projects.firstIndex(where: { $0.id == project.id }) {
            projectManager.projects[idx].githubRepo = project.githubRepo
        }
        dismiss()
        onComplete(project)
    }
}
