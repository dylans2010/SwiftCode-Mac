import SwiftUI

@MainActor
struct RepositoryDetailView: View {
    let project: Project?
    @State private var repoDetails: GitHubRepoDetail?
    @State private var isLoading = false

    private var ownerAndRepo: (String, String)? {
        guard let repoStr = project?.githubRepo, !repoStr.isEmpty else { return nil }
        let parts = repoStr.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isLoading {
                    GitHubLoadingView(message: "Loading repository details...")
                } else if let details = repoDetails {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Repository Details", systemImage: "folder.fill")
                                    .font(.title2.bold())
                                    .foregroundStyle(.orange)

                                Spacer()

                                Text(details.private ? "PRIVATE" : "PUBLIC")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(details.private ? Color.yellow.opacity(0.12) : Color.green.opacity(0.12))
                                    .foregroundStyle(details.private ? .yellow : .green)
                                    .cornerRadius(4)
                            }

                            Text(details.fullName)
                                .font(.title3.bold())

                            if let desc = details.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

                            HStack(spacing: 16) {
                                Label("\(details.stargazersCount) Stars", systemImage: "star.fill")
                                    .foregroundStyle(.yellow)
                                Label("\(details.forksCount) Forks", systemImage: "arrow.branch")
                                    .foregroundStyle(.purple)
                                Label("\(details.openIssuesCount) Issues", systemImage: "exclamationmark.circle.fill")
                                    .foregroundStyle(.cyan)
                            }
                            .font(.subheadline)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Clone URLs", systemImage: "link")
                                .font(.headline)
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("HTTPS Clone URL")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Text(details.cloneUrl)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(6)

                                if let ssh = details.sshUrl {
                                    Text("SSH Clone URL")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 4)
                                    Text(ssh)
                                        .font(.system(.body, design: .monospaced))
                                        .padding(8)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(6)
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                } else {
                    GitHubEmptyStateView(
                        title: "No Repository Connected",
                        description: "Go to Repositories to search and connect a remote GitHub repository to this project.",
                        systemImage: "folder.badge.questionmark",
                        accentColor: .orange
                    )
                }
            }
            .padding(24)
        }
        .onAppear {
            fetchDetails()
        }
    }

    private func fetchDetails() {
        guard let (owner, repo) = ownerAndRepo else { return }
        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else { return }

        isLoading = true
        Task {
            do {
                guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)") else { return }

                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                let (data, _) = try await URLSession.shared.data(for: request)
                self.repoDetails = try JSONDecoder().decode(GitHubRepoDetail.self, from: data)
            } catch {
                // Silent catch
            }
            isLoading = false
        }
    }
}

struct GitHubRepoDetail: Decodable {
    let id: Int
    let fullName: String
    let description: String?
    let `private`: Bool
    let cloneUrl: String
    let sshUrl: String?
    let stargazersCount: Int
    let forksCount: Int
    let openIssuesCount: Int

    enum CodingKeys: String, CodingKey {
        case id, description, `private`
        case fullName = "full_name"
        case cloneUrl = "clone_url"
        case sshUrl = "ssh_url"
        case stargazersCount = "stargazers_count"
        case forksCount = "forks_count"
        case openIssuesCount = "open_issues_count"
    }
}
