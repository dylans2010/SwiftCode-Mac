import SwiftUI
import YcodeIDECore
import SwiftCodeGitHub

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
                        NSGitErrorView(message: errorMsg)
                    }

                    Button("Create on GitHub") {
                        let name = repoName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }

                        Task {
                            isLoading = true
                            successMsg = ""
                            errorMsg = ""
                            do {
                                let token = CodingAssistantServices.shared.store.readString(SecretAccount.githubToken)
                                let repo = try await GitHubClient(tokenProvider: { token }).createRepository(
                                    name: name,
                                    description: project.description,
                                    isPrivate: isPrivate
                                )

                                ProjectSessionStore.shared.updateProjectSettings(
                                    description: project.description,
                                    githubRepo: repo.fullName,
                                    for: project
                                )

                                if pushLocalCode {
                                    try await pushLocalCodeToGitHub(fullName: repo.fullName)
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
        .liquidGlass(style: .sheet, cornerRadius: 12)
        .frame(width: 280)
    }

    private func pushLocalCodeToGitHub(fullName: String) async throws {
        let parts = fullName.split(separator: "/")
        guard parts.count == 2 else {
            throw GitMenuBarError.gitError("Invalid repository full name: \(fullName)")
        }
        let remoteURL = "https://github.com/\(parts[0])/\(parts[1]).git"
        try await GitMenuBarCommandExecutor.runGit(args: ["init"])
        _ = try? await GitMenuBarCommandExecutor.runGit(args: ["remote", "add", "origin", remoteURL])
        try await GitMenuBarCommandExecutor.runGit(args: ["add", "-A"])
        try await GitMenuBarCommandExecutor.runGit(args: ["commit", "-m", "Initial commit"])
        try await GitMenuBarCommandExecutor.runGit(args: ["push", "-u", "origin", "HEAD"])
    }
}
