import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profiles: [GitHubProfile] = []
    @State private var isLoading = false

    private let usernames = ["dylans2010", "aoyn1xw"]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Contributors Header Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Contributors", systemImage: "person.2.fill")
                                .font(.headline)
                                .foregroundColor(.cyan)
                            Spacer()
                        }

                        Text("Meet the brilliant minds and open-source contributors powering the SwiftCode IDE platform.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                if isLoading && profiles.isEmpty {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Loading profiles…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 32)
                } else {
                    VStack(spacing: 16) {
                        ForEach(profiles) { profile in
                            GitHubProfileCard(profile: profile)
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Credits")
        .task {
            if profiles.isEmpty {
                await loadProfiles()
            }
        }
    }

    private func loadProfiles() async {
        isLoading = true
        defer { isLoading = false }

        var loaded: [GitHubProfile] = []
        for username in usernames {
            if let profile = try? await GitHubProfileService.shared.fetchProfile(username: username) {
                loaded.append(profile)
            }
        }
        profiles = loaded
    }
}

private struct GitHubProfileCard: View {
    let profile: GitHubProfile

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    AsyncImage(url: URL(string: profile.avatarURL)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color.secondary.opacity(0.15))
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.name ?? profile.login)
                            .font(.headline)
                        Text("@\(profile.login)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if let bio = profile.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }

                Divider()

                HStack(spacing: 24) {
                    Label("\(profile.followers) followers", systemImage: "person.2")
                    Label("\(profile.publicRepos) public repos", systemImage: "folder")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let profileURL = URL(string: profile.htmlURL) {
                    Link(destination: profileURL) {
                        Label("View GitHub Profile", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }
}

private struct GitHubProfile: Decodable, Identifiable {
    let id: Int
    let login: String
    let name: String?
    let bio: String?
    let avatarURL: String
    let htmlURL: String
    let followers: Int
    let publicRepos: Int

    enum CodingKeys: String, CodingKey {
        case id, login, name, bio, followers
        case avatarURL = "avatar_url"
        case htmlURL = "html_url"
        case publicRepos = "public_repos"
    }
}

private final class GitHubProfileService: Sendable {
    static let shared = GitHubProfileService()
    private init() {}

    func fetchProfile(username: String) async throws -> GitHubProfile {
        guard let url = URL(string: "https://api.github.com/users/\(username)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SwiftCode", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(GitHubProfile.self, from: data)
    }
}
