import SwiftUI

@MainActor
public struct CollaborationAuditLogView: View {
    @ObservedObject var manager: CollaborationManager

    public var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    ForEach(manager.activityLog) { activity in
                        ActivityEntryRow(activity: activity)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Audit Log")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ActivityEntryRow: View {
    let activity: CollaborationActivity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconForKind(activity.kind))
                .font(.caption)
                .foregroundStyle(colorForKind(activity.kind))
                .frame(width: 32, height: 32)
                .background(colorForKind(activity.kind).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(activity.actorID)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Text(activity.timestamp, style: .time)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Text(activity.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(activity.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
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
