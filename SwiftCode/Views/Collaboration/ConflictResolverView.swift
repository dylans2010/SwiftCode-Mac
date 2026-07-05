import SwiftUI

struct ConflictResolverView: View {
    @ObservedObject var manager: CollaborationManager
    let actorID: String

    var body: some View {
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
