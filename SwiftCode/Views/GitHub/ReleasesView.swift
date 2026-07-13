import SwiftUI

@MainActor
struct ReleasesView: View {
    let project: Project?
    @Binding var showSuccess: Bool
    @Binding var successMessage: String?
    @Binding var showError: Bool
    @Binding var errorMessage: String?

    @State private var releases: [GitHubReleaseInfo] = []
    @State private var isFetching = false

    private var ownerAndRepo: (String, String)? {
        guard let repoStr = project?.githubRepo, !repoStr.isEmpty else { return nil }
        let parts = repoStr.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header actions row
            HStack(spacing: 12) {
                Label("Repository Releases", systemImage: "shippingbox.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                Spacer()

                Button {
                    fetchReleases()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isFetching)
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            if isFetching {
                GitHubLoadingView(message: "Loading releases...")
            } else if releases.isEmpty {
                GitHubEmptyStateView(
                    title: "No Releases Found",
                    description: "No GitHub releases have been published for this repository yet.",
                    systemImage: "shippingbox",
                    accentColor: .green
                )
            } else {
                List(releases) { release in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "shippingbox.fill")
                                .foregroundStyle(.green)
                            Text(release.name ?? release.tagName)
                                .font(.headline)
                            Spacer()
                            Text(release.createdAt)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        GroupBox {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Notes")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Text(release.body ?? "No release notes provided.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .onAppear {
            fetchReleases()
        }
    }

    private func fetchReleases() {
        guard let (owner, repo) = ownerAndRepo else { return }
        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else { return }

        isFetching = true
        Task {
            do {
                guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=10") else { return }

                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                let (data, _) = try await URLSession.shared.data(for: request)
                self.releases = try JSONDecoder().decode([GitHubReleaseInfo].self, from: data)
            } catch {
                errorMessage = "Failed to load releases: \(error.localizedDescription)"
                showError = true
            }
            isFetching = false
        }
    }
}

struct GitHubReleaseInfo: Identifiable, Decodable {
    let id: Int
    let tagName: String
    let name: String?
    let body: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, body
        case tagName = "tag_name"
        case createdAt = "created_at"
    }
}
