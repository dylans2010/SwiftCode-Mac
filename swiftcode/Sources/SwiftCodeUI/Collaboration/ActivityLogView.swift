// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Views/Collaboration/ActivityLogView.swift
// Adapted for SwiftCode: reads the real CollaborationManager activity log
// and notifications. Legacy's `.liquidGlass` has no destination equivalent
// (specs/ide/liquid-glass-swiftcode.md) — cards use the system thin material
// instead. Legacy's iOS `swipeActions` become a macOS context menu.

import SwiftUI
import SwiftCodeCollaboration

@MainActor
struct ActivityLogView: View {
    @ObservedObject var manager: CollaborationManager
    @State private var selectedKind: CollaborationActivity.Kind?

    var body: some View {
        List {
            Section("Notifications") {
                if manager.notifications.isEmpty {
                    Text("No Notifications Yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(manager.notifications) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.headline)
                        Text(item.detail).font(.caption)
                        Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .opacity(item.isRead ? 0.6 : 1.0)
                    .contextMenu {
                        Button("Mark as Read") { manager.markNotificationRead(item.id) }
                            .disabled(item.isRead)
                    }
                }
            }

            Section("Filter") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        filterChip(title: "All", kind: nil)
                        ForEach(CollaborationActivity.Kind.allCases, id: \.self) { kind in
                            filterChip(title: kind.rawValue.capitalized, kind: kind)
                        }
                    }
                }
            }

            Section("Timeline") {
                ForEach(filteredActivity) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.title).font(.headline)
                            Spacer()
                            Text(entry.kind.rawValue.capitalized)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.detail)
                        Text("\(entry.actorID) • \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Activity Log")
    }

    private var filteredActivity: [CollaborationActivity] {
        guard let selectedKind else { return manager.activityLog }
        return manager.activityLog.filter { $0.kind == selectedKind }
    }

    private func filterChip(title: String, kind: CollaborationActivity.Kind?) -> some View {
        Button(title) { selectedKind = kind }
            .buttonStyle(.borderedProminent)
            .tint(selectedKind == kind ? .blue : .gray)
    }
}

private extension CollaborationActivity.Kind {
    // CollaborationActivity.Kind is not CaseIterable in the destination;
    // this is the filter list. It adds `.chat` to Legacy's list because
    // chat messages are now logged to the activity timeline as well
    // (CollaborationChatView sends to both the chat store and addActivity).
    static var allCases: [CollaborationActivity.Kind] {
        [.branch, .commit, .review, .pullRequest, .sync, .invite, .permissions, .conflict, .fileLock, .chat]
    }
}
