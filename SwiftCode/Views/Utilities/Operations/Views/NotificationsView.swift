import SwiftUI

struct NotificationsView: View {
    @State private var nm = NotificationCenterManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notification Center")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Certificates expiration, failing compilation warns, and updates alert logs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    nm.markAllAsRead()
                } label: {
                    Text("Mark All as Read")
                }
                .buttonStyle(.bordered)
                .disabled(nm.notifications.allSatisfy { $0.isRead })
            }
            .padding(16)

            Divider()

            if nm.notifications.isEmpty {
                ContentUnavailableView {
                    Label("No Notifications", systemImage: "bell.slash")
                } description: {
                    Text("You're completely up to date! System warnings will alert here.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(nm.notifications) { notif in
                    GroupBox {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(notif.isRead ? Color.clear : Color.blue)
                                .frame(width: 8, height: 8)

                            Image(systemName: iconForType(notif.type))
                                .font(.title3)
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(notif.title)
                                    .font(.headline)
                                Text(notif.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(formatDate(notif.date))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(6)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 16)
            }
        }
        .onAppear {
            nm.loadNotifications()
        }
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "Certificate": return "key.fill"
        case "Package": return "puzzlepiece.fill"
        default: return "bell.fill"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}
