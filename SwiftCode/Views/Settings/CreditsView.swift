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

    private static var groupedBackground: Color {
#if canImport(UIKit)
        Color(UIColor.systemGroupedBackground)
#elseif canImport(AppKit)
        Color(nsColor: NSColor.windowBackgroundColor)
#else
        Color.primary.opacity(0.04)
#endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if isLoading && profiles.isEmpty {
                        ProgressView("Loading profiles…")
                            .padding(.top, 32)
                    }

                    ForEach(profiles) { profile in
                        GitHubProfileCard(profile: profile)
                    }
                }
                .padding()
            }
            .background(Self.groupedBackground)
            .navigationTitle("Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if profiles.isEmpty {
                    await loadProfiles()
                }
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

    private static var secondaryGroupedBackground: Color {
#if canImport(UIKit)
        Color(UIColor.secondarySystemGroupedBackground)
#elseif canImport(AppKit)
        Color(nsColor: NSColor.controlBackgroundColor)
#else
        Color.secondary.opacity(0.08)
#endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
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
                    .font(.subheadline)
            }

            HStack(spacing: 16) {
                Label("\(profile.followers)", systemImage: "person.2")
                Label("\(profile.publicRepos)", systemImage: "folder")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let profileURL = URL(string: profile.htmlURL) {
                Link(destination: profileURL) {
                    Label("View GitHub Profile", systemImage: "arrow.up.right.square")
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Self.secondaryGroupedBackground)
        )
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
