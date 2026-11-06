// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Views/Collaboration/CollaborationNotificationCenterView.swift
// Adapted for SwiftCode: reads the real CollaborationManager.notifications
// (CollaborationNotificationItem) and marks read via
// CollaborationManager.markNotificationRead. Legacy's hardcoded dark
// background / white text become system-adaptive; cards use the system
// thin material in place of Legacy's `.liquidGlass`, which has no
// destination equivalent.

import SwiftUI
import SwiftCodeCollaboration

@MainActor
public struct CollaborationNotificationCenterView: View {
    @ObservedObject var manager: CollaborationManager
    @Environment(\.dismiss) private var dismiss

    public init(manager: CollaborationManager) {
        self.manager = manager
    }

    public var body: some View {
        NavigationStack {
            if manager.notifications.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.secondary)
                    Text("No Notifications")
                        .font(.title3.bold())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .disabled(manager.notifications.allSatisfy { $0.isRead })
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
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(notification.isRead ? Color.secondary.opacity(0.25) : Color.blue.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
