import SwiftUI

public struct NSCreatePRView: View {
    @State private var prTitle = ""
    @State private var targetBranch = "main"
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        Group {
            if let project = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Create Pull Request", systemImage: "arrow.up.right.square.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    TextField("PR Title...", text: $prTitle)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isLoading)

                    TextField("Base Branch (e.g. main)...", text: $targetBranch)
                        .textFieldStyle(.roundedBorder)
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

                    Button("Publish Pull Request") {
                        let title = prTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let base = targetBranch.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty, !base.isEmpty else { return }

                        guard let repoURL = project.githubRepo, !repoURL.isEmpty else {
                            errorMsg = "No GitHub repository is linked to this project."
                            return
                        }

                        Task {
                            isLoading = true
                            successMsg = ""
                            errorMsg = ""
                            do {
                                let (owner, repo) = try GitHubRepositoryManager.shared.parseRepoURL(repoURL)
                                let currentBranch = try await GitMenuBarCommandExecutor.getCurrentBranchName()

                                let pr = try await GitHubService.shared.createPullRequest(
                                    owner: owner,
                                    repo: repo,
                                    title: title,
                                    body: "Created from SwiftCode Git Menu Bar.",
                                    head: currentBranch,
                                    base: base
                                )

                                successMsg = "PR #\(pr.number) '\(pr.title)' submitted successfully!"
                                prTitle = ""
                            } catch {
                                errorMsg = "PR creation failed: \(error.localizedDescription)"
                            }
                            isLoading = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(prTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || targetBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            } else {
                NoActiveProjectView(title: "Create PR")
            }
        }
        .padding()
        .frame(width: 280)
    }
}
