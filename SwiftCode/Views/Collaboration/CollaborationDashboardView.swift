import SwiftUI

@MainActor
public struct CollaborationDashboardView: View {
    @ObservedObject var manager: CollaborationManager
    let actorID: String

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Statistics
                HStack(spacing: 16) {
                    StatCard(title: "Branch", value: manager.branches.currentBranch.name, icon: "arrow.triangle.branch", color: .blue)
                    StatCard(title: "Reviewers", value: "\(manager.permissions.memberRoles.count)", icon: "person.3.fill", color: .purple)
                }
                .padding(.horizontal)

                HStack(spacing: 16) {
                    StatCard(title: "Open PRs", value: "\(manager.pullRequests.pullRequests.filter { $0.status == .open }.count)", icon: "tray.full.fill", color: .orange)
                    StatCard(title: "Unread", value: "\(manager.notifications.filter { !$0.isRead }.count)", icon: "bell.badge.fill", color: .red)
                }
                .padding(.horizontal)

                // Recent Activity
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recent Activity")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal)

                    VStack(spacing: 12) {
                        ForEach(manager.activityLog.prefix(5)) { activity in
                            ActivityRow(activity: activity)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                }

                // Collaborators
                VStack(alignment: .leading, spacing: 16) {
                    Text("Team Presence")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(manager.activeUsers) { user in
                                CollaboratorMiniCard(user: user)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(.vertical)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.white)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct ActivityRow: View {
    let activity: CollaborationActivity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconForKind(activity.kind))
                .font(.caption)
                .foregroundStyle(colorForKind(activity.kind))
                .frame(width: 24, height: 24)
                .background(colorForKind(activity.kind).opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(activity.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(activity.timestamp, style: .time)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func iconForKind(_ kind: CollaborationActivity.Kind) -> String {
        switch kind {
        case .branch: return "arrow.triangle.branch"
        case .commit: return "shippingbox"
        case .review: return "checkmark.bubble"
        case .pullRequest: return "tray"
        case .sync: return "arrow.2.circlepath"
        case .invite: return "person.badge.plus"
        case .permissions: return "lock"
        case .conflict: return "exclamationmark.triangle"
        case .fileLock: return "lock.doc"
        case .chat: return "bubble.left"
        }
    }

    private func colorForKind(_ kind: CollaborationActivity.Kind) -> Color {
        switch kind {
        case .branch: return .blue
        case .commit: return .green
        case .review: return .purple
        case .pullRequest: return .orange
        case .sync: return .teal
        case .invite: return .pink
        case .permissions: return .yellow
        case .conflict: return .red
        case .fileLock: return .indigo
        case .chat: return .cyan
        }
    }
}

struct CollaboratorMiniCard: View {
    let user: UserPresence

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 32, height: 32)
                Text(String(user.id.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(user.id)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                if let file = user.currentFile {
                    Text((file as NSString).lastPathComponent)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Idle")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
