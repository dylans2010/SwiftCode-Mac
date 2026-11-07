import YcodeAssistant
import SwiftCodeGitHub
import SwiftUI

@MainActor
public struct GitHubAccountView: View {
    public var client: GitHubClient
    public var store: SecretStore
    public var onSignOut: () -> Void

    @State private var user: GitHubUser?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSignOutConfirm = false

    public init(client: GitHubClient, store: SecretStore = defaultSecretStore(), onSignOut: @escaping () -> Void) {
        self.client = client
        self.store = store
        self.onSignOut = onSignOut
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLoading {
                ProgressView("Loading account…")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let user {
                profileHeader(user: user)
                Divider()
                profileDetails(user: user)
                Divider()
                statsGrid(user: user)
                Spacer()
                Button("Sign Out", role: .destructive) {
                    showSignOutConfirm = true
                }
                .buttonStyle(.bordered)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Could Not Load Account",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text(errorMessage)
                )
                Button("Try Again") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .task { await load() }
        .alert("Sign out of GitHub?", isPresented: $showSignOutConfirm) {
            Button("Sign Out", role: .destructive) { signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the stored GitHub token from the keychain. You will need to sign in again to use GitHub features.")
        }
    }

    private func profileHeader(user: GitHubUser) -> some View {
        HStack(spacing: 14) {
            AsyncImage(url: user.avatarUrl.flatMap(URL.init(string:))) { image in
                image.resizable()
            } placeholder: {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(user.name ?? user.login)
                    .font(.title2.bold())
                Text("@\(user.login)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func profileDetails(user: GitHubUser) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let company = user.company, !company.isEmpty {
                Label(company, systemImage: "building.2")
            }
            if let location = user.location, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
            }
            if let blog = user.blog, !blog.isEmpty {
                Label(blog, systemImage: "link")
            }
            if let email = user.email, !email.isEmpty {
                Label(email, systemImage: "envelope")
            }
            if let hireable = user.hireable {
                Label(hireable ? "Available for hire" : "Not looking for work", systemImage: "briefcase")
            }
            if let createdAt = user.createdAt {
                Label("Joined \(createdAt, style: .date)", systemImage: "calendar")
            }
        }
        .font(.subheadline)
    }

    private func statsGrid(user: GitHubUser) -> some View {
        HStack(spacing: 24) {
            stat(value: user.followers, label: "Followers")
            stat(value: user.following, label: "Following")
            stat(value: user.publicRepos, label: "Public Repos")
            stat(value: user.totalPrivateRepos, label: "Private Repos")
        }
    }

    private func stat(value: Int?, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value.map(String.init) ?? "—")
                .font(.title3.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            user = try await client.getAuthenticatedUser()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signOut() {
        store.delete(SecretAccount.githubToken)
        onSignOut()
    }
}
