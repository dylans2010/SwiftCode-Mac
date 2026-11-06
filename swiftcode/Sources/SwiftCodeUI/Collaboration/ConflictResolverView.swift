// Ported from SwiftCode-Legacy `SwiftCode/Views/Collaboration/ConflictResolverView.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// The conflict resolver: pending branch conflicts with their local /
// remote change, and one button per `ConflictResolutionChoice`.
// Not in the migration worklists, but staged here because
// `CollaborationMainView` (batch 2) instantiates it for its
// `.conflicts` tab (and `PushPullManagerView` routes to it) and it
// exists nowhere in the destination — without it those views do not
// compile. (Legacy also has `CollaborationConflictResolverView`, a
// different view; that one is not referenced by any ported view and
// is left to its own worklist entry.)
//
// Adaptations for SwiftCode: `.liquidGlass` (no destination
// equivalent) becomes the system thin material, as in the sibling
// Collaboration views.

import Foundation
import SwiftUI
import SwiftCodeCollaboration

@MainActor
public struct ConflictResolverView: View {
    @ObservedObject var manager: CollaborationManager
    let actorID: String

    public init(manager: CollaborationManager, actorID: String) {
        self.manager = manager
        self.actorID = actorID
    }

    public var body: some View {
        List {
            if manager.pendingConflicts.isEmpty {
                Text("No branch conflicts need attention.")
                    .foregroundStyle(.secondary)
            }
            ForEach(manager.pendingConflicts) { conflict in
                Section(conflict.filePath) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Local")
                            .font(.caption.bold())
                        Text(conflict.localChange)
                        Divider()
                        Text("Remote")
                            .font(.caption.bold())
                        Text(conflict.remoteChange)
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    ForEach(ConflictResolutionChoice.allCases, id: \.self) { choice in
                        Button(choice.displayName) {
                            manager.resolveConflict(conflict.id, using: choice, actorID: actorID)
                        }
                    }
                }
            }
        }
        .navigationTitle("Conflict Resolver")
    }
}
