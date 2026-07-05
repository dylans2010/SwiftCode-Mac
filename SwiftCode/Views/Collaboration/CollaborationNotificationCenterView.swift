import SwiftUI

@MainActor
public struct CollaborationNotificationCenterView: View {
    @ObservedObject var manager: CollaborationManager
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()

                if manager.notifications.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.secondary)
                        Text("No Notifications")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(manager.notifications) { notification in
                                NotificationRow(notification: notification) {
                                    manager.markNotificationRead(notification.id)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mark All Read") {
                        for n in manager.notifications {
                            manager.markNotificationRead(n.id)
                        }
                    }
                }
            }
        }
    }
}

struct NotificationRow: View {
    let notification: CollaborationNotificationItem
    let onRead: () -> Void

    var body: some View {
        Button(action: onRead) {
            HStack(spacing: 12) {
                Circle()
                    .fill(notification.isRead ? Color.clear : Color.blue)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(notification.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(notification.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(notification.timestamp, style: .relative)
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding()
            .background(notification.isRead ? Color.white.opacity(0.03) : Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
