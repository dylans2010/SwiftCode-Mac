import SwiftUI

@MainActor
struct OrganizationsView: View {
    @State private var organizations: [GitHubOrgInfo] = []
    @State private var isFetching = false

    var body: some View {
        VStack(spacing: 0) {
            // Header actions row
            HStack {
                Label("GitHub Organizations", systemImage: "building.2.fill")
                    .font(.headline)
                    .foregroundStyle(.purple)

                Spacer()

                Button {
                    fetchOrgs()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isFetching)
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            if isFetching {
                GitHubLoadingView(message: "Loading organizations...")
            } else if organizations.isEmpty {
                GitHubEmptyStateView(
                    title: "No Organizations Found",
                    description: "No GitHub organizations were resolved for your account.",
                    systemImage: "building.2",
                    accentColor: .purple
                )
            } else {
                List(organizations) { org in
                    HStack(spacing: 16) {
                        Image(systemName: "building.2.fill")
                            .foregroundStyle(.purple)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(org.login)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            if let desc = org.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .onAppear {
            fetchOrgs()
        }
    }

    private func fetchOrgs() {
        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else { return }

        isFetching = true
        Task {
            do {
                guard let url = URL(string: "https://api.github.com/user/orgs") else { return }

                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                let (data, _) = try await URLSession.shared.data(for: request)
                self.organizations = try JSONDecoder().decode([GitHubOrgInfo].self, from: data)
            } catch {
                // Silent catch
            }
            isFetching = false
        }
    }
}

struct GitHubOrgInfo: Identifiable, Decodable {
    let id: Int
    let login: String
    let description: String?
}
