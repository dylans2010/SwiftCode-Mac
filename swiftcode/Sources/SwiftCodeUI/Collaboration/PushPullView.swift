// Ported from SwiftCode-Legacy `SwiftCode/Views/Collaboration/PushPullView.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Thin wrapper around `PushPullManagerView`; same coverage and same gap
// as that view (branch-sync UI with progress, Sync Across Peers, live
// conflict detection, Active Transfers), which this wrapper inherits
// by construction.

import Foundation
import SwiftUI
import SwiftCodeCollaboration

@MainActor
public struct PushPullView: View {
    @ObservedObject var manager: CollaborationManager

    public init(manager: CollaborationManager) {
        self.manager = manager
    }

    public var body: some View {
        PushPullManagerView(manager: manager, actorID: Host.current().localizedName ?? "macOS Device")
    }
}
