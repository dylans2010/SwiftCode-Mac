import SwiftUI

public struct NSCreateRepositoryView: View {
    @State private var repoName = ""
    @State private var isPrivate = true
    @State private var pushLocalCode = false
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        Group {
            if let project = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Create Repository (⇧⌘R)", systemImage: "folder.badge.plus")
                        .font(.headline)
                        .foregroundStyle(.blue)

                    TextField("Repository name...", text: $repoName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isLoading)

                    Toggle("Private Repository", isOn: $isPrivate)
                        .toggleStyle(.checkbox)
                        .disabled(isLoading)

                    Toggle("Push local code after creating", isOn: $pushLocalCode)
                        .toggleStyle(.checkbox)
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

                    Button("Create on GitHub") {
                        let name = repoName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }

                        Task {
                            isLoading = true
                            successMsg = ""
                            errorMsg = ""
                            do {
                                let repo = try await GitHubService.shared.createRepository(
                                    name: name,
                                    description: project.description,
                                    isPrivate: isPrivate
                                )

                                ProjectSessionStore.shared.updateProjectSettings(
                                    description: project.description,
                                    githubRepo: repo.fullName,
                                    for: project
                                )

                                if pushLocalCode, let linkedProject = ProjectSessionStore.shared.activeProject {
                                    try await GitHubService.shared.initializeGitHubRepository(for: linkedProject, logHandler: { @Sendable (_: String) in })
                                }

                                successMsg = pushLocalCode ? "Repository '\(repo.name)' created, linked, and populated successfully!" : "Repository '\(repo.name)' created and linked successfully!"
                                repoName = ""
                            } catch {
                                errorMsg = "Creation failed: \(error.localizedDescription)"
                            }
                            isLoading = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(repoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            } else {
                NoActiveProjectView(title: "Create Repo")
            }
        }
        .padding()
        .frame(width: 280)
    }
}

