// Ported from SwiftCode-Legacy `SwiftCode/Views/Collaboration/CollaborationCommitHistoryView.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Thin wrapper around `CommitManagerView`; same coverage and same gap
// as that view (per-change Undo/Redo), which this wrapper inherits by
// construction.

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
