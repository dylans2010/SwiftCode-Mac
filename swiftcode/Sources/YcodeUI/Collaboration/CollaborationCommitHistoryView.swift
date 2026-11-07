import Foundation
import SwiftUI
import SwiftCodeCollaboration

@MainActor
public struct CollaborationCommitHistoryView: View {
    @ObservedObject var manager: CollaborationManager

    public init(manager: CollaborationManager) {
        self.manager = manager
    }

    public var body: some View {
        CommitManagerView(manager: manager, actorID: Host.current().localizedName ?? "macOS Device")
    }
}
