import SwiftUI

@MainActor
struct ActivityFeedView: View {
    let project: Project?
    @State private var events: [GitHubEventInfo] = []
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
            HStack {
                Label("Repository Activity Feed", systemImage: "bolt.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Spacer()

                Button {
                    fetchEvents()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isFetching)
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            if isFetching {
                GitHubLoadingView(message: "Loading repository activity...")
            } else if events.isEmpty {
                GitHubEmptyStateView(
                    title: "No Activity",
                    description: "No recent activity has been recorded in this repository's feed.",
                    systemImage: "bolt.slash",
                    accentColor: .orange
                )
            } else {
                List(events) { item in
                    HStack(spacing: 16) {
                        Image(systemName: "circle.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.type)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            Text("By \(item.actor.login) on \(item.createdAt)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .onAppear {
            fetchEvents()
        }
    }

    private func fetchEvents() {
        guard let (owner, repo) = ownerAndRepo else { return }
        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else { return }

        isFetching = true
        Task {
            do {
                guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/events?per_page=15") else { return }

                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                let (data, _) = try await URLSession.shared.data(for: request)
                self.events = try JSONDecoder().decode([GitHubEventInfo].self, from: data)
            } catch {
                // Silent catch
            }
            isFetching = false
        }
    }
}

struct GitHubEventInfo: Identifiable, Decodable {
    let id: String
    let type: String
    let actor: EventActor
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, type, actor
        case createdAt = "created_at"
    }

    struct EventActor: Decodable {
        let login: String
    }
}
