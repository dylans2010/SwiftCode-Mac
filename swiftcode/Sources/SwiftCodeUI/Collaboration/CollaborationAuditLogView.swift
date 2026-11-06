// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Views/Collaboration/CollaborationAuditLogView.swift
// Adapted for SwiftCode: reads the real CollaborationManager activity log.
// Legacy's hardcoded dark background / white text become system-adaptive
// (no forced dark paint on macOS); cards use the system thin material in
// place of Legacy's `.liquidGlass`, which has no destination equivalent.

import SwiftUI
import SwiftCodeCollaboration

@MainActor
public struct CollaborationAuditLogView: View {
    @ObservedObject var manager: CollaborationManager

    public init(manager: CollaborationManager) {
        self.manager = manager
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if manager.activityLog.isEmpty {
                    Text("No activity recorded yet.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
                ForEach(manager.activityLog) { activity in
                    ActivityEntryRow(activity: activity)
                }
            }
            .padding()
        }
        .navigationTitle("Audit Log")
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
                    Spacer()
                    Text(activity.timestamp, style: .time)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Text(activity.title)
                    .font(.subheadline.weight(.semibold))
                Text(activity.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
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
