import SwiftUI

public struct NSCherryPickView: View {
    @State private var commitSHA = ""
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    // Paginated list state
    @State private var commits: [GitHubCommit] = []
    @State private var currentPage = 1
    @State private var isFetching = false
    @State private var hasMoreCommits = true
    @State private var selectedCommitSHA: String? = nil

    public init() {}

    public var body: some View {
        Group {
            if let project = ProjectSessionStore.shared.activeProject {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Git Cherry Pick (⇧⌘K)", systemImage: "arrow.triangle.pull")
                        .font(.headline)
                        .foregroundStyle(.purple)

                    Text("Apply change introduced by existing commit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Commit SHA (e.g. d6f3e12)...", text: $commitSHA)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isLoading)
                        .onChange(of: commitSHA) { _, newValue in
                            // If user manually types SHA, sync selected SHA if it matches
                            if selectedCommitSHA != newValue {
                                selectedCommitSHA = nil
                            }
                        }

                    // Commits list section
                    Text("Select a commit from history:")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(commits) { commit in
                                    let isSelected = selectedCommitSHA == commit.sha
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Image(systemName: "circle.hexagongrid.fill")
                                                .font(.system(size: 10))
                                                .foregroundStyle(isSelected ? .purple : .secondary)

                                            Text(String(commit.sha.prefix(7)))
                                                .font(.system(.caption2, design: .monospaced))
                                                .bold()
                                                .foregroundStyle(isSelected ? .purple : .primary)

                                            Spacer()

                                            if let authorName = commit.commit.author?.name {
                                                Text(authorName)
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }

                                        Text(commit.commit.message)
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isSelected ? Color.purple.opacity(0.15) : Color.secondary.opacity(0.05))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 1)
                                    )
                                    .onTapGesture {
                                        selectedCommitSHA = commit.sha
                                        commitSHA = commit.sha
                                    }
                                    .onAppear {
                                        if commit.id == commits.last?.id && hasMoreCommits && !isFetching {
                                            Task {
                                                await fetchNextPage(project: project)
                                            }
                                        }
                                    }
                                }

                                if isFetching {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .controlSize(.small)
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                } else if !hasMoreCommits {
                                    Text("No More Commits")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 8)
                                }
                            }
                            .padding(2)
                        }
                    }
                    .frame(height: 150)
                    .padding(4)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(8)

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

                    Button("Apply Commit") {
                        let sha = commitSHA.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !sha.isEmpty else { return }
                        Task {
                            isLoading = true
                            successMsg = ""
                            errorMsg = ""
                            do {
                                try await GitMenuBarCommandExecutor.runGit(args: ["cherry-pick", sha])
                                successMsg = "Successfully cherry-picked commit: \(sha)"
                                commitSHA = ""
                                selectedCommitSHA = nil
                            } catch {
                                errorMsg = "Failed: \(error.localizedDescription)"
                            }
                            isLoading = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(commitSHA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
                .onAppear {
                    Task {
                        await loadInitialCommits(project: project)
                    }
                }
            } else {
                NoActiveProjectView(title: "Cherry Pick")
            }
        }
        .padding()
        .frame(width: 280)
    }

    private func loadInitialCommits(project: Project) async {
        guard let repoURL = project.githubRepo, !repoURL.isEmpty else {
            errorMsg = "No GitHub repository linked to this project."
            return
        }
        isFetching = true
        commits = []
        currentPage = 1
        hasMoreCommits = true
        do {
            let (owner, repo) = try GitHubRepositoryManager.shared.parseRepoURL(repoURL)
            let fetched = try await fetchCommits(owner: owner, repo: repo, page: 1)
            commits = fetched
            if fetched.count < 50 {
                hasMoreCommits = false
            }
        } catch {
            errorMsg = "Failed to load commits: \(error.localizedDescription)"
        }
        isFetching = false
    }

    private func fetchNextPage(project: Project) async {
        guard let repoURL = project.githubRepo, !repoURL.isEmpty, hasMoreCommits, !isFetching else { return }
        isFetching = true
        let nextPage = currentPage + 1
        do {
            let (owner, repo) = try GitHubRepositoryManager.shared.parseRepoURL(repoURL)
            let fetched = try await fetchCommits(owner: owner, repo: repo, page: nextPage)
            if fetched.isEmpty {
                hasMoreCommits = false
            } else {
                commits.append(contentsOf: fetched)
                currentPage = nextPage
                if fetched.count < 50 {
                    hasMoreCommits = false
                }
            }
        } catch {
            errorMsg = "Failed to load more commits: \(error.localizedDescription)"
        }
        isFetching = false
    }

    private func fetchCommits(owner: String, repo: String, page: Int, perPage: Int = 50) async throws -> [GitHubCommit] {
        let token = APIKeyManager.shared.retrieveKey(service: .gitHub) ?? KeychainService.shared.get(forKey: KeychainService.githubToken)

        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/commits?per_page=\(perPage)&page=\(page)"
        guard let url = URL(string: urlString) else {
            throw GitHubError.invalidPath
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("SwiftCodeIDE", forHTTPHeaderField: "User-Agent")
        if let token = token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubError.apiError(statusCode: httpResponse.statusCode, body: body)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([GitHubCommit].self, from: data)
    }
}
