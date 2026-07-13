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
                    // Modern Translucent Profile Card
                    GroupBox {
                        VStack(spacing: 16) {
                            if let avatarStr = u.avatarUrl, let avatarURL = URL(string: avatarStr) {
                                AsyncImage(url: avatarURL) { image in
                                    image.resizable()
                                         .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.system(size: 72))
                                        .foregroundStyle(.blue)
                                }
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.blue.opacity(0.3), lineWidth: 2))
                                .shadow(radius: 4)
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 80))
                                    .foregroundStyle(.blue)
                            }

                            VStack(spacing: 4) {
                                Text(u.name ?? u.login)
                                    .font(.title2.bold())
                                    .foregroundStyle(.primary)

                                Text("@\(u.login)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            if let bio = u.bio, !bio.isEmpty {
                                Text(bio)
                                    .font(.body)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: 420)
                                    .padding(.horizontal)
                            }

                            Divider()
                                .padding(.vertical, 4)

                            // Rich Interactive Metadata Grid
                            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                                if let company = u.company, !company.isEmpty {
                                    GridRow {
                                        Label("Company", systemImage: "building.2.fill")
                                            .foregroundColor(.secondary)
                                        Text(company)
                                            .fontWeight(.semibold)
                                    }
                                }

                                if let location = u.location, !location.isEmpty {
                                    GridRow {
                                        Label("Location", systemImage: "mappin.and.ellipse")
                                            .foregroundColor(.secondary)
                                        Text(location)
                                            .fontWeight(.semibold)
                                    }
                                }

                                if let email = u.email, !email.isEmpty {
                                    GridRow {
                                        Label("Email", systemImage: "envelope.fill")
                                            .foregroundColor(.secondary)
                                        Text(email)
                                            .fontWeight(.semibold)
                                    }
                                }

                                if let blog = u.blog, !blog.isEmpty {
                                    GridRow {
                                        Label("Website", systemImage: "link")
                                            .foregroundColor(.secondary)
                                        Text(blog)
                                            .foregroundColor(.blue)
                                            .fontWeight(.semibold)
                                            .onTapGesture {
                                                if let url = URL(string: blog.hasPrefix("http") ? blog : "https://\(blog)") {
                                                    NSWorkspace.shared.open(url)
                                                }
                                            }
                                    }
                                }

                                GridRow {
                                    Label("Hireable Status", systemImage: "briefcase.fill")
                                        .foregroundColor(.secondary)
                                    Text(u.hireable == true ? "Available for hire" : "Not open to offers")
                                        .fontWeight(.semibold)
                                        .foregroundColor(u.hireable == true ? .green : .secondary)
                                }
                            }
                            .font(.subheadline)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Numerical Stats Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Developer Statistics", systemImage: "chart.bar.fill")
                                .font(.headline)
                                .foregroundStyle(.blue)

                            Divider()

                            let columns = [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ]

                            LazyVGrid(columns: columns, spacing: 16) {
                                statBox(title: "Public Repos", value: "\(u.publicRepos)", icon: "folder.fill", color: .orange)
                                if let priv = u.totalPrivateRepos {
                                    statBox(title: "Private Repos", value: "\(priv)", icon: "lock.fill", color: .red)
                                } else {
                                    statBox(title: "Private Repos", value: "Locked", icon: "lock.fill", color: .red)
                                }
                                statBox(title: "Followers", value: "\(u.followers)", icon: "person.2.fill", color: .green)
                                statBox(title: "Following", value: "\(u.following ?? 0)", icon: "person.badge.plus", color: .purple)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Account Diagnostics & Integration Details
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Account Integration", systemImage: "shield.checkered")
                                .font(.headline)
                                .foregroundStyle(.green)

                            Divider()

                            HStack {
                                Text("Profile Created:")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if let created = u.createdAt {
                                    Text(formatGitHubDate(created))
                                        .fontWeight(.semibold)
                                } else {
                                    Text("N/A")
                                }
                            }

                            HStack {
                                Text("Profile Updated:")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if let updated = u.updatedAt {
                                    Text(formatGitHubDate(updated))
                                        .fontWeight(.semibold)
                                } else {
                                    Text("N/A")
                                }
                            }

                            HStack {
                                Text("API Token Status:")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Active (OAuth2 Token)")
                                    .fontWeight(.bold)
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding()
                        .font(.subheadline)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

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

    private func statBox(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(8)
    }

    private func formatGitHubDate(_ dateStr: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        guard let date = isoFormatter.date(from: dateStr) else { return dateStr }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
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
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                self.user = try decoder.decode(GitHubUserInfo.self, from: data)
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
    let following: Int?
    let publicRepos: Int
    let totalPrivateRepos: Int?
    let avatarUrl: String?
    let company: String?
    let blog: String?
    let location: String?
    let email: String?
    let hireable: Bool?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case login, name, bio, followers, following, company, blog, location, email, hireable
        case publicRepos = "public_repos"
        case totalPrivateRepos = "total_private_repos"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
