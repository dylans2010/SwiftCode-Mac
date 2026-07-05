import SwiftUI

@MainActor
struct CollaborationCommitHistoryView: View {
    @ObservedObject var manager: CollaborationManager

    var body: some View {
        CommitManagerView(manager: manager, actorID: Host.current().localizedName ?? "macOS Device")
    }
}
