import SwiftUI

@MainActor
struct NotificationsView: View {
    @State private var notifications: [GitHubNotificationInfo] = []
    @State private var isFetching = false

    var body: some View {
        VStack(spacing: 0) {
            // Header actions row
            HStack {
                Label("GitHub Notifications Inbox", systemImage: "bell.fill")
                    .font(.headline)
                    .foregroundStyle(.yellow)

                Spacer()

                Button {
                    fetchNotifications()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isFetching)
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            if isFetching {
                GitHubLoadingView(message: "Loading notifications...")
            } else if notifications.isEmpty {
                GitHubEmptyStateView(
                    title: "Inbox Zero!",
                    description: "No unread notifications in your GitHub account. Looking clean!",
                    systemImage: "bell.slash",
                    accentColor: .yellow
                )
            } else {
                List(notifications) { item in
                    HStack(spacing: 16) {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(.yellow)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.subject.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            Text("\(item.repository.fullName) • \(item.reason)")
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
            fetchNotifications()
        }
    }

    private func fetchNotifications() {
        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else { return }

        isFetching = true
        Task {
            do {
                guard let url = URL(string: "https://api.github.com/notifications") else { return }

                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                let (data, _) = try await URLSession.shared.data(for: request)
                self.notifications = try JSONDecoder().decode([GitHubNotificationInfo].self, from: data)
            } catch {
                // Silent catch
            }
            isFetching = false
        }
    }
}

struct GitHubNotificationInfo: Identifiable, Decodable {
    let id: String
    let reason: String
    let subject: NotificationSubject
    let repository: NotificationRepo

    struct NotificationSubject: Decodable {
        let title: String
    }

    struct NotificationRepo: Decodable {
        let fullName: String
        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
        }
    }
}
