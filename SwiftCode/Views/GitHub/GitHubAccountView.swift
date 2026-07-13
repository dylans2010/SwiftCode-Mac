import SwiftUI

@MainActor
struct GitHubAccountView: View {
    @State private var user: GitHubUserInfo?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isLoading {
                    GitHubLoadingView(message: "Loading your GitHub profile...")
                } else if let u = user {
                    // Profile Header Card
                    GroupBox {
                        VStack(spacing: 16) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(.blue)

                            Text(u.name ?? u.login)
                                .font(.title.bold())

                            Text("@\(u.login)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if let bio = u.bio, !bio.isEmpty {
                                Text(bio)
                                    .font(.body)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: 360)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Stats Grid
                    let columns = [
                        GridItem(.adaptive(minimum: 180), spacing: 16)
                    ]

                    LazyVGrid(columns: columns, spacing: 16) {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Repositories", systemImage: "folder.fill")
                                    .font(.headline)
                                    .foregroundStyle(.orange)
                                Text("\(u.publicRepos) Public")
                                    .font(.title3.bold())
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Followers", systemImage: "person.2.fill")
                                    .font(.headline)
                                    .foregroundStyle(.green)
                                Text("\(u.followers) Followers")
                                    .font(.title3.bold())
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                } else {
                    GitHubEmptyStateView(
                        title: "Account Not Loaded",
                        description: "Provide a valid GitHub Personal Access Token in Settings to load profile details.",
                        systemImage: "person.crop.circle.badge.questionmark",
                        accentColor: .blue
                    )
                }
            }
            .padding(24)
        }
        .onAppear {
            fetchUserProfile()
        }
    }

    private func fetchUserProfile() {
        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else { return }

        isLoading = true
        Task {
            do {
                guard let url = URL(string: "https://api.github.com/user") else { return }

                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                let (data, _) = try await URLSession.shared.data(for: request)
                self.user = try JSONDecoder().decode(GitHubUserInfo.self, from: data)
            } catch {
                // Silent catch
            }
            isLoading = false
        }
    }
}

struct GitHubUserInfo: Decodable {
    let login: String
    let name: String?
    let bio: String?
    let followers: Int
    let publicRepos: Int

    enum CodingKeys: String, CodingKey {
        case login, name, bio, followers
        case publicRepos = "public_repos"
    }
}
