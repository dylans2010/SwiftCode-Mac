import SwiftUI

@MainActor
struct GitHubAccountView: View {
    @State private var user: GitHubUserInfo?
    @State private var isLoading = false

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    GitHubLoadingView(message: "Loading your GitHub profile...")
                    Spacer()
                }
                .padding(.vertical, 40)
            } else if let u = user {
                // Section 1: Profile Details
                Section(header: Text("GitHub Profile").font(.system(size: 10, weight: .bold)).foregroundStyle(.blue)) {
                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            if let avatarStr = u.avatarUrl, let avatarURL = URL(string: avatarStr) {
                                AsyncImage(url: avatarURL) { image in
                                    image.resizable()
                                         .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.blue)
                                }
                                .frame(width: 50, height: 50)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.blue.opacity(0.3), lineWidth: 1))
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundStyle(.blue)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(u.name ?? u.login)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text("@\(u.login)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        if let bio = u.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Divider()

                        // Grid for profile properties
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 8)
                }

                // Section 2: Developer Statistics
                Section(header: Text("Developer Statistics").font(.system(size: 10, weight: .bold)).foregroundStyle(.green)) {
                    statBox(title: "Public Repositories", value: "\(u.publicRepos)", icon: "folder.fill", color: .orange)
                    if let priv = u.totalPrivateRepos {
                        statBox(title: "Private Repositories", value: "\(priv)", icon: "lock.fill", color: .red)
                    } else {
                        statBox(title: "Private Repositories", value: "Locked", icon: "lock.fill", color: .red)
                    }
                    statBox(title: "Followers", value: "\(u.followers)", icon: "person.2.fill", color: .green)
                    statBox(title: "Following", value: "\(u.following ?? 0)", icon: "person.badge.plus", color: .purple)
                }

                // Section 3: Account Integration
                Section(header: Text("Account Integration").font(.system(size: 10, weight: .bold)).foregroundStyle(.purple)) {
                    HStack {
                        Label("Profile Created", systemImage: "calendar")
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
                        Label("Profile Updated", systemImage: "calendar.badge.clock")
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
                        Label("API Token Status", systemImage: "shield.checkered")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Active (OAuth2 Token)")
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                    }
                }
            } else {
                HStack {
                    Spacer()
                    GitHubEmptyStateView(
                        title: "Account Not Loaded",
                        description: "Provide a valid GitHub Personal Access Token in Settings to load profile details.",
                        systemImage: "person.crop.circle.badge.questionmark",
                        accentColor: .blue
                    )
                    Spacer()
                }
            }
        }
        .listStyle(.sidebar)
        .onAppear {
            fetchUserProfile()
        }
    }

    private func statBox(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 24, height: 24)

            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.headline)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 4)
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
